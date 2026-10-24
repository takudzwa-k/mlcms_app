// MLCMS alert sender
// Watches the Realtime Database and sends a push alert EVERY time a unit leaves
// its safe range, and another when it is back inside it.
//
//   node index.js          run the sender (leave it running)
//   node index.js --test   send one test notification and exit

const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');

const KEY_PATH =
  process.env.KEY_PATH || path.join(__dirname, 'serviceAccountKey.json');
const DATABASE_URL =
  process.env.DATABASE_URL || 'https://mlcms-app-default-rtdb.firebaseio.com';

// Timings. 0 is allowed. Override any of them when starting, for example:
//   RECOVER_SECONDS=30 node index.js
const num = (name, fallback) => {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return fallback;
  const v = Number(raw);
  return Number.isFinite(v) && v >= 0 ? v : fallback;
};
const CONFIRM_MS = num('CONFIRM_SECONDS', 0) * 1000; // 0 = alert the moment a unit leaves its range
const RECOVER_MS = num('RECOVER_SECONDS', 0) * 1000; // 0 = every return to range counts
const ESCALATE_MS = num('ESCALATE_MINUTES', 15) * 60 * 1000; // still out = tell supervisors
const STALE_MS = num('STALE_MINUTES', 15) * 60 * 1000; // ignore units silent this long
const TICK_MS = 5 * 1000; // how often time-based rules are checked

if (!fs.existsSync(KEY_PATH)) {
  console.error(
    `Cannot find the service account key at:\n  ${KEY_PATH}\n\n` +
      'In the Firebase console go to Project settings > Service accounts,\n' +
      'generate a new private key, and save it there as serviceAccountKey.json.'
  );
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require(KEY_PATH)),
  databaseURL: DATABASE_URL,
});

const db = admin.database();
const messaging = admin.messaging();

// ---------- Small helpers ----------

const log = (...args) =>
  console.log(`[${new Date().toLocaleTimeString()}]`, ...args);

const signed = (v, digits = 1) =>
  `${v >= 0 ? '+' : ''}${Number(v).toFixed(digits)}`;

const limit = (v) => {
  const text = Number.isInteger(v) ? String(v) : v.toFixed(1);
  return `${v >= 0 ? '+' : ''}${text}°C`;
};

const minutes = (ms) => Math.max(1, Math.round(ms / 60000));

// ---------- Sending ----------

async function push(topic, title, body, fridgeId, kind) {
  try {
    await messaging.send({
      topic,
      notification: { title, body },
      data: { fridgeId: fridgeId || '', kind },
      android: {
        priority: 'high',
        // the channel created in MainActivity, so alerts pop up on screen;
        // the tag makes a unit's newest alert replace its previous one
        notification: { channelId: 'mlcms_alerts', tag: fridgeId || kind },
      },
      apns: { payload: { aps: { sound: 'default' } } },
    });
    log(`sent [${kind}] to "${topic}": ${title}`);
    return true;
  } catch (err) {
    log(`FAILED to send [${kind}]: ${err.message}`);
    return false;
  }
}

// ---------- Alert logic ----------

let fridges = {}; // the latest copy of /fridges
const states = {}; // one alert state per unit, mirrored in /alertState
let loaded = false;

const freshState = () => ({
  phase: 'ok', // ok -> pending -> breach -> ok
  since: 0, // when the current breach was first noticed
  recoverSince: 0, // when the unit first looked back in range
  escalated: false,
});

function save(id) {
  db.ref(`alertState/${id}`)
    .set(states[id])
    .catch((err) => log(`could not save state for ${id}: ${err.message}`));
}

