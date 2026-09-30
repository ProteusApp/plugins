---@meta

-- Types for the DAW: the song, devices and their patches, and the services of the plugins
-- whose ids start with daw. daw.core's README.md explains how the pieces fit.

---------------------------------------------------------------------------------------------
-- The song
---------------------------------------------------------------------------------------------

---A parameter value: a number, a choice or a file's id as text, or a switch.
---@alias Daw.Value number|string|boolean

---A song, as saved in `songs/<name>.song.json`. Times are in beats, where a beat is a
---quarter note, and the song starts at beat 0.
---@class Daw.Song
---@field format integer The file format, 1 for now.
---@field name string
---@field tempo number Beats per minute.
---@field signature integer[] Beats per bar and the beat's note value, such as `{ 4, 4 }`.
---@field loop Daw.Loop
---@field master Daw.Master
---@field tracks Daw.Track[]
---@field ids integer The last number used for an id, so new ids never repeat.

---@class Daw.Loop
---@field on boolean
---@field start number
---@field finish number

---@class Daw.Master
---@field volume number Decibels.
---@field effects Daw.DeviceRef[]

---@alias Daw.TrackKind 'instrument'|'audio'

---@class Daw.Track
---@field id string
---@field name string
---@field kind Daw.TrackKind An instrument track plays notes, and an audio track plays audio files.
---@field color string A CSS colour.
---@field volume number Decibels, from -60 (silent) to 6.
---@field pan number From -1 (left) to 1 (right).
---@field mute boolean
---@field solo boolean
---@field arm boolean Recording writes into this track.
---@field instrument? Daw.DeviceRef
---@field effects Daw.DeviceRef[]
---@field clips Daw.Clip[]

---A device placed on a track: which device, and its settings.
---@class Daw.DeviceRef
---@field id string Unique in the song.
---@field device string The id of a registered device, such as `'daw.synth'`.
---@field params table<string, Daw.Value> Values changed on the track. The rest come from the preset, then the defaults.
---@field bypass boolean
---@field preset? string The preset it loaded, by name. Its values sit under `params`.

---@class Daw.Clip
---@field id string
---@field name string
---@field start number
---@field length number
---@field color? string
---@field notes? Daw.Note[] A MIDI clip's notes, timed from the clip's start.
---@field file? string An audio clip's file: the id of a file the user gave daw.engine, never a path.
---@field offset? number Seconds into the file where an audio clip starts.
---@field gain? number An audio clip's gain in decibels.

---@class Daw.Note
---@field pitch integer A MIDI note number: 60 is middle C.
---@field start number Beats from the clip's start.
---@field length number Beats.
---@field velocity number From 0 to 1.

---What changed in the song, sent with each `daw:changed` event.
---@class Daw.Change
---@field kind 'edit'|'param'|'mix'|'open'|'undo'|'new'
---@field label? string
---@field device? string For `param`: the device's id in the song.
---@field track? string For `mix`: the track's id, or `'master'`.
---@field key? string For `param` and `mix`: what changed.
---@field value? Daw.Value

---------------------------------------------------------------------------------------------
-- Devices
---------------------------------------------------------------------------------------------

---@alias Daw.Role 'instrument'|'effect'

---@alias Daw.ParamKind 'number'|'choice'|'toggle'|'file'

---One knob, switch or menu on a device.
---@class Daw.ParamSpec
---@field key string The name the patch reads, as `$key`.
---@field label string
---@field kind? Daw.ParamKind `'number'` when nil.
---@field min? number
---@field max? number
---@field default Daw.Value
---@field curve? 'linear'|'log' `'log'` spreads a frequency range evenly along a knob.
---@field unit? ''|'Hz'|'dB'|'s'|'%'|'st'|'ct'|'x'|':1'|'b' How the value reads. `'%'` values run from 0 to 1, and `'b'` values are beats, read as note lengths such as `'1/8'`.
---@field step? number Rounds the value, such as 1 for whole semitones.
---@field options? string[] The choices of a `'choice'` parameter.
---@field group? string Puts the control under a heading, such as `'Filter'`.

---A named set of parameter values.
---@class Daw.Preset
---@field name string
---@field params table<string, Daw.Value>

