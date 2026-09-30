# The DAW

The `daw` profile turns Proteus into a music program: instrument tracks with clips on a timeline, a piano roll, a mixer, a rack of devices, loops, a metronome, and recording from the computer keyboard. Every part of it is a plugin in this registry, and none of it needs the app to change. Install the **DAW** profile from the marketplace.

## How it fits the registry

The DAW runs as restricted community plugins, the way the Shader Builder does:

- **No permissions.** Every `daw.*` plugin declares `permissions = {}`. They draw, keep their data in `app.store`, and `daw.session` writes songs in `songs/`, the one folder it claims in `folders`.
- **The sound runs in a web view.** Lua runs on the page's thread and cannot keep time to the millisecond, so the engine is a page, `daw.engine/page/engine.html`, in the sandboxed web view that `ui.webview` gives any plugin with the `webview` feature. It plays through Web Audio and talks to `daw.engine` only through messages.
- **One namespace.** Every service, event, command and setting starts with `daw`, the first part of each id. A command that a button in another plugin runs, such as `daw.new`, `daw.save` and `daw.loop`, is marked `shared = true`.

### What the sandbox leaves out

A web view cannot reach files, the network, MIDI devices or the app, and a restricted plugin cannot read or write bytes. So some things the DAW could do as part of the app are not here:

| Missing | Why | What would bring it back |
|---------|-----|--------------------------|
| Audio tracks and a sampler | A plugin cannot read an audio file's bytes, and the page cannot read files | A byte reader for plugins with `files`, whose result the plugin posts to the page |
| Export to WAV | The page can render the song offline, but nothing can write the bytes | A byte writer for plugins with `files` |
| MIDI keyboards | The frame's `allow` list is empty, so Web MIDI is off | `allow="midi"` on web views of plugins that ask for it |
| Sound before a click | The browser holds a sandboxed frame's sound until someone clicks inside it | `allow="autoplay"` on web views |

Until then, the meter on the toolbar reads **Click for sound**, and one click there lets the DAW play. The page hands the keyboard back to the app after the click, so Space still plays and stops.

## The layers

```
plugins/daw.core/          pure Lua: songs, notes, devices, time, undo, the demo song
  types/daw.lua            types for the song, devices and every DAW service
  tests/                   run by scripts/lua-test.mjs
plugins/daw.engine/        the plugin that keeps the page playing the session's song
  page/engine.html         the page: the master meter, and these scripts in order
  page/expr.js             the expression language of patch fields
  page/patch.js            builds Web Audio graphs from patches
  page/mixer.js            tracks, effect chains, faders, the scheduling of notes
  page/engine.js           the transport, live notes, recording and meters
  page/main.js             the messages to and from the plugin
plugins/daw.*/             the registry of devices, the builtin devices, and the screens
profiles/daw/profile.lua   the profile
```

## The plugins

| Plugin | Service | What it does |
|--------|---------|--------------|
| `daw.core` | `daw` | Pure logic: the song model, note editing, device checks, file reading, undo, the demo song. No UI and no I/O, so the tests load it directly. |
| `daw.devices` | `daw.devices` | The registry of instruments and effects. It holds none of its own. |
| `daw.instruments` | | Registers Synth, FM Keys and Drum Kit. |
| `daw.effects` | | Registers EQ Three, Filter, Delay, Reverb, Compressor, Drive, Chorus and Utility. |
| `daw.session` | `daw.session` | The open song, its file in `songs/`, undo and redo, and what is selected. The only place a song changes. |
| `daw.engine` | `daw.engine` | Runs the engine page and keeps it playing the session's song. Recording. |
| `daw.transport` | | Play, stop, record, loop, metronome, position, tempo and time signature, on the toolbar. |
| `daw.arrange` | | Tracks and clips on a timeline, the ruler and the loop. The main view. |
| `daw.pianoroll` | | The notes of one clip, with velocity, in the bottom dock. |
| `daw.mixer` | | A strip per track and the master, with meters, in the bottom dock. |
| `daw.rack` | | The selected track's devices and every parameter, in the right dock. |
| `daw.browser` | | Songs, instruments, effects and presets, in the left dock. |
| `daw.keyboard` | | The computer keyboard as a piano. |

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

| From the page | What it says |
|---------------|--------------|
| `ready` | The page listens. The plugin sends the song. |
| `sound` (`on`) | The browser lets the page make sound, or not |
| `transport` (`playing`, `beat`) | Playing started or stopped |
| `tick` (`beat`) | About 30 times a second while playing, for the playheads |
| `levels` (`tracks`, `master`) | About 15 times a second while there is sound, for the meters |
| `recorded` (`notes`) | What was recorded, when recording or playing stops |
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
- `kind` is `instrument` for every track the DAW makes. The format keeps room for `audio` tracks, whose clips name a `file`, for the day a web view can read audio files. The engine plays no sound for them yet.
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

The cost is that a device can only combine the node types above. A new kind of sound, such as granular synthesis, needs a new node type in `daw.engine/page/patch.js`.

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
- **Audio, export and MIDI**, once the app offers what the table above lists.

## Device packs

A device pack is any plugin that lists `daw.devices` in `depends` and registers devices. `chiptune` in this registry adds a pulse lead, a triangle bass, a noise kit and a bit crusher, and is the smallest complete example. Add a pack to the DAW profile from the marketplace.
