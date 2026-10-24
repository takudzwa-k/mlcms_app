// MLCMS sensor node: ESP32 + DHT22 (+ door reed switch, + cooler output)
// Sends live readings, a history log and hardware health to Firebase,
// answers "Ping node", and carries out cooling requests from the app.

#include <Arduino.h>
#include <WiFi.h>
#include <esp_timer.h>
#include <DHT.h>
#include <Firebase_ESP_Client.h>
#include <addons/TokenHelper.h>

#include "secrets.h"

// 0 = find the Wi-Fi channel automatically (use this on a real board).
// In the Wokwi simulator, set WIFI_CHANNEL to 6 in secrets.h to join faster.
#ifndef WIFI_CHANNEL
#define WIFI_CHANNEL 0
#endif

// ---------- Settings ----------

#define DHT_PIN 4
#define DHT_TYPE DHT22
#define DOOR_PIN 13
#define HAS_DOOR_SENSOR true  // set to false if no reed switch is wired
#define COOLER_PIN 26         // drives a relay (or an LED while testing)

// true  = no real cooler is attached: the node simulates the cooling and adds
//         its effect to the DHT22 reading (the app labels it "simulated").
// false = a relay on COOLER_PIN drives a real cooler, and the DHT22 feels the
//         result itself, so nothing is added in software.
#define SIMULATE_COOLING true

const char* FW_VERSION = "1.2.0";

const unsigned long LIVE_EVERY_MS = 5UL * 1000;     // update the unit's live values
const unsigned long MOVING_EVERY_MS = 2UL * 1000;   // faster while the temperature is moving
const unsigned long LOG_EVERY_MS = 60UL * 1000;     // add a history reading
const unsigned long HEALTH_EVERY_MS = 30UL * 1000;  // report hardware health
const unsigned long PING_POLL_MS = 4UL * 1000;      // look for ping requests
const unsigned long COMMAND_POLL_MS = 2UL * 1000;   // look for cooling requests
const unsigned long WIFI_RETRY_MS = 30UL * 1000;

const float MAX_EFFECT = 100.0f;  // a sanity limit only; the simulated cooler has no real limit
const float HYSTERESIS = 0.5f;    // thermostat dead-band for a real cooler

// ---------- State ----------

DHT dht(DHT_PIN, DHT_TYPE);
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

unsigned long lastLive = 0, lastLog = 0, lastHealth = 0, lastPingPoll = 0;
unsigned long lastCommandPoll = 0, lastWifiTry = 0, lastPlant = 0;
bool firstRun = true;
bool lastDoorOpen = false;
bool sensorOk = false;
int failures = 0;
int lastPing = 0;

float measured = NAN;     // what the DHT22 actually measured
float temperature = NAN;  // what we report (measured + simulated cooling)
float humidity = NAN;

// Cooling requests from the app
bool hasOffset = false;   // adjust the reading by offsetReq degrees
float offsetReq = 0;
bool hasTarget = false;   // hold the unit at targetTemp
float targetTemp = 0;
long lastCmd = 0;         // id of the last request we carried out
bool needSync = true;     // read the saved settings once after boot
bool ackPending = false;  // tell the app we picked up a request

float effect = 0;         // cooling effect right now, in degrees
float goalEffect = 0;     // cooling effect we are heading towards
bool coolerOn = false;
bool coolerChanged = false;
bool plantMoving = false;
bool wasMoving = false;

String unitPath() { return String("/fridges/") + FRIDGE_ID; }
String devicePath() { return String("/devices/") + FRIDGE_ID; }

float round1(float v) { return roundf(v * 10.0f) / 10.0f; }

float reported() { return round1(measured + (SIMULATE_COOLING ? effect : 0.0f)); }

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
  measured = round1(t);
  humidity = round1(h);
  return true;
}