---@alias Daw.NodeType
---| 'osc' # An oscillator. `wave`: sine, triangle, sawtooth, square or pulse. `freq`, `detune`, `duty`.
---| 'noise' # White noise.
---| 'sample' # An audio file the user picked. `file` names a file parameter, such as `'$file'`. `loop`, `rate`, `detune`.
---| 'gain' # Scales the sound. `gain`.
---| 'filter' # A biquad filter. `mode`, `freq`, `q`, `gain`, `detune`.
---| 'delay' # `time` in seconds, up to 4.
---| 'pan' # `pan` from -1 to 1.
---| 'compressor' # `threshold`, `knee`, `ratio`, `attack`, `release`.
---| 'reverb' # A generated room. `seconds`, `decay`.
---| 'shaper' # Distortion. `curve`: soft, hard, fold or crush. `amount` from 0 to 1.
---| 'lfo' # A slow wave for moving parameters. `wave`, `rate`, `depth`.
---| 'env' # An envelope, from 0 to `amount`. `a`, `d`, `s`, `r` in seconds, and `oneshot`.
---| 'const' # A steady value. `value`.

---One node of a patch. Fields other than `id` and `type` take a number, or an expression
---such as `'$cutoff * 2'` or `'freq * semis($tune)'`. `$name` reads a parameter,
---`freq`, `key` and `vel` read the note being played, and `bpm` reads the tempo. The
---functions are min, max, pow, exp, log, abs, floor, sqrt, clamp, semis and db.
---@class Daw.PatchNode
---@field id string
---@field type Daw.NodeType
---@field [string] any

---Nodes and the wires between them. A wire is `'from > to'` for sound, or
---`'from > to.field'` to move a field, as in `'env > amp.gain'`. `out` is the graph's
---output, and an effect's input is `in`.
---@class Daw.Graph
---@field nodes Daw.PatchNode[]
---@field connect string[]

---One sound of a drum kit, played by one note.
---@class Daw.Pad
---@field pitch integer
---@field name string
---@field choke? string Pads with the same choke group cut each other off.
---@field voice Daw.Graph

---How a device makes or changes sound. An instrument has a `voice` built for each note, or
---`pads` for a kit. An effect has `nodes` and `connect`, built once.
---@class Daw.Patch
---@field poly? integer How many notes play at once. 1 plays one at a time.
---@field voice? Daw.Graph
---@field pads? Daw.Pad[]
---@field nodes? Daw.PatchNode[]
---@field connect? string[]

---A device: an instrument or an effect, registered by a plugin with `daw.devices`.
---@class Daw.DeviceSpec
---@field id string Such as `'daw.synth'`. Songs save this id.
---@field name string
---@field role Daw.Role
---@field description? string
---@field icon? string A Lucide icon name.
---@field category? string Groups devices in the browser, such as `'Synths'` or `'Delay'`.
---@field params Daw.ParamSpec[]
---@field presets? Daw.Preset[]
---@field patch Daw.Patch
---@field owner? string Set by the service: the plugin that registered it.

---------------------------------------------------------------------------------------------
-- The engine's view of a song (posted to the engine's page as JSON)
---------------------------------------------------------------------------------------------

---@class Daw.EngineDevice
---@field id string
---@field patch table The device's patch, with its role.
---@field params table<string, Daw.Value> Every parameter, defaults filled in.
---@field bypass boolean

---@class Daw.EngineTrack
---@field id string
---@field kind Daw.TrackKind
---@field volume number
---@field pan number
---@field mute boolean
---@field solo boolean
---@field instrument? Daw.EngineDevice
---@field effects Daw.EngineDevice[]
---@field clips Daw.Clip[]

---@class Daw.EngineSong
---@field tempo number
---@field beats_per_bar integer
---@field loop { on: boolean, start: number, end: number }
---@field master { volume: number, effects: Daw.EngineDevice[] }
---@field tracks Daw.EngineTrack[]

---------------------------------------------------------------------------------------------
-- The modules of daw.core, shared as the `daw` service
---------------------------------------------------------------------------------------------

---@alias Daw.Grid '1/1'|'1/2'|'1/4'|'1/8'|'1/16'|'1/32'|'1/8T'|'1/16T'|'off'

