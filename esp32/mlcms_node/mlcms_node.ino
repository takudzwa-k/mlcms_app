// MLCMS sensor node: ESP32 + DHT22 (+ optional door reed switch)
// Sends live readings, a history log and hardware health to Firebase,
// and answers "Ping node" requests from the app.

#include <Arduino.h>
#include <WiFi.h>
#include <esp_timer.h>
#include <DHT.h>
#include <Firebase_ESP_Client.h>
#include <addons/TokenHelper.h>

#include "secrets.h"

// ---------- Settings ----------

#define DHT_PIN 4
#define DHT_TYPE DHT22
#define DOOR_PIN 13
#define HAS_DOOR_SENSOR true  // set to false if no reed switch is wired

const char* FW_VERSION = "1.0.0";

const unsigned long LIVE_EVERY_MS = 10UL * 1000;    // update the unit's live values
const unsigned long LOG_EVERY_MS = 60UL * 1000;     // add a history reading
const unsigned long HEALTH_EVERY_MS = 30UL * 1000;  // report hardware health
const unsigned long PING_POLL_MS = 4UL * 1000;      // look for ping requests
const unsigned long WIFI_RETRY_MS = 15UL * 1000;

// ---------- State ----------

DHT dht(DHT_PIN, DHT_TYPE);
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

unsigned long lastLive = 0, lastLog = 0, lastHealth = 0, lastPingPoll = 0, lastWifiTry = 0;
bool firstRun = true;
bool lastDoorOpen = false;
bool sensorOk = false;
int failures = 0;
float temperature = NAN, humidity = NAN;
int lastPing = 0;

String unitPath() { return String("/fridges/") + FRIDGE_ID; }
String devicePath() { return String("/devices/") + FRIDGE_ID; }

float round1(float v) { return roundf(v * 10.0f) / 10.0f; }

// Magnet near = switch closed = pin pulled LOW = door closed
bool doorIsOpen() {
#if HAS_DOOR_SENSOR
  return digitalRead(DOOR_PIN) == HIGH;
#else
  return false;
#endif
}

// Returns true when we got a fresh, valid reading.
bool readSensor() {
  float t = dht.readTemperature();
  float h = dht.readHumidity();
  if (isnan(t) || isnan(h)) {
    failures++;
    if (failures >= 3) sensorOk = false;  // three misses in a row = fault
    return false;
  }
  failures = 0;
  sensorOk = true;
  temperature = round1(t);
  humidity = round1(h);
  return true;
}

void connectWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting to Wi-Fi");
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 20000) {
    delay(400);
    Serial.print(".");
  }
  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("\nConnected. IP %s, signal %d dBm\n",
                  WiFi.localIP().toString().c_str(), WiFi.RSSI());
  } else {
    Serial.println("\nCould not connect yet. Will keep trying.");
  }
}

// ---------- Talking to Firebase ----------

void sendLive(bool door, bool withReading) {
  FirebaseJson json;
  if (withReading) {
    json.set("temperature", temperature);
    json.set("humidity", humidity);
    json.set("lastSeen/.sv", "timestamp");  // the server's clock, so no NTP needed
  }
#if HAS_DOOR_SENSOR
  json.set("doorOpen", door);
#endif
  if (Firebase.RTDB.updateNode(&fbdo, unitPath().c_str(), &json)) {
    if (withReading) {
      Serial.printf("Live: %.1f C, %.1f %%, door %s\n", temperature, humidity,
                    door ? "open" : "closed");
    }
  } else {
    Serial.printf("Live update failed: %s\n", fbdo.errorReason().c_str());
  }
}

void sendLog(bool door) {
  FirebaseJson json;
  json.set("t/.sv", "timestamp");
  json.set("temp", temperature);
  json.set("hum", humidity);
  json.set("door", door);
  String path = String("/readings/") + FRIDGE_ID;
  if (Firebase.RTDB.pushJSON(&fbdo, path.c_str(), &json)) {
    Serial.println("History reading saved");
  } else {
    Serial.printf("History save failed: %s\n", fbdo.errorReason().c_str());
  }
}

void sendHealth() {
  FirebaseJson json;
  json.set("mac", WiFi.macAddress());
  json.set("fw", FW_VERSION);
  json.set("rssi", WiFi.RSSI());
  json.set("sensorOk", sensorOk);
  json.set("uptimeS", (int)(esp_timer_get_time() / 1000000LL));
  if (!Firebase.RTDB.updateNode(&fbdo, devicePath().c_str(), &json)) {
    Serial.printf("Health update failed: %s\n", fbdo.errorReason().c_str());
  }
}

// The app writes a number to devices/{id}/pingAt; we copy it to pingAck.
void checkPing() {
  String at = devicePath() + "/pingAt";
  if (!Firebase.RTDB.getInt(&fbdo, at.c_str())) return;  // nothing asked yet

  int request = fbdo.intData();
  if (request != 0 && request != lastPing) {
    String ack = devicePath() + "/pingAck";
    if (Firebase.RTDB.setInt(&fbdo, ack.c_str(), request)) {
      lastPing = request;
      Serial.printf("Answered ping %d\n", request);
    }
  }
}

// ---------- Arduino ----------

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\nMLCMS sensor node starting");

#if HAS_DOOR_SENSOR
  pinMode(DOOR_PIN, INPUT_PULLUP);
#endif
  dht.begin();
  connectWifi();

  config.api_key = API_KEY;
  config.database_url = DATABASE_URL;
  auth.user.email = DEVICE_EMAIL;
  auth.user.password = DEVICE_PASSWORD;
  config.token_status_callback = tokenStatusCallback;

  Firebase.reconnectNetwork(true);
  fbdo.setBSSLBufferSize(4096, 1024);
  Firebase.begin(&config, &auth);

  lastDoorOpen = doorIsOpen();
}

void loop() {
  unsigned long now = millis();

  if (WiFi.status() != WL_CONNECTED) {
    if (now - lastWifiTry > WIFI_RETRY_MS) {
      lastWifiTry = now;
      Serial.println("Wi-Fi lost, reconnecting...");
      WiFi.disconnect();
      WiFi.reconnect();
    }
    return;
  }
  if (!Firebase.ready()) return;

  bool door = doorIsOpen();
  bool dueLive = firstRun || (now - lastLive >= LIVE_EVERY_MS) || (door != lastDoorOpen);

  if (dueLive) {
    lastLive = now;
    bool fresh = readSensor();
    if (!fresh) Serial.println("DHT22 read failed");

    // A dead sensor must not refresh lastSeen, so the unit shows as offline.
    // The door state is still reported.
    sendLive(door, fresh);
    lastDoorOpen = door;

    if (fresh && (firstRun || now - lastLog >= LOG_EVERY_MS)) {
      lastLog = now;
      sendLog(door);
    }
  }

  if (firstRun || now - lastHealth >= HEALTH_EVERY_MS) {
    lastHealth = now;
    sendHealth();
  }

  if (now - lastPingPoll >= PING_POLL_MS) {
    lastPingPoll = now;
    checkPing();
  }

  firstRun = false;
  delay(50);
}