// Keeps trying until the board is online, then returns. The simulator can be
// slow to join, so each attempt gets plenty of time before we try again.
void connectWifi() {
  WiFi.mode(WIFI_STA);
  while (WiFi.status() != WL_CONNECTED) {
    Serial.print("Connecting to Wi-Fi");
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD, WIFI_CHANNEL);
    unsigned long start = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - start < 40000) {
      delay(500);
      Serial.print(".");
    }
    if (WiFi.status() != WL_CONNECTED) {
      Serial.println(" not yet, trying again");
      WiFi.disconnect();
      delay(500);
    }
  }
  Serial.printf("\nConnected. IP %s, signal %d dBm\n",
                WiFi.localIP().toString().c_str(), WiFi.RSSI());
}

// ---------- Cooling ----------

// Decides what the cooler does and, when simulated, moves the cooling effect.
// Runs on every pass of loop(); it makes no network calls.
void updateCooling(unsigned long now) {
  float dt = (now - lastPlant) / 1000.0f;
  lastPlant = now;
  if (dt > 5.0f) dt = 5.0f;

  bool want = coolerOn;
  plantMoving = false;

#if SIMULATE_COOLING
  float goal = effect;  // by default, stay where we are
  if (hasTarget) {
    if (!isnan(measured)) goal = targetTemp - measured;  // hold the target whatever the sensor does
  } else if (hasOffset) {
    goal = offsetReq;
  } else {
    goal = 0;  // automatic
  }
  goal = constrain(goal, -MAX_EFFECT, MAX_EFFECT);
  goalEffect = goal;

  // Big changes are quick; small ones finish at no less than 1 degree per second
  float gap = goal - effect;
  float speed = fmaxf(1.0f, fabsf(gap) * 0.4f);
  float step = speed * dt;
  if (fabsf(gap) <= step) {
    effect = goal;
  } else {
    effect += (gap > 0 ? step : -step);
  }

  plantMoving = fabsf(goal - effect) > 0.2f;
  want = goal < -0.05f;
#else
  goalEffect = 0;
  if (hasTarget && !isnan(measured)) {
    if (measured > targetTemp + HYSTERESIS) want = true;
    else if (measured < targetTemp - HYSTERESIS) want = false;
  } else {
    want = hasOffset && offsetReq < 0;
  }
#endif

  if (want != coolerOn) {
    coolerOn = want;
    digitalWrite(COOLER_PIN, coolerOn ? HIGH : LOW);
    coolerChanged = true;
    Serial.printf("Cooler %s\n", coolerOn ? "ON" : "OFF");
  }
}

// Reads a number from the database.
// 1 = got a number, 0 = the value is empty, -1 = the request failed.
int readNumber(const String& path, float& out) {
  if (!Firebase.RTDB.get(&fbdo, path.c_str())) return -1;
  String p = fbdo.payload();
  p.trim();
  if (p.length() == 0 || p == "null") return 0;
  out = p.toFloat();
  return 1;
}

// Same, for whole numbers (request ids), so nothing is rounded.
int readInt(const String& path, long& out) {
  if (!Firebase.RTDB.get(&fbdo, path.c_str())) return -1;
  String p = fbdo.payload();
  p.trim();
  if (p.length() == 0 || p == "null") return 0;
  out = p.toInt();
  return 1;
}

// Looks for a new cooling request. The app writes a fresh cmdId with every
// request, so most polls cost a single read.
void checkCommands() {
  long id = 0;
  int rc = readInt(unitPath() + "/cmdId", id);
  if (rc < 0) return;  // network trouble: try again later
  if (!needSync && id == lastCmd) return;

  float off = 0, tgt = 0;
  int ro = readNumber(unitPath() + "/coolOffset", off);
  if (ro < 0) return;
  int rt = readNumber(unitPath() + "/targetTemp", tgt);
  if (rt < 0) return;

  hasOffset = (ro == 1);
  offsetReq = hasOffset ? off : 0;
  hasTarget = (rt == 1);
  targetTemp = hasTarget ? tgt : 0;
  lastCmd = id;
  needSync = false;
  ackPending = true;

  if (hasTarget) Serial.printf("Request: hold %.1f C\n", targetTemp);
  else if (hasOffset) Serial.printf("Request: adjust by %+.1f C\n", offsetReq);
  else Serial.println("Request: automatic");
}

// ---------- Talking to Firebase ----------

