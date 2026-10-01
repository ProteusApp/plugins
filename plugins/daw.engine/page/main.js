// The page's side of daw.engine. It owns the Engine, answers the plugin's messages, and
// reports back what the plugin shows: the transport, the playhead, the meters and what was
// recorded. The page itself is the master meter on the toolbar.
//
// The plugin asks for autoplay, so the sound usually starts by itself. Where the browser
// still holds it, the meter reads "Click for sound", and a click inside the page starts it.
//
// Messages from the plugin:
//   { type: 'load', song }                  song: the resolved song, as JSON text
//   { type: 'play', from? } { type: 'stop' } { type: 'pause' } { type: 'seek', beat }
//   { type: 'param', device, key, value }   one device parameter, at once
//   { type: 'mix', track, key, value }      volume, pan, mute or solo of a track or 'master'
//   { type: 'note_on', track, pitch, velocity } { type: 'note_off', track, pitch }
//   { type: 'all_off' } { type: 'live', track } { type: 'metronome', on } { type: 'record', on }
//   { type: 'missing', file, error }        the plugin cannot send a file the page wanted
//   { type: 'retry', file }                 try a file that failed again
//   { type: 'render', file, from, to }      play the song into a WAV file the user chose to
//                                           save. With `to` at or before `from`, to the end.
//   { type: 'set_state', device, state }    a device's saved state, as text. A module playing
//                                           it takes it now, and one made later starts from it.
//                                           Without `state`, the page forgets it.
//   { type: 'get_states', id }              asks what every device would save now
//   { type: 'native', on }                  the app's native engine plays, and the page is
//                                           only the meter
//   { type: 'meter', master }               the native engine's master level, to draw
// Messages to the plugin:
//   { type: 'ready' }                       the page listens
//   { type: 'sound', on }                   the browser lets the page make sound, or not
//   { type: 'transport', playing, beat }    playing started or stopped
//   { type: 'tick', beat }                  about 30 times a second while playing
//   { type: 'levels', tracks, master }      about 15 times a second while there is sound
//   { type: 'recorded', notes }             the notes recorded, when recording or playing stops
//   { type: 'warning', message }            a patch had a mistake
//   { type: 'rendered', file, seconds }     the WAV file is written
//   { type: 'render_failed', file, error }
//   { type: 'states', id, states }          the answer to get_states: the text by device id
// and the file messages in files.js.

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

FILES.post = post;
FILES.decode = (bytes) => engine.ctx.decodeAudioData(bytes);
proteus.onFile((f) => FILES.receive(f));

/** Waits, up to a limit, for the files the song asked for to arrive. */
async function filesSettled(limit = 15000) {
  const start = performance.now();
  while (FILES.pending.size > 0 && performance.now() - start < limit) {
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
}

let rendering = false;
async function renderTo(file, from, to) {
  if (rendering) {
    post({ type: 'render_failed', file, error: 'another export is still running' });
    return;
  }
  rendering = true;
  try {
    await filesSettled();
    const buf = await engine.render(from, to);
    await proteus.save(file, encodeWav(buf));
    post({ type: 'rendered', file, seconds: buf.duration });
  } catch (err) {
    post({ type: 'render_failed', file, error: String(err?.message ?? err) });
  } finally {
    rendering = false;
  }
}

function sendRecording() {
  const notes = engine.takeRecording();
  if (notes.length > 0) post({ type: 'recorded', notes });
}

// While the native engine plays, the page only draws the level it reports.
let native = false;
let external = [0, 0];

let soundOn = null;
function showSound() {
  const on = engine.ctx.state === 'running';
  hint.hidden = on || native;
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
    case 'missing':
      FILES.missing(String(m.file), typeof m.error === 'string' ? m.error : undefined);
      break;
    case 'retry':
      FILES.retry(String(m.file));
      break;
    case 'render':
      void renderTo(String(m.file), num(m.from), num(m.to));
      break;
    case 'set_state':
      engine.setState(String(m.device), typeof m.state === 'string' ? m.state : '');
      break;
    case 'get_states':
      void engine.getStates().then((states) => post({ type: 'states', id: m.id, states }));
      break;
    case 'native':
      native = m.on === true;
      if (native) engine.stop(false);
      external = [0, 0];
      showSound();
      break;
    case 'meter':
      external = Array.isArray(m.master) ? m.master.map((v) => num(v)) : [0, 0];
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
  if (!native && now - lastLevels > 66) {
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
  const [l, r] = native ? external : engine.masterPeak();
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
void engine.ctx.resume().then(showSound, showSound);
showSound();
post({ type: 'ready' });