---Beats, bars, grids and note names.
---@class Daw.TimeModule
---@field GRIDS Daw.Grid[]
---@field grid_beats fun(grid: string): number Beats in one grid step, 0 for `'off'`.
---@field snap fun(beat: number, grid: string): number Rounds to the nearest grid line.
---@field snap_down fun(beat: number, grid: string): number Rounds down to a grid line.
---@field format fun(beat: number, beats_per_bar: integer): string Such as `'3.2.1'`: bar, beat and sixteenth, from 1.
---@field format_short fun(beat: number, beats_per_bar: integer): string Such as `'3.2'`.
---@field seconds fun(beat: number, tempo: number): number
---@field format_clock fun(seconds: number): string Such as `'1:05.250'`.
---@field note_name fun(pitch: integer): string Such as `'C4'` for 60.
---@field is_black fun(pitch: integer): boolean
---@field parse_note fun(text: string): integer? Reads `'C4'`, `'F#3'` or `'60'`.

---Pure operations on a song. Each returns a new song and leaves the one it was given as it
---was, so a song can go straight into the undo history.
---@class Daw.SongModule
---@field COLORS string[]
---@field new fun(name?: string): Daw.Song
---@field copy fun(value: any): any A deep copy.
---@field new_id fun(song: Daw.Song, prefix: string): Daw.Song, string
---@field track fun(song: Daw.Song, id: string): Daw.Track?, integer?
---@field clip fun(song: Daw.Song, id: string): Daw.Clip?, Daw.Track?, integer?
---@field device fun(song: Daw.Song, id: string): Daw.DeviceRef?, Daw.Track?
---@field set fun(song: Daw.Song, fields: table<string, any>): Daw.Song Changes top-level fields, such as tempo or name.
---@field set_loop fun(song: Daw.Song, fields: { on?: boolean, start?: number, finish?: number }): Daw.Song
---@field add_track fun(song: Daw.Song, fields: table<string, any>, index?: integer): Daw.Song, string
---@field remove_track fun(song: Daw.Song, id: string): Daw.Song
---@field move_track fun(song: Daw.Song, id: string, index: integer): Daw.Song
---@field update_track fun(song: Daw.Song, id: string, fields: table<string, any>): Daw.Song
---@field set_instrument fun(song: Daw.Song, track_id: string, ref: Daw.DeviceRef?): Daw.Song, string?
---@field add_effect fun(song: Daw.Song, track_id: string, ref: Daw.DeviceRef, index?: integer): Daw.Song, string
---@field remove_device fun(song: Daw.Song, id: string): Daw.Song
---@field move_effect fun(song: Daw.Song, id: string, index: integer): Daw.Song
---@field set_param fun(song: Daw.Song, id: string, key: string, value: Daw.Value): Daw.Song
---@field update_device fun(song: Daw.Song, id: string, fields: table<string, any>): Daw.Song
---@field set_preset fun(song: Daw.Song, id: string, name?: string): Daw.Song Loads a preset, or the defaults for nil, and drops the values changed by hand.
---@field add_clip fun(song: Daw.Song, track_id: string, fields: table<string, any>): Daw.Song, string
---@field update_clip fun(song: Daw.Song, id: string, fields: table<string, any>): Daw.Song
---@field move_clip fun(song: Daw.Song, id: string, track_id: string, start: number): Daw.Song
---@field remove_clips fun(song: Daw.Song, ids: string[]): Daw.Song
---@field split_clip fun(song: Daw.Song, id: string, beat: number): Daw.Song, string?
---@field duplicate_clips fun(song: Daw.Song, ids: string[]): Daw.Song, string[]
---@field set_notes fun(song: Daw.Song, clip_id: string, notes: Daw.Note[]): Daw.Song
---@field song_end fun(song: Daw.Song): number The beat where the last clip ends.
---@field beats_per_bar fun(song: Daw.Song): integer

---Pure operations on a list of notes, for the piano roll. Each returns a new list.
---@class Daw.NotesModule
---@field sort fun(notes: Daw.Note[]): Daw.Note[]
---@field add fun(notes: Daw.Note[], note: Daw.Note): Daw.Note[], integer
---@field remove fun(notes: Daw.Note[], picked: integer[]): Daw.Note[]
---@field move fun(notes: Daw.Note[], picked: integer[], beats: number, semitones: integer, limit: number): Daw.Note[]
---@field resize fun(notes: Daw.Note[], picked: integer[], beats: number, min_length: number): Daw.Note[]
---@field quantize fun(notes: Daw.Note[], picked: integer[], grid: string, ends?: boolean): Daw.Note[]
---@field set_velocity fun(notes: Daw.Note[], picked: integer[], velocity: number): Daw.Note[]
---@field transpose fun(notes: Daw.Note[], picked: integer[], semitones: integer): Daw.Note[]
---@field at fun(notes: Daw.Note[], beat: number, pitch: integer): integer? The note under a point, last drawn first.
---@field within fun(notes: Daw.Note[], from: number, to: number, low: integer, high: integer): integer[]
---@field range fun(notes: Daw.Note[]): integer?, integer? The lowest and highest pitch.

