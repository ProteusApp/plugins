# Chiptune

Sounds in the style of old game consoles, for the DAW profile.

| Device | Kind | What it does |
|--------|------|--------------|
| Pulse | Instrument | A pulse wave with the narrow widths of an 8-bit console. It can start away from the note and sweep to it, and it has vibrato. Presets: Lead, Thin, Laser, Coin. |
| Triangle Bass | Instrument | A stepped triangle wave, one note at a time, for bass lines. |
| Noise Kit | Instrument | Crunchy drums: kick on C1, snare on D1, closed hat on F#1 and open hat on A#1. |
| Bit Crusher | Effect | Fewer bits and a darker top. |

## Use it

Install it from **Plugins > Store**, then open the DAW profile. The devices show up in the Browser under **Chiptune**, and in the pickers for instruments and effects.

The plugin needs `daw.devices`, so it only runs in a profile that has the DAW.

## How it works

Each device is a patch: a list of Web Audio nodes and the wires between them, registered with `app.use('daw.devices').register(spec)`. The DAW's engine builds the patch for each note, so nothing in this plugin runs while music plays. `docs/daw/DESIGN.md` in the Proteus repository describes the format.
