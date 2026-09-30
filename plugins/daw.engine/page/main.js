// The page's side of daw.engine. It owns the Engine, answers the plugin's messages, and
// reports back what the plugin shows: the transport, the playhead, the meters and what was
// recorded. The page itself is the master meter on the toolbar.
//
// The page runs in a sandboxed frame, so the browser holds its sound until someone clicks
// inside it. Until then the meter reads "Click for sound", and a click starts the sound.
//
// Messages from the plugin:
//   { type: 'load', song }                  song: the resolved song, as JSON text
//   { type: 'play', from? } { type: 'stop' } { type: 'pause' } { type: 'seek', beat }
//   { type: 'param', device, key, value }   one device parameter, at once
//   { type: 'mix', track, key, value }      volume, pan, mute or solo of a track or 'master'
//   { type: 'note_on', track, pitch, velocity } { type: 'note_off', track, pitch }
//   { type: 'all_off' } { type: 'live', track } { type: 'metronome', on } { type: 'record', on }
// Messages to the plugin:
//   { type: 'ready' }                       the page listens
//   { type: 'sound', on }                   the browser lets the page make sound, or not
//   { type: 'transport', playing, beat }    playing started or stopped
//   { type: 'tick', beat }                  about 30 times a second while playing
//   { type: 'levels', tracks, master }      about 15 times a second while there is sound
//   { type: 'recorded', notes }             the notes recorded, when recording or playing stops
//   { type: 'warning', message }            a patch had a mistake

'use strict';

const canvas = document.getElementById('meter');
const hint = document.getElementById('hint');

const post = (message) => proteus.post(message);

const engine = new Engine((kind, data) => {
  if (kind === 'transport') {
    const t = data;
    post({ type: 'transport', playing: t.playing, beat: t.beat });
    if (!t.playing) sendRecording();
  } else if (kind === 'warning') {
    post({ type: 'warning', message: data.message });
  } else if (kind === 'context') {
    showSound();
  }
});

function sendRecording() {
  const notes = engine.takeRecording();
  if (notes.length > 0) post({ type: 'recorded', notes });
}

let soundOn = null;
function showSound() {
  const on = engine.ctx.state === 'running';
  hint.hidden = on;
  if (on !== soundOn) {
    soundOn = on;
    post({ type: 'sound', on });
  }
}

// A click is the one thing that lets a sandboxed page start its sound.
addEventListener('pointerdown', () => {
  void engine.ctx.resume().then(showSound);
});
// The click leaves the keyboard in this frame, and the app's keys, such as Space for play,
// listen outside it. So the focus goes back to the app.
addEventListener('pointerup', () => {
  try {
    parent.focus();
  } catch {
    // A browser that refuses leaves the focus here, and a click on the app brings it back.
  }
});

const num = (v, fallback = 0) => (typeof v === 'number' && Number.isFinite(v) ? v : fallback);

proteus.on((m) => {
  if (!m || typeof m !== 'object') return;
  switch (m.type) {
    case 'load':
      engine.load(typeof m.song === 'string' ? JSON.parse(m.song) : m.song);
      break;
    case 'play':
      void engine.ctx.resume().then(showSound);
      engine.play(typeof m.from === 'number' ? m.from : undefined);
      break;
    case 'stop':
      engine.stop(false);
      break;
    case 'pause':
      engine.stop(true);
      break;
    case 'seek':
      engine.seek(num(m.beat));
      break;
    case 'param':
      engine.mixer.setParam(String(m.device), String(m.key), m.value);
      break;
    case 'mix':
      engine.mixer.setMix(String(m.track), String(m.key), m.value);
      break;
    case 'note_on':
      engine.noteOn(String(m.track ?? ''), num(m.pitch, 60), num(m.velocity, 0.8));
      break;
    case 'note_off':
      engine.noteOff(String(m.track ?? ''), num(m.pitch, 60));
      break;
    case 'all_off':
      engine.allNotesOff();
      break;
    case 'live':
      engine.setLiveTrack(String(m.track ?? ''));
      break;
    case 'metronome':
      engine.setMetronome(m.on === true);
      break;
    case 'record':
      engine.setRecording(m.on === true);
      if (m.on !== true) sendRecording();
      break;
  }
});

// The playhead and the meters -----------------------------------------------------------------

let lastTick = 0;
let lastLevels = 0;
let quiet = 0;
let shown = [0, 0];
let clipped = 0;

function frame(now) {
  requestAnimationFrame(frame);
  if (engine.playing && now - lastTick > 33) {
    lastTick = now;
    post({ type: 'tick', beat: engine.position() });
  }
  if (now - lastLevels > 66) {
    lastLevels = now;
    const levels = engine.levels();
    const loud = levels.master.some((v) => v > 0.001);
    // Levels go out while there is sound, and a few more times as it dies away.
    quiet = loud ? 0 : quiet + 1;
    if (quiet < 4) post({ type: 'levels', tracks: levels.tracks, master: levels.master });
  }
  draw();
}

function draw() {
  const g = canvas.getContext('2d');
  if (!g) return;
  const w = (canvas.width = canvas.clientWidth * devicePixelRatio);
  const h = (canvas.height = canvas.clientHeight * devicePixelRatio);
  const [l, r] = engine.masterPeak();
  shown = [Math.max(l, shown[0] * 0.9), Math.max(r, shown[1] * 0.9)];
  if (l >= 1 || r >= 1) clipped = performance.now();
  g.clearRect(0, 0, w, h);
  g.fillStyle = 'rgba(128, 128, 128, 0.22)';
  g.fillRect(0, 0, w, h);
  const bar = (v, y) => {
    // A meter reads in decibels, from -48 dB at the left to 0 dB at the right.
    const db = v > 0 ? 20 * Math.log10(v) : -96;
    const x = Math.max(0, Math.min(1, (db + 48) / 48)) * (w - 6 * devicePixelRatio);
    g.fillStyle = db > -3 ? '#f85149' : db > -12 ? '#d29922' : '#3fb950';
    g.fillRect(0, y, x, h / 2 - 2 * devicePixelRatio);
  };
  bar(shown[0], devicePixelRatio);
  bar(shown[1], h / 2 + devicePixelRatio);
  g.fillStyle = performance.now() - clipped < 1500 ? '#f85149' : 'rgba(128, 128, 128, 0.4)';
  g.fillRect(w - 4 * devicePixelRatio, devicePixelRatio, 3 * devicePixelRatio, h - 2 * devicePixelRatio);
}

requestAnimationFrame(frame);
showSound();
post({ type: 'ready' });