---Checks device specs and works with parameter values.
---@class Daw.DeviceModule
---@field check fun(spec: table): Daw.DeviceSpec?, string? A cleaned spec, or why it was refused.
---@field defaults fun(spec: Daw.DeviceSpec): table<string, Daw.Value>
---@field param fun(spec: Daw.DeviceSpec, key: string): Daw.ParamSpec?
---@field value fun(spec: Daw.DeviceSpec, ref: Daw.DeviceRef, key: string): Daw.Value
---@field clamp fun(param: Daw.ParamSpec, value: any): Daw.Value
---@field to_unit fun(param: Daw.ParamSpec, value: number): number Where the value sits along its knob, from 0 to 1.
---@field from_unit fun(param: Daw.ParamSpec, unit: number): number
---@field format fun(param: Daw.ParamSpec, value: Daw.Value): string Such as `'2.40 kHz'` or `'-6.0 dB'`.
---@field ref fun(spec: Daw.DeviceSpec, preset?: string): Daw.DeviceRef A new device, with no id yet.
---@field preset fun(spec: Daw.DeviceSpec, name?: string): Daw.Preset?
---@field values fun(spec: Daw.DeviceSpec, ref: Daw.DeviceRef): table<string, Daw.Value> Defaults, then the preset, then the track's own values.

---Reads songs from files and fills in what is missing.
---@class Daw.FileModule
---@field FORMAT integer
---@field EXT string
---@field normalize fun(value: any): Daw.Song A valid song from any decoded JSON.
---@field for_save fun(song: Daw.Song): Daw.Song The song as it is written.

---Turns a song into what the audio engine plays, with each device's patch and defaults.
---@class Daw.ResolveModule
---@field song fun(song: Daw.Song, lookup: fun(id: string): Daw.DeviceSpec?): Daw.EngineSong, string[] Also the ids of devices no plugin provides.
---@field device fun(ref: Daw.DeviceRef, spec: Daw.DeviceSpec): Daw.EngineDevice

---An undo history of songs.
---@class Daw.History
---@field push fun(song: Daw.Song, key?: string) Keeps a song. Pushes with the same key in quick succession make one step.
---@field undo fun(current: Daw.Song): Daw.Song?
---@field redo fun(current: Daw.Song): Daw.Song?
---@field can_undo fun(): boolean
---@field can_redo fun(): boolean
---@field clear fun()
---@field seal fun() Ends the current step, so the next push starts a new one.

---@class Daw.HistoryModule
---@field new fun(limit?: integer, now?: fun(): number): Daw.History

---@class Daw.DemoModule
---@field song fun(): Daw.Song A short song that shows off the builtin devices.
---@field empty fun(): Daw.Song A new song with a drum track and a synth track.

---The `daw` service from daw.core.
---@class Daw.Core
---@field time Daw.TimeModule
---@field song Daw.SongModule
---@field notes Daw.NotesModule
---@field device Daw.DeviceModule
---@field file Daw.FileModule
---@field resolve Daw.ResolveModule
---@field history Daw.HistoryModule
---@field demo Daw.DemoModule

---------------------------------------------------------------------------------------------
-- daw.devices
---------------------------------------------------------------------------------------------

---The device registry. Instruments and effects come from plugins, so a new device is a new
---plugin that calls `register`.
---@class Daw.Devices
local Devices = {}

---Adds a device. It goes away when the plugin that added it stops. Raises an error when the
---spec is not valid.
---@param spec Daw.DeviceSpec
---@return Daw.DeviceSpec
function Devices.register (spec) end

---@param id string
---@return Daw.DeviceSpec?
function Devices.get (id) end

---@param role? Daw.Role
---@return Daw.DeviceSpec[]
function Devices.list (role) end

