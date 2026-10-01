# The DAW

The `daw` profile turns Proteus into a music program laid out like FL Studio: a desktop of floating windows for the Channel Rack with its step sequencer, the Playlist, the piano roll, the mixer and each channel's settings. It has instrument and audio tracks with clips on a timeline, a piano roll, a mixer, a rack of devices with a sampler, loops, a metronome, recording from the computer keyboard or a MIDI keyboard, and export to WAV. Every part of it is a plugin in this registry, and none of it needs the app to change. Install the **DAW** profile from the marketplace.

## How it fits the registry

The DAW runs as restricted community plugins, the way the Shader Builder does:

- **Almost no permissions.** Every `daw.*` plugin but one declares `permissions = {}`. They draw, keep their data in `app.store`, and `daw.session` writes songs in `songs/`, the one folder it claims in `folders`. `daw.midi` asks for `midi`, which hears keyboards and nothing else.
- **The sound runs in a web view.** Lua runs on the page's thread and cannot keep time to the millisecond, so the engine is a page, `daw.engine/page/engine.html`, in the sandboxed web view that `ui.webview` gives any plugin with the `webview` feature. It plays through Web Audio and talks to `daw.engine` only through messages.
- **One namespace.** Every service, event, command and setting starts with `daw`, the first part of each id. A command that a button in another plugin runs, such as `daw.new`, `daw.save` and `daw.loop`, is marked `shared = true`.

### Files, sound and keyboards

Each of these rests on something the user does, so none of it needs a full-access permission. They need Proteus with the features `grants`, `autoplay` and `midi`.

| Feature | How it works |
|---------|--------------|
| Audio tracks and the Sampler | **Import audio** and the Sampler's **Choose...** show the system's open dialog through `app.grants.open`. `daw.engine` gets an id and a name for each file, never a path, and a song keeps the id. When the page needs a file it asks, and the plugin has the app send the bytes into the page with `view:widget ('send_file', id)`. The page decodes them once and sends back the length and 1000 peaks for the waveform. |
| Export as WAV | **File > Export as WAV** shows the save dialog through `app.grants.save`. `view:widget ('allow_save', id)` lets the page write that one file. The page renders the song in an `OfflineAudioContext`, encodes 16-bit WAV, and writes it with `proteus.save`. The plugin then gives the file back, so the next export asks again. |
| MIDI keyboards | `daw.midi` listens with `app.midi.listen`, which passes notes and controllers only, never SysEx, and sends nothing to the device. Notes go to the armed or selected track, the same as the computer keyboard's, so recording takes them. The sustain pedal holds notes. |
| Sound at once | The web view asks for `autoplay`. Where the browser still holds the sound, the meter on the toolbar reads **Click for sound**, and one click there lets the DAW play. The page hands the keyboard back to the app after the click, so Space still plays and stops. |

The marketplace lists the files `daw.engine` holds on its page, and **Forget** takes one back. A song that names a file this computer never gave the DAW, such as one from another computer, plays that clip silently and says so in its tooltip until the file is imported again.

## The desktop

The app's builtin `ui.windows` turns the middle of the window into a desktop, as FL Studio does, and the profile names its tab **Studio**. Every screen is a window on it:

| Window | Key | Plugin |
|--------|-----|--------|
| Playlist | F5 | `daw.arrange` |
| Channel rack | F6 | `daw.channels` |
| Piano roll | F7 | `daw.pianoroll` |
| Mixer | F9 | `daw.mixer` |
| Channel settings | | `daw.rack`, opened by clicking a channel's name |

- A window moves by its title bar and resizes from its edges. It snaps to the desktop's edges and to other windows, and Alt holds the snap off.
- Double-clicking the title, or its middle button, maximizes it. The left button rolls it up to its title bar.
- A key or a toolbar button brings a window that is behind others to the front, and closes one that is in front already.
- The layout, the stacking and what is open come back the next time. **View > Reset the Window Layout** puts every window back.
- A window's title follows the selection, such as **Piano roll - Bass** or **Drums - Channel settings**.

A screen adds its window with the app's `windows` service: `windows.add ({ id, title, icon, key, content, x, y, w, h })`, where a position from 0 to 1 is a share of the desktop. The service is builtin because only a builtin plugin may put another plugin's element on screen. When the screen's plugin stops, its window goes too. Without `ui.windows`, each screen falls back to the app's docks.