bool sendLive(bool door, bool withReading) {
  FirebaseJson json;
  if (withReading) {
    json.set("temperature", temperature);
    json.set("humidity", humidity);
    json.set("lastSeen/.sv", "timestamp");  // the server's clock, so no NTP needed
    json.set("sensorTemp", measured);
    json.set("coolEffect", round1(SIMULATE_COOLING ? effect : 0.0f));
    json.set("coolGoal", round1(SIMULATE_COOLING ? goalEffect : 0.0f));
  }
  json.set("cmdAck", (int)lastCmd);  // tells the app which request we have carried out
#if HAS_DOOR_SENSOR
  json.set("doorOpen", door);
#endif
  bool ok = Firebase.RTDB.updateNode(&fbdo, unitPath().c_str(), &json);
  if (ok) {
    if (withReading) {
      Serial.printf("Live: %.1f C (DHT22 %.1f, cooler %+.1f), %.1f %%, door %s\n",
                    temperature, measured, SIMULATE_COOLING ? effect : 0.0f, humidity,
                    door ? "open" : "closed");
    }
  } else {
    Serial.printf("Live update failed: %s\n", fbdo.errorReason().c_str());
  }
  return ok;
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
  json.set("cooling", coolerOn);
  json.set("plantSim", SIMULATE_COOLING);
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
  pinMode(COOLER_PIN, OUTPUT);
  digitalWrite(COOLER_PIN, LOW);
  dht.begin();
  connectWifi();  // returns only once we are online

  config.api_key = API_KEY;
  config.database_url = DATABASE_URL;
  auth.user.email = DEVICE_EMAIL;
  auth.user.password = DEVICE_PASSWORD;
  config.token_status_callback = tokenStatusCallback;

  // The secure connection is slow in the simulator, so allow more time
  config.timeout.serverResponse = 30 * 1000;
  config.timeout.socketConnection = 30 * 1000;
  config.timeout.sslHandshake = 90 * 1000;

  Firebase.reconnectNetwork(true);
  fbdo.setBSSLBufferSize(4096, 1024);
  Firebase.begin(&config, &auth);

  lastDoorOpen = doorIsOpen();
  lastPlant = millis();
}

void loop() {
  unsigned long now = millis();

  if (WiFi.status() != WL_CONNECTED) {
    if (now - lastWifiTry > WIFI_RETRY_MS) {
      lastWifiTry = now;
      Serial.println("Wi-Fi lost, waiting for it to come back...");
      WiFi.reconnect();  // no disconnect(): that would cancel an attempt in progress
    }
    return;
  }
  if (!Firebase.ready()) return;

  updateCooling(now);
  bool justStopped = wasMoving && !plantMoving;  // tell the app the move has finished
  wasMoving = plantMoving;

  bool door = doorIsOpen();
  bool dueLive = firstRun || (now - lastLive >= LIVE_EVERY_MS) || (door != lastDoorOpen) ||
                 (plantMoving && now - lastLive >= MOVING_EVERY_MS) || justStopped ||
                 (ackPending && now - lastLive >= 1000);

  if (dueLive) {
    lastLive = now;
    bool fresh = readSensor();
    if (fresh) {
      temperature = reported();
    } else {
      Serial.println("DHT22 read failed");
    }

    // A dead sensor must not refresh lastSeen, so the unit shows as offline.
    // The door state and the request acknowledgement are still reported.
    if (sendLive(door, fresh)) ackPending = false;
    lastDoorOpen = door;

    if (fresh && (firstRun || now - lastLog >= LOG_EVERY_MS)) {
      lastLog = now;
      sendLog(door);
    }
  }

  if (firstRun || coolerChanged || now - lastHealth >= HEALTH_EVERY_MS) {
    lastHealth = now;
    coolerChanged = false;
    sendHealth();
  }

  if (now - lastCommandPoll >= COMMAND_POLL_MS) {
    lastCommandPoll = now;
    checkCommands();
  }

  if (now - lastPingPoll >= PING_POLL_MS) {
    lastPingPoll = now;
    checkPing();
  }

  firstRun = false;
  delay(50);
}