function evaluate() {
  if (!loaded) return;
  const now = Date.now();

  for (const id of Object.keys(fridges)) {
    const f = fridges[id];
    if (!f || typeof f !== 'object') continue;

    const s = states[id] || (states[id] = freshState());
    const name = f.name || id;
    const min = Number(f.minTemp);
    const max = Number(f.maxTemp);
    const temp = Number(f.temperature);
    const lastSeen = Number(f.lastSeen) || 0;

    // Ignore units that have never reported or have gone quiet
    if (lastSeen <= 0 || now - lastSeen > STALE_MS) continue;
    if (![min, max, temp].every(Number.isFinite)) continue;

    const above = temp > max;
    const out = above || temp < min;
    const muted = Number(f.mutedUntil) > now;

    // 1. the unit has just gone out of range
    if (s.phase === 'ok' && out) {
      s.phase = 'pending';
      s.since = now;
      s.recoverSince = 0;
      s.escalated = false;
      save(id);
      log(`${name}: out of range (${signed(temp)}°C)`);
    }

    // 2. confirm it (instantly when CONFIRM_SECONDS is 0)
    if (s.phase === 'pending') {
      if (!out) {
        s.phase = 'ok';
        s.since = 0;
        save(id);
        log(`${name}: back in range before confirmation, no alert sent`);
      } else if (now - s.since >= CONFIRM_MS) {
        s.phase = 'breach';
        save(id);
        if (muted) {
          log(`${name}: breach confirmed, but alerts are muted`);
        } else {
          const where = above
            ? `above the safe maximum of ${limit(max)}`
            : `below the safe minimum of ${limit(min)}`;
          push(
            'alerts',
            `${name}: temperature breach`,
            `${signed(temp)}°C, ${where}. Tap to view.`,
            id,
            'breach'
          );
        }
      }
    }

    // 3. while it is in breach
    if (s.phase === 'breach') {
      if (!out) {
        if (!s.recoverSince) s.recoverSince = now;

        if (now - s.recoverSince >= RECOVER_MS) {
          const mins = minutes(now - s.since);
          s.phase = 'ok';
          s.since = 0;
          s.recoverSince = 0;
          s.escalated = false;
          save(id);
          if (!muted) {
            push(
              'alerts',
              `${name}: back in range`,
              `Now ${signed(temp)}°C (safe range ${limit(min)} to ${limit(max)}). ` +
                `Out of range for about ${mins} min.`,
              id,
              'resolved'
            );
          }
        } else {
          save(id);
        }
      } else {
        if (s.recoverSince) {
          s.recoverSince = 0; // it slipped back out, so start counting again
          save(id);
        }
        if (!s.escalated && now - s.since >= ESCALATE_MS) {
          s.escalated = true;
          save(id);
          const acked = Number(f.ackAt) >= s.since;
          const by = f.ackBy ? ` by ${f.ackBy}` : '';
          push(
            'supervisors', // escalations go out even when the unit is muted
            `${name}: escalated`,
            `Out of range for ${minutes(now - s.since)} min (${signed(temp)}°C). ` +
              (acked
                ? `Acknowledged${by}, but not yet recovered.`
                : 'Not yet acknowledged.'),
            id,
            'escalated'
          );
        }
      }
    }
  }

  // forget units that were removed
  for (const id of Object.keys(states)) {
    if (!(id in fridges)) {
      delete states[id];
      db.ref(`alertState/${id}`).remove().catch(() => {});
    }
  }
}

// ---------- Start ----------

async function start() {
  log('MLCMS alert sender starting');
  log(
    `alert after ${CONFIRM_MS / 1000}s out of range, resolve after ${RECOVER_MS / 1000}s in range, ` +
      `escalate after ${ESCALATE_MS / 60000} min, ignore data older than ${STALE_MS / 60000} min`
  );

  // pick up where we left off, so a restart doesn't repeat or lose alerts
  try {
    const snap = await db.ref('alertState').once('value');
    const saved = snap.val() || {};
    for (const id of Object.keys(saved)) {
      states[id] = { ...freshState(), ...saved[id] };
    }
  } catch (err) {
    log(`could not read saved state: ${err.message}`);
  }

  db.ref('fridges').on(
    'value',
    (snap) => {
      fridges = snap.val() || {};
      loaded = true;
      evaluate();
    },
    (err) => log(`database error: ${err.message}`)
  );

  setInterval(evaluate, TICK_MS);
  log('Watching /fridges. Press Ctrl+C to stop.');
}

process.on('SIGINT', () => {
  log('stopped');
  process.exit(0);
});

if (process.argv.includes('--test')) {
  push(
    'alerts',
    'MLCMS test alert',
    'If you can read this, push alerts are working.',
    '',
    'test'
  ).then((ok) => process.exit(ok ? 0 : 1));
} else {
  start();
}