### The Channel rack

Each instrument track is a channel: a light that mutes it, its name, and 16 steps, one bar in sixteenth notes. A kit, such as the Drum Kit, gets a row for each pad. The steps are not a second kind of pattern: `daw_steps.lua` reads and writes the notes of the track's clips. A step turns on by adding a sixteenth note to the clip that covers it, or to a new one-bar clip, so the Playlist and the piano roll show every step.

- A click on a step plays it, and a drag paints the same state along the row. One drag is one undo step.
- While the song plays, the bar follows the playhead and the current step lights. The arrows pick another bar, and the target button turns following off.
- A click on a channel's name selects its track and opens its Channel settings. A double-click opens the clip under the bar in the piano roll.

## The layers

```
plugins/daw.core/          pure Lua: songs, notes, steps, devices, time, undo, the demo song
  types/daw.lua            types for the song, devices and every DAW service
  tests/                   run by scripts/lua-test.mjs
plugins/daw.engine/        the plugin that keeps the page playing the session's song
  page/engine.html         the page: the master meter, and these scripts in order
  page/expr.js             the expression language of patch fields
  page/files.js            audio files by grant id, and the WAV encoder
  page/patch.js            builds Web Audio graphs from patches
  page/mixer.js            tracks, effect chains, faders, the scheduling of notes
  page/engine.js           the transport, live notes, recording, meters and rendering
  page/main.js             the messages to and from the plugin
plugins/daw.*/             the registry of devices, the builtin devices, and the screens
profiles/daw/profile.lua   the profile
```

## The plugins

| Plugin | Service | What it does |
|--------|---------|--------------|
| `daw.core` | `daw` | Pure logic: the song model, note editing, device checks, file reading, undo, the demo song. No UI and no I/O, so the tests load it directly. |
| `daw.devices` | `daw.devices` | The registry of instruments and effects. It holds none of its own. |
| `daw.instruments` | | Registers Synth, FM Keys, Drum Kit and Sampler. |
| `daw.effects` | | Registers EQ Three, Filter, Delay, Reverb, Compressor, Drive, Chorus and Utility. |
| `daw.session` | `daw.session` | The open song, its file in `songs/`, undo and redo, and what is selected. The only place a song changes. |
| `daw.engine` | `daw.engine` | Runs the engine page and keeps it playing the session's song. Recording, the audio files the user picks, and Export as WAV. |
| `daw.transport` | | Play, stop, record, loop, metronome, position, tempo and time signature, on the toolbar. |
| `daw.channels` | | The Channel rack: every instrument channel, with a step sequencer. |
| `daw.arrange` | | The Playlist: tracks and clips on a timeline, the ruler and the loop. |
| `daw.pianoroll` | | The notes of one clip, with velocity. Without a clip picked, the selected channel's. |
| `daw.mixer` | | A strip per track and the master, with meters. |
| `daw.rack` | | Channel settings: the selected track's devices and every parameter. |
| `daw.browser` | | Songs, instruments, effects and presets, in the left dock. |
| `daw.keyboard` | | The computer keyboard as a piano. |
| `daw.midi` | | MIDI keyboards, with the sustain pedal. Needs the `midi` permission. |

Each screen can be switched off, and the rest still works. None of the screens knows a device by name.

## How a change flows

```
a screen  ──daw.song.<op>(song, …)──►  a new song
          ──session.apply(song, change)──►  daw.session
                                            │ keeps the old song for undo
                                            │ autosaves a moment later
                                            ▼
                                     event daw:changed (song, change)
                                            │
            ┌───────────────────────────────┼─────────────────────────────┐
            ▼                               ▼                             ▼
   every screen redraws            daw.engine resolves the song     the status bar
   from the same song              and posts it to the page
```

Songs never change in place. Each operation in `daw_song.lua` returns a new song and copies only the tables on the path to the change, so the old song can sit in the undo history as it is.

`change.kind` lets each listener skip work. A knob sends `param` and a fader sends `mix`, and `daw.engine` posts just that value, without the whole song. The arrangement and the piano roll ignore them, since nothing they show moved. Drags change the song once, when the button comes up, and a coalesce key groups the steps of one knob turn into one undo step.

