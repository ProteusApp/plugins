# WAM Basics

Two [Web Audio Modules](https://www.webaudiomodules.com/) for the DAW profile:

- **PolySynth**, an instrument: two detuned oscillators (saw, square, triangle or sine) through a resonant low-pass filter, with attack and release. Sixteen notes at once, and the sustain pedal holds them.
- **Echo**, an effect: a stereo delay whose repeats bounce between the sides, darker each time.

They run in an AudioWorklet inside the DAW's sandboxed engine page, like any WAM in a web host. They need no permissions.

## Files

- `wam/polysynth/index.js` and `wam/echo/index.js`: the modules, readable source.
- `wam/sdk/index.js`: the Web Audio Modules SDK 0.0.12, as `@webaudiomodules/sdk` publishes it, under the MIT license in `wam/sdk/LICENSE`. `vendor.json` records its source and hash, and `node scripts/vendor.mjs verify plugins/wam.basics` checks it against npm.

The plugin exports `wam/`, so the DAW engine's page can load the modules, and registers the two devices with `daw.devices`.