---A new device of this kind, ready to put on a track. Nil for an unknown id.
---@param id string
---@param preset? string
---@return Daw.DeviceRef?
function Devices.ref (id, preset) end

---------------------------------------------------------------------------------------------
-- daw.session
---------------------------------------------------------------------------------------------

---The open song, its file, its undo history, and what is selected. Every change goes through
---`apply`, which sends `daw:changed` with the new song and a `Daw.Change`.
---@class Daw.Session
local Session = {}

---@return Daw.Song
function Session.song () end

---Replaces the song with a changed copy, as one undo step. Changes with the same `coalesce`
---key in quick succession, such as a knob being dragged, make one step.
---@param song Daw.Song
---@param change? Daw.Change
---@param coalesce? string
function Session.apply (song, change, coalesce) end

---Ends the current undo step, such as when a drag ends.
function Session.seal () end

function Session.undo () end
function Session.redo () end

---@return boolean
function Session.can_undo () end

---@return boolean
function Session.can_redo () end

---The open song's file in the workspace, such as `songs/Demo.song.json`. Nil until saved.
---@return string?
function Session.path () end

---@return boolean
function Session.dirty () end

---@param song? Daw.Song
function Session.new (song) end

---@param path string A workspace path.
---@return boolean ok
function Session.open (path) end

---Saves the song. Asks for a name the first time.
---@param done? fun(path: string)
function Session.save (done) end

---@param done? fun(path: string)
function Session.save_as (done) end

---Songs in `songs/`, the most recently opened first.
---@return { path: string, name: string }[]
function Session.list () end

---@return string?
function Session.selected_track () end

---@param id string?
function Session.select_track (id) end

---@return string[]
function Session.selected_clips () end

---@param ids string[]
function Session.select_clips (ids) end

---The clip the piano roll edits.
---@return string?
function Session.editing () end

---@param id string?
function Session.edit_clip (id) end

---------------------------------------------------------------------------------------------
-- daw.engine
---------------------------------------------------------------------------------------------

---The audio engine, a page in a web view. It follows the session's song by itself, so most
---plugins only start and stop it, and play notes. Its answers, such as the position and the
---levels, are the latest the page reported.
---@class Daw.Engine
local Engine = {}

---@param from? number The beat to start from. The last stop point when nil.
function Engine.play (from) end

---Stops and goes back to where playing started.
function Engine.stop () end

---Stops and stays where it is.
function Engine.pause () end

---Plays or stops.
function Engine.toggle () end

---@param beat number
function Engine.seek (beat) end

---@return number
function Engine.position () end

---@return boolean
function Engine.playing () end

---Plays a note on a track now, such as from the piano roll's keys.
---@param track_id string
---@param pitch integer
---@param velocity? number
function Engine.note_on (track_id, pitch, velocity) end

---@param track_id string
---@param pitch integer
function Engine.note_off (track_id, pitch) end

function Engine.all_notes_off () end

---@param on boolean
function Engine.set_metronome (on) end

---@return boolean
function Engine.metronome () end

---Starts or stops recording notes into the armed track while it plays.
---@param on boolean
function Engine.set_recording (on) end

---@return boolean
function Engine.recording () end

---Track levels from 0 to 1 by track id, and the master's left and right.
---@return { tracks: table<string, number>, master: number[] }
function Engine.levels () end

---True once the page may make sound. Where the browser holds it, a click on the meter starts it.
---@return boolean
function Engine.sound () end

---Asks the user for audio files in the system's open dialog. `cb` gets the files picked, by
---the id a song keeps and the name to show, or an empty list when the user cancelled.
---@param multiple boolean
---@param cb fun(files: { id: string, name: string }[])
function Engine.pick_audio (multiple, cb) end

---What the engine knows of an audio file, by id. Nil for an id it was never given, such as
---one in a song from another computer.
---@param id string
---@return Daw.EngineFile?
function Engine.file (id) end

---Asks the user where to save, then plays the whole song into that WAV file.
function Engine.export_wav () end

---An audio file the user gave the engine. `seconds` and `peaks` arrive once the page decoded
---it, and `daw:file` fires then.
---@class Daw.EngineFile
---@field name string
---@field seconds? number
---@field peaks? number[] The loudest sample in each of 1000 even stretches, from 0 to 1.
---@field failed? string Why it did not load.