## The page's messages

| From the plugin | What it does |
|-----------------|--------------|
| `{ type = 'load', song }` | The resolved song, as JSON text so an empty list stays a list |
| `play` (`from`), `stop`, `pause`, `seek` (`beat`) | The transport |
| `param` (`device`, `key`, `value`), `mix` (`track`, `key`, `value`) | One value, at once |
| `note_on`, `note_off`, `all_off`, `live` (`track`) | Live notes, from the keys, the piano roll and the computer keyboard |
| `metronome` (`on`), `record` (`on`) | |
| `missing` (`file`, `error`), `retry` (`file`) | The plugin cannot send a file the page asked for, or it can again |
| `render` (`file`, `from`, `to`) | Play the song into the WAV file the user chose. With `to` at or before `from`, to the end. |

| From the page | What it says |
|---------------|--------------|
| `ready` | The page listens. The plugin sends the song. |
| `sound` (`on`) | The browser lets the page make sound, or not |
| `transport` (`playing`, `beat`) | Playing started or stopped |
| `tick` (`beat`) | About 30 times a second while playing, for the playheads |
| `levels` (`tracks`, `master`) | About 15 times a second while there is sound, for the meters |
| `recorded` (`notes`) | What was recorded, when recording or playing stops |
| `want` (`file`) | The page needs this file |
| `file` (`file`, `seconds`, `peaks`), `file_failed` (`file`, `error`) | A file decoded, or could not be read |
| `rendered` (`file`, `seconds`), `render_failed` (`file`, `error`) | The export finished |
| `warning` (`message`) | A patch had a mistake |

That stays well under the web view's limits of 500 messages a second and 1 MB a message.

## The song

A song is a JSON file in `songs/` in the workspace, the folder `daw.session` claims. Times are in beats, and a beat is a quarter note.

```json
{
  "format": 1,
  "name": "Demo",
  "tempo": 112,
  "signature": [4, 4],
  "loop": { "on": true, "start": 0, "finish": 16 },
  "master": { "volume": -3, "effects": [] },
  "tracks": [
    {
      "id": "t5", "name": "Bass", "kind": "instrument", "color": "#e5a04b",
      "volume": -3, "pan": 0, "mute": false, "solo": false, "arm": false,
      "instrument": { "id": "d6", "device": "daw.synth", "preset": "Sub Bass", "params": { "cutoff": 700 }, "bypass": false },
      "effects": [],
      "clips": [
        { "id": "c7", "name": "Bass", "start": 0, "length": 16,
          "notes": [{ "pitch": 33, "start": 0, "length": 0.75, "velocity": 0.9 }] }
      ]
    }
  ],
  "ids": 12
}
```

- A device on a track names its device by id, a preset by name, and only the values changed by hand. Its sound is the device's defaults, then the preset, then those values.
- `kind` is `instrument` or `audio`. An audio track's clips have no notes: `file` is the id of a file the user gave `daw.engine`, `offset` is where in the file the clip starts, in seconds, and `gain` is in decibels. Splitting an audio clip moves the right half's offset.
- `ids` counts up, so a new id never repeats one that was deleted.
- `daw_file.normalize` reads anything: an older file, a hand edit, or an empty list that came back from JSON as an empty object. Every field is checked, and anything missing gets its default.

A song that names a device no running plugin provides keeps it. The track plays without it, the rack shows it in red, and a message says which plugin is missing.

## Devices

A device is a plugin's description of an instrument or an effect. It is data, not code:

```lua
app.use ('daw.devices').register ({
  id = 'my.wobble',
  name = 'Wobble Bass',
  role = 'instrument',
  category = 'Synths',
  params = {
    { key = 'cutoff', label = 'Cutoff', min = 40, max = 8000, default = 600, curve = 'log', unit = 'Hz' },
    { key = 'rate', label = 'Wobble', min = 0.5, max = 12, default = 4, unit = 'Hz' },
  },
  presets = { { name = 'Slow', params = { rate = 1 } } },
  patch = {
    poly = 1,
    voice = {
      nodes = {
        { id = 'osc', type = 'osc', wave = 'sawtooth', freq = 'freq' },
        { id = 'flt', type = 'filter', mode = 'lowpass', freq = '$cutoff', q = 8 },
        { id = 'lfo', type = 'lfo', rate = '$rate', depth = '$cutoff * 0.8' },
        { id = 'amp', type = 'gain', gain = 0 },
        { id = 'env', type = 'env', a = 0.005, d = 0.2, s = 0.8, r = 0.1, amount = 'vel' },
      },
      connect = { 'osc > flt', 'flt > amp', 'amp > out', 'lfo > flt.freq', 'env > amp.gain' },
    },
  },
})
```

The rack builds a control for each parameter, the browser lists the device under its category, and songs save its id. The device goes away when its plugin stops.

### Patches

- An **instrument** has a `voice`, built once for each note, or `pads` for a drum kit, where each pad is a voice for one note. `poly` caps how many notes sound at once. Pads with the same `choke` cut each other off.
- An **effect** has `nodes` and `connect`, built once for its track, between the implicit nodes `in` and `out`.
- A wire `'a > b'` carries sound. A wire `'a > b.field'` moves a field, added to the value the field already has. That is how an envelope opens a filter or an LFO adds vibrato.

| Node | Fields |
|------|--------|
| `osc` | `wave` (sine, triangle, sawtooth, square, pulse), `freq`, `detune`, `duty` |
| `noise` | none |
| `gain` | `gain` |
| `filter` | `mode` (any biquad type), `freq`, `q`, `gain`, `detune` |
| `delay` | `time`, up to 4 seconds |
| `pan` | `pan` |
| `compressor` | `threshold`, `knee`, `ratio`, `attack`, `release` |
| `reverb` | `seconds`, `decay`. The impulse is made from noise. |
| `shaper` | `curve` (soft, hard, fold, crush), `amount` |
| `lfo` | `wave`, `rate`, `depth` |
| `env` | `a`, `d`, `s`, `r`, `amount`, `oneshot`. Its output runs from 0 to `amount`. |
| `const` | `value` |

A field takes a number or an expression. `$name` reads a parameter. `freq`, `key` and `vel` read the note, and `bpm` reads the tempo, so a delay can follow the song: `time = '$beats * 60 / bpm'`. The functions are `min`, `max`, `pow`, `exp`, `log`, `abs`, `floor`, `sqrt`, `clamp`, `semis` (semitones to a ratio) and `db` (decibels to a gain). Text fields such as `wave` take a name, or `'$param'` to read a choice parameter.

The engine compiles each expression once. When a parameter moves, it works out only the fields that read it again, on every voice that is sounding and on every effect. `daw_device.check` refuses a spec with an unknown node type, a wire to nothing, or a parameter with no range, with a reason, before anything reaches the engine.

### Why patches and not code

A device written as Lua code would run for every note, on the page's thread, and could stall the music. A device that shipped JavaScript into the engine's page could break every other device, since they share one audio graph. A patch is plain data, so:

- a plugin in Lua can add a real instrument, with nothing running while it plays
- a reviewer reads a device like any other plugin, since it is plain Lua data
- a pack needs no permissions and no web view of its own

A Web Audio Module, below, is the way out when a patch is not enough. It runs in the same sandboxed page, so a module that stalls only stalls the music, never the app.

The cost is that a device can only combine the node types above. A new kind of sound, such as granular synthesis, needs a new node type in `daw.engine/page/patch.js`.

### Web Audio Modules

A device can also be a [Web Audio Module](https://www.webaudiomodules.com/), a WAM 2 module in JavaScript that runs its own sound in an AudioWorklet. The pack offers the folder that holds its modules in `exports`, and each device names its module there instead of a patch:

```lua
return {
  name = 'My modules',
  version = '1.0.0',
  depends = { 'daw.devices' },
  exports = { 'wam' },
  requires = { features = { 'webview-files' } },
  activate = function (app)
    app.use ('daw.devices').register ({
      id = 'my.synth',
      name = 'My Synth',
      role = 'instrument',
      category = 'Web Audio Modules',
      params = {},
      patch = {},
      wam = { path = 'wam/synth/index.js' },
    })
  end,
}
```

- `daw.engine` mounts every pack that registers a module, and loads each one from `_/<pack>/<path>` inside its own page. The module runs in that sandboxed page, the same as a patch, so it reaches nothing a patch could not.
- A device may leave `params` empty. The first time a module loads, the engine asks it for its parameters and `daw.devices` fills them in, so the rack draws a control for each and songs save their values like any other.
- An instrument hears its notes as MIDI events on the audio clock. An effect passes its sound straight through until its module is ready.
- A module with an editor gets a button in the rack that opens it in a floating window. The editor runs its own silent copy of the module, and every change it makes goes to the song, so undo and saving work as they do for the rack's controls.
- A render waits for every module to load before it starts.

`wam.basics` in this registry holds a polyphonic synth with an editor and a stereo echo, and is the smallest example. It copies the WAM SDK, listed in its `vendor.json`.

### Native plugins

The DAW also plays on the app's native engine, a process of its own that plays the same patches and hosts CLAP and VST3 plugins. Set **Sound engine** (`daw.engine`) to `native`. `daw.engine` then sends the page's messages to `app.audio` instead, and the page on the toolbar only draws the master level.

- `daw.native` registers each CLAP and VST3 plugin the app finds as a device with `native = { plugin = ref }` and a control for each parameter (`daw_device.from_native`). It needs the `native-plugins` permission, and the app asks the user the first time a song loads each plugin.
- `daw.engine` opens the native engine itself, so its file grants and exports work as they do on the web. `daw.native` lends it the right to load native plugins with `app.audio.lend ('daw.engine')`, so the rest of the DAW needs no full-access permission.
- A native device resolves to `{ id, kind, params, native = { plugin } }`. The app puts the binary's path in before the engine sees the song, and the DAW never learns it.
- A native plugin that crashes takes the native engine with it, never the app. The app starts the engine again on its own, `daw.engine` tells the user once why and sends it the song when it is ready, and the user's answers about native plugins still hold. After a few crashes in a row the engine stays stopped, and **Restart the Sound Engine** starts it again.
- The web engine cannot play native devices. It says so, leaves the instrument silent and passes an effect's sound through. The native engine cannot play Web Audio Modules, and says so too.

## The engine

- **Scheduling.** Every 25 ms the transport looks 150 ms ahead and starts each note that falls in that stretch, on the Web Audio clock. At the loop's end it wraps and carries on. Notes that run past the loop end are cut there.
- **Tempo.** A tempo change while playing takes effect from the next stretch, and the playhead's position stays continuous across it.
- **Tracks.** Instrument, then the effects in order, then the fader, the pan and a meter, into the master chain. Solo mutes every track that is not soloed. Effects that did not change keep running, so a delay's tail survives an edit elsewhere.
- **Recording.** While recording and playing, notes played live on the armed track are kept with their beats. When playing stops, the page posts them, and `daw.engine` puts them in a new clip, in whole bars.

## Shortcuts

| Key | Does |
|-----|------|
| Space | Play or stop |
| Shift+Space | Pause where it is |
| Home | Go to the start, or the loop's start |
| Ctrl+R | Record |
| Ctrl+L | Loop on or off |
| Ctrl+M | Metronome |
| F5, F6, F7, F9 | The Playlist, the Channel rack, the piano roll and the mixer |
| Ctrl+T | Add an instrument track |
| Ctrl+D | Duplicate the selected clips |
| Ctrl+E | Split at the playhead |
| Delete | Delete the selected clips, or notes when the piano roll was clicked last |
| Arrow keys | In the piano roll: move notes by a semitone or a grid step. Shift moves an octave. |
| Alt+Q | Quantize |
| A to K, W to U | Play notes. Z and X change the octave, C and V the velocity. |

## Where it can grow

- **Automation.** A lane of points per parameter. The engine already keeps a binding for each field, so it could follow a curve instead of a value.
- **Clip loops.** A clip that repeats its notes past their length.
- **Sends.** Effect tracks that several tracks feed.
- **More node types.** A wavetable oscillator would widen what devices can do without changing the patch format.
- **Recording audio.** A microphone needs a permission and a frame `allow` entry that the app does not offer yet.

## Device packs

A device pack is any plugin that lists `daw.devices` in `depends` and registers devices. `chiptune` in this registry adds a pulse lead, a triangle bass, a noise kit and a bit crusher, and is the smallest complete example. Add a pack to the DAW profile from the marketplace.
