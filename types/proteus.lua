---@meta

-- Types for the Proteus kernel and the `app` table every plugin receives.
--
-- This folder holds type information only, for lua-language-server. Nothing here runs.
-- Start a plugin with `---@type Proteus.Plugin` above its returned table, and every
-- `app.` call after that completes and is checked.

---A plugin: the table returned by `plugins/<group>/<id>/init.lua`.
---
---```lua
------@type Proteus.Plugin
---return {
---  name = 'Clock',
---  depends = { 'proteus.ui.statusbar' },
---  activate = function (app)
---    app.use('status').add({ text = 'hi' })
---  end,
---}
---```
---@class Proteus.Plugin
---@field name string Shown in the plugin manager.
---@field description? string One sentence on what the plugin does.
---@field version? string Such as `'1.0.0'`.
---@field depends? string[] Plugin ids that must start first. The plugin fails if one cannot start.
---@field optional? string[] Plugin ids that start first when the profile lists them.
---@field conflicts? string[] Plugin ids that cannot run at the same time as this one.
---@field permissions? Proteus.Permission[] What a plugin that does not ship with the app may do beyond drawing and keeping its own data.
---@field folders? string[] Workspace folders the plugin writes its files in, such as `'shaders'`. Folders the app ships, such as `plugins` and `data`, cannot be claimed.
---@field exports? string[] Folders right inside the plugin, such as `'wam'`, that any plugin's web view may load with `mounts`.
---@field requires? Proteus.Requires The Proteus version and features the plugin needs.
---@field activate? fun(app: Proteus.App) Runs when the plugin starts.
---@field deactivate? fun(app: Proteus.App) Runs when the plugin stops, before its cleanup functions.

---@alias Proteus.Permission
---| 'net' # Sends HTTP requests, opens web pages in the browser and connects to servers on this computer.
---| 'clipboard' # Reads the clipboard, and pastes.
---| 'midi' # Hears MIDI keyboards: notes and controls, never SysEx, and nothing sent back.
---| 'files' # Reads and writes files anywhere on disk. Amounts to full access.
---| 'process' # Runs programs and opens terminals. Amounts to full access.
---| 'workspace' # Writes anywhere in the workspace, plugins and settings included. Amounts to full access.
---| 'kernel' # Starts, stops and reloads plugins, and trusts folders. Amounts to full access.

---@alias Proteus.Feature
---| 'permissions' # The permission model: `permissions`, `folders` and restricted plugins.
---| 'folders' # `folders` in a plugin's table.
---| 'plugin-files' # `app.plugin`, which reads the plugin's own files.
---| 'webview' # The `webview` widget and `ui.webview`.
---| 'languages' # `ui.language`, which adds a language to the code editor.
---| 'grants' # `app.grants`: files the user picks for the plugin, and their bytes in its web view.
---| 'midi' # The `midi` permission and `app.midi`.
---| 'autoplay' # `autoplay` in `ui.webview`: sound before anyone clicks in the page.
---| 'icons' # File icon packs registered with the `icons` service.
---| 'windows' # Floating windows on a desktop, from `proteus.ui.windows` and the `windows` service.
---| 'webview-files' # `files` and `mounts` in `ui.webview`, and `exports` in a plugin's table.
---| 'webview-disk' # `view:widget ('send_path', path)`: the bytes of a file the plugin names, in its web view.
---| 'tcp' # `app.net.connect`, which connects to a server on this computer's loopback address.
---| 'http-bodies' # `app.net.fetch` with bytes, files and multipart bodies, `timeout`, `redirects`, `encoding`, and a call that can be cancelled.
---| 'grants-read' # `app.grants.read`, the text of a file the user picked.
---| 'perf' # `app.kernel.perf`: how long each plugin's callbacks take, and the page's frames and size.

---@class Proteus.Requires
---@field proteus? string The versions of Proteus it runs on, such as `'>=0.2.0'`. Conditions separated by spaces must all hold.
---@field features? Proteus.Feature[] Features it needs. A Proteus without one refuses to start the plugin.

---@class Proteus.PermissionInfo
---@field id Proteus.Permission
---@field label string
---@field description string
---@field full boolean True when the permission amounts to full access to the computer.

---@class Proteus.ProvideOptions
---@field needs? Proteus.Permission|Proteus.Permission[] Permissions a restricted plugin needs to use the service. Set it when the service does something for its user that the user could not do itself.

---@class Proteus.EventRule
---@field needs Proteus.Permission|Proteus.Permission[] Permissions a restricted plugin needs to hear the event.
---@field allow? fun(...: any): boolean Gets the event's arguments. True lets a restricted plugin without the permissions hear this one call.

---A plugin's own files, read from the folder it was loaded from.
---@class Proteus.PluginFiles
---@field dir string Its folder, such as `'plugins/community/shader.preview'`.
local PluginFiles = {}

---Reads a file from the plugin's folder, such as `'page/preview.html'`.
---@param rel string
---@return string?
function PluginFiles.read (rel) end

---Lists a folder inside the plugin's folder, or the folder itself.
---@param rel? string
---@return Proteus.FsEntry[]
function PluginFiles.list (rel) end

---A profile: the table returned by `profiles/<id>.lua`.
---@class Proteus.ProfileSpec
---@field name string
---@field description? string
---@field plugins string[] Plugin ids to start. Their dependencies start too.
---@field settings? table<string, any> Setting values for this profile.
---@field extensible? boolean Lets a builtin profile keep plugins switched on and off from inside the app.

---A loaded profile.
---@class Proteus.Profile: Proteus.ProfileSpec
---@field id string The file name without `.lua`.
---@field settings table<string, any>
---@field builtin boolean True for a profile shipped with the app. Its file cannot change.
---@field fixed boolean True when its plugin list cannot change: a builtin profile that is not `extensible`.
---@field added string[] Plugins switched on from inside the app.
---@field removed string[] Plugins switched off from inside the app.

---Event names the builtin plugins send. Any other string works too.
---@alias Proteus.EventName
---| 'log' # A log line was written. Receives an `Proteus.LogEntry`.
---| 'fs:changed' # A workspace file changed. Receives its path, and true when another window or another program changed it.
---| 'fs:renamed' # A workspace file or folder moved. Receives the old path, the new path, and true when another window or another program moved it.
---| 'file:open' # Ask an editor to open a file. Send a workspace path or a full path, and optional `{ line, col }`.
---| 'disk:changed' # A trusted plugin tells the editor that files on disk changed. Receives a Proteus.DirChange[] and the whole Proteus.DirEvent. A restricted plugin needs `files` to hear it.
---| 'disk:renamed' # A trusted plugin tells the editor that a file or folder on disk moved. Receives the old and the new full path. A restricted plugin needs `files` to hear it.
---| 'code:disk_changed' # From the Code Editor: files changed in the open folder. Receives a Proteus.DirChange[] and the whole Proteus.DirEvent. Needs `files`.
---| 'code:disk_renamed' # From the Code Editor: a file or folder moved in its explorer. Receives the old and the new full path. Needs `files`.
---| 'git:status' # From the Git plugin: Git's view of the open folder changed. Receives a table of full paths to a Git.Kind such as 'modified'. Needs `files`.
---| 'kernel:ready' # Every plugin in the profile has started.
---| 'kernel:error' # A plugin raised an error. Receives the plugin id and the message.
---| 'kernel:plugin_started' # Receives the plugin id.
---| 'kernel:plugin_stopped' # Receives the plugin id.
---| 'kernel:plugin_failed' # Receives the plugin id and the error.
---| 'kernel:plugin_reloaded' # Receives the plugin id, whether it worked, and any error.
---| 'kernel:service' # A service was provided. Receives its name.
---| 'commands:changed' # The command list changed.
---| 'commands:before_run' # A command is about to run. Receives its id.
---| 'keys:changed' # Key bindings changed.
---| 'settings:changed' # Receives the setting key and its new value.
---| 'settings:defined' # Receives the setting key.
---| 'themes:applied' # Receives the theme id.
---| 'tabs:changed' # Receives the active tab id, or nil.
---| 'views:shown' # Receives the view id.
---| 'shell:visibility' # Receives the dock name and whether it shows.
---| 'editor:saved' # Receives the saved file's path. A restricted plugin needs `files` to hear about a file outside the workspace.
---| 'diagnostics:changed' # Receives the file path whose problems changed.
---| 'tools:changed' # Receives the tool id whose status changed.
---| 'tools:log' # Receives the tool id and the new Proteus.ToolLogLine. A restricted plugin needs `process`, as for the `tools` service.
---| 'editor:opened' # Receives the Proteus.DocInfo of a newly opened document. A restricted plugin needs `files`, as for the `editor` service.
---| 'editor:changed' # Receives the Proteus.DocInfo of an edited document. A restricted plugin needs `files`.
---| 'editor:closed' # Receives the closed document's path. A restricted plugin needs `files` to hear about a file outside the workspace.
---| 'editor:dirty' # A document gained or lost unsaved edits. Receives its path and true while it has them. A restricted plugin needs `files` to hear about a file outside the workspace.
---| 'nodal:changed' # The Nodal document changed, or the values of the app running in the Preview did. Receives the new Nodal.Snapshot.
---| 'nodal:selected' # The Nodal selection changed. Receives the node id, or nil.
---| 'nodal:debug' # The Nodal watch list or breakpoints changed.

---The table each plugin receives in `activate`. Everything a plugin does goes through it.
---@class Proteus.App
---@field id string This plugin's id.
---@field platform 'tauri'|'browser' The desktop app, or a plain browser.
---@field os string Such as `'windows'`, `'macos'` or `'linux'`.
---@field dom Proteus.Dom Raw DOM access by handle. Most plugins use the `ui` service instead.
---@field fs Proteus.Fs Workspace files, plus files anywhere on disk.
---@field json Proteus.Json
---@field store Proteus.Store Small saved data for this plugin, in `data/store/<id>.json`.
---@field secrets Proteus.Secrets Secrets such as a sign-in, kept in the system's credential store.
---@field grants Proteus.Grants Files the user picks for this plugin in the system's dialogs. Needs no permission.
---@field midi Proteus.Midi Notes and controls from MIDI keyboards. Needs the `midi` permission.
---@field timer Proteus.Timer
---@field util Proteus.Util
---@field window Proteus.Window
---@field system Proteus.System
---@field process Proteus.Process Runs programs such as language servers.
---@field net Proteus.Net Sends HTTP requests and connects to servers on this computer.
---@field kernel Proteus.Kernel Lists, starts and reloads plugins, and switches profiles.
---@field trusted boolean True when the plugin ships with the app, or is a workspace edit of one. Every other plugin is restricted to its `permissions`.
---@field permissions Proteus.Permission[] The permissions the plugin runs with. A trusted plugin has them all.
---@field plugin Proteus.PluginFiles The plugin's own files.
---@field namespaces string[] For a restricted plugin, what its service, event, command and setting names may start with: the first and last part of its id, less those the app's own plugins use. Empty for a trusted plugin, which may use any name.
local App = {}

---Registers a function to run when this plugin stops. Returns a function that cancels it.
---@param fn fun()
---@return fun() cancel
function App.dispose (fn) end

---Writes to the Console log.
---@param ... any
function App.log (...) end

---Writes a warning to the Console log.
---@param ... any
function App.warn (...) end

---Writes an error to the Console log.
---@param ... any
function App.error (...) end

---Calls `fn(...)`. An error is logged against this plugin instead of being raised.
---@generic R
---@param fn fun(...: any): R?
---@param ... any
---@return R?
function App.try (fn, ...) end

---Calls `fn` each time `event` is sent. Returns a function that stops listening.
---The listener stops by itself when this plugin stops.
---@param event Proteus.EventName|string
---@param fn fun(...: any)
---@return fun() off
function App.on (event, fn) end

---Sends an event to every listener.
---@param event Proteus.EventName|string
---@param ... any
function App.emit (event, ...) end

---Keeps `event` from restricted plugins without the permissions in `rule.needs`. Their
---listeners are not called, unless `rule.allow` returns true for that call. Trusted plugins
---hear every call. Set it before the first `emit`, for an event whose arguments carry what
---the permission guards, such as a file's text. The rule goes when this plugin stops.
---@param event Proteus.EventName|string
---@param rule Proteus.EventRule
function App.protect_event (event, rule) end

---Shares a table with every plugin under `name`. A restricted plugin names its services after
---itself, such as `shader.docs` from the plugin `shader.docs` or `shader.core`, and the others
---see them read only.
---@param name string
---@param value table
---@param opts? Proteus.ProvideOptions
function App.provide (name, value, opts) end

---Shares a service where each user gets its own copy, built by `make(user_app)`.
---The service can clean up after each user through `user_app.dispose`. A restricted provider
---gets only the user's `id`, `trusted`, `permissions`, `dispose`, `on` and log functions. Its
---`on` hears events as a plugin with no permissions.
---@param name string
---@param make fun(consumer: Proteus.App): table
---@param opts? Proteus.ProvideOptions
function App.provide_scoped (name, make, opts) end

---Returns a service, or raises an error naming the missing plugin.
---List the plugin that provides it in `depends`.
---@overload fun(name: 'ui'): Proteus.UI
---@overload fun(name: 'http'): Proteus.Http
---@overload fun(name: 'commands'): Proteus.Commands
---@overload fun(name: 'keys'): Proteus.Keys
---@overload fun(name: 'settings'): Proteus.Settings
---@overload fun(name: 'themes'): Proteus.Themes
---@overload fun(name: 'icons'): Proteus.Icons
---@overload fun(name: 'menus'): Proteus.Menus
---@overload fun(name: 'shell'): Proteus.Shell
---@overload fun(name: 'views'): Proteus.Views
---@overload fun(name: 'windows'): Proteus.Windows
---@overload fun(name: 'tabs'): Proteus.Tabs
---@overload fun(name: 'picker'): Proteus.Picker
---@overload fun(name: 'overlays'): Proteus.Overlays
---@overload fun(name: 'notify'): Proteus.Notify
---@overload fun(name: 'toolbar'): Proteus.Toolbar
---@overload fun(name: 'status'): Proteus.Status
---@overload fun(name: 'editor'): Proteus.Editor
---@overload fun(name: 'console'): Proteus.Console
---@overload fun(name: 'tools'): Proteus.Tools
---@overload fun(name: 'diagnostics'): Proteus.Diagnostics
---@overload fun(name: 'luals'): Proteus.Luals
---@overload fun(name: 'discord'): Proteus.Discord
---@overload fun(name: 'project'): Proteus.Project
---@overload fun(name: 'marketplace'): Proteus.Marketplace
---@overload fun(name: 'publishing'): Proteus.Publishing
---@overload fun(name: 'files'): Proteus.Files
---@overload fun(name: 'nodal'): Nodal.Core
---@overload fun(name: 'nodal.store'): Nodal.Store
---@overload fun(name: 'nodal.canvas'): Nodal.Canvas
---@overload fun(name: 'nodal.app'): Nodal.AppService
---@param name string
---@return any
function App.use (name) end

---Returns a service, or nil when no running plugin provides it.
---@overload fun(name: 'ui'): Proteus.UI?
---@overload fun(name: 'http'): Proteus.Http?
---@overload fun(name: 'commands'): Proteus.Commands?
---@overload fun(name: 'keys'): Proteus.Keys?
---@overload fun(name: 'settings'): Proteus.Settings?
---@overload fun(name: 'themes'): Proteus.Themes?
---@overload fun(name: 'icons'): Proteus.Icons?
---@overload fun(name: 'menus'): Proteus.Menus?
---@overload fun(name: 'shell'): Proteus.Shell?
---@overload fun(name: 'views'): Proteus.Views?
---@overload fun(name: 'windows'): Proteus.Windows?
---@overload fun(name: 'tabs'): Proteus.Tabs?
---@overload fun(name: 'picker'): Proteus.Picker?
---@overload fun(name: 'overlays'): Proteus.Overlays?
---@overload fun(name: 'notify'): Proteus.Notify?
---@overload fun(name: 'toolbar'): Proteus.Toolbar?
---@overload fun(name: 'status'): Proteus.Status?
---@overload fun(name: 'editor'): Proteus.Editor?
---@overload fun(name: 'console'): Proteus.Console?
---@overload fun(name: 'tools'): Proteus.Tools?
---@overload fun(name: 'diagnostics'): Proteus.Diagnostics?
---@overload fun(name: 'luals'): Proteus.Luals?
---@overload fun(name: 'discord'): Proteus.Discord?
---@overload fun(name: 'project'): Proteus.Project?
---@overload fun(name: 'marketplace'): Proteus.Marketplace?
---@overload fun(name: 'publishing'): Proteus.Publishing?
---@overload fun(name: 'files'): Proteus.Files?
---@overload fun(name: 'nodal'): Nodal.Core?
---@overload fun(name: 'nodal.store'): Nodal.Store?
---@overload fun(name: 'nodal.canvas'): Nodal.Canvas?
---@overload fun(name: 'nodal.app'): Nodal.AppService?
---@param name string
---@return any
function App.try_use (name) end

---------------------------------------------------------------------------------------------
-- Files
---------------------------------------------------------------------------------------------

---@alias Proteus.Layer
---| 'all' # The project's `.proteus` copy, then the workspace copy, then the builtin one.
---| 'builtin' # Only files shipped with the app.
---| 'user' # Only files in the workspace folder.
---| 'project' # Only files in the open folder's `.proteus` folder, when one is in use.
---| 'locked' # What a locked plugin reads: the project's copy, then the builtin one.

---@class Proteus.FsEntry
---@field name string The last part of the path.
---@field path string The path from the workspace root.
---@field dir boolean
---@field builtin boolean True when the builtin layer has it.
---@field user boolean True when the workspace folder has it.
---@field project boolean True when the open folder's `.proteus` folder has it.

---@class Proteus.FsStat
---@field path string
---@field dir boolean
---@field builtin boolean
---@field user boolean
---@field project boolean

---@alias Proteus.FileSource
---| 'builtin' # Shipped with the app, unchanged.
---| 'override' # A builtin file with a changed copy in the workspace.
---| 'user' # Only in the workspace.
---| 'project' # From the open folder's `.proteus` folder, which wins over the others.

---@class Proteus.DialogFilter
---@field name string Such as `'Images'`.
---@field extensions string[] Such as `{ 'png', 'jpg' }`.

---@class Proteus.DialogOptions
---@field title? string
---@field directory? boolean Pick a folder instead of a file.
---@field multiple? boolean
---@field default_path? string
---@field filters? Proteus.DialogFilter[]

---Workspace files. Paths are relative to the workspace root and use `/`.
---Reads are instant. Writes save to disk in the background.
---@class Proteus.Fs
local Fs = {}

---@param path string
---@param layer? Proteus.Layer
---@return string? text nil when there is no such file
function Fs.read (path, layer) end

---Writes a file. Folders are made as needed. Locked files raise an error. A file the open
---folder's `.proteus` folder has is saved there, and any other file goes to the workspace.
---`layer` picks one.
---@param path string
---@param text string
---@param layer? 'user'|'project'
function Fs.write (path, text, layer) end

---Removes a workspace file, or a folder and everything in it.
---A builtin file underneath becomes visible again.
---@param path string
---@return boolean removed
function Fs.remove (path) end

---@param path string
function Fs.mkdir (path) end

---Moves or renames a workspace file or folder. Builtin files cannot move.
---@param from string
---@param to string
function Fs.rename (from, to) end

---Reads the workspace folder again and picks up files that changed outside the app. The
---app watches the folder already, so this is only needed when a change was missed. Each
---change arrives as an `fs:changed` event. `cb` gets how many changes there were.
---@param cb? fun(count: integer?, err: string?)
function Fs.reload (cb) end

---@param path string
---@param layer? Proteus.Layer
---@return boolean
function Fs.exists (path, layer) end

---Lists a folder, folders first.
---@param path? string The workspace root when nil.
---@param layer? Proteus.Layer
---@return Proteus.FsEntry[]
function Fs.list (path, layer) end

---@param path string
---@return Proteus.FsStat
function Fs.stat (path) end

---Every file path in both layers, sorted.
---@return string[]
function Fs.files () end

---The full path on disk of a workspace path, with `/`, such as
---`C:/Users/ana/.proteus/plugins/mine/my.clock`. `''` is the workspace folder itself. Nil in a
---browser, where the workspace is not on disk. A restricted plugin needs `files`.
---@param path string
---@return string?
function Fs.disk_path (path) end

---@param path string
---@return Proteus.FileSource
function Fs.source (path) end

---Reads and decodes a JSON file. Returns `default` when it is missing or unreadable.
---@generic T
---@param path string
---@param default T
---@return T|any
function Fs.read_json (path, default) end

---@param path string
---@param value any
function Fs.write_json (path, value) end

---Shows the system Open dialog. Calls `cb(paths)`, with an empty list when cancelled.
---@param opts Proteus.DialogOptions
---@param cb fun(paths: string[]?, err: string?)
function Fs.pick_open (opts, cb) end

---Shows the system Save dialog. Calls `cb(path)`, with nil when cancelled.
---@param opts Proteus.DialogOptions
---@param cb fun(path: string?, err: string?)
function Fs.pick_save (opts, cb) end

---Reads any file on disk by its full path.
---@param path string
---@param cb fun(text: string?, err: string?)
function Fs.read_file (path, cb) end

---Lists any folder on disk by its full path: names only, sorted, folders ending in `/`.
---Needs the desktop app.
---@param path string
---@param cb fun(names: string[]?, err: string?)
function Fs.list_dir (path, cb) end

---Writes any file on disk by its full path.
---@param path string
---@param text string
---@param cb? fun(ok: any, err: string?)
function Fs.write_file (path, text, cb) end

---Reads the text files in a zip file on disk, such as the parts of an `.xlsx` file. Calls
---`cb(files, nil, skipped)`, where `files` maps each path inside the zip to its text. Files
---that are not UTF-8 text, such as pictures, are left out and named in `skipped`. Calls
---`cb(nil, err)` when the zip cannot be read. Needs the desktop app.
---@param path string
---@param cb fun(files: table<string, string>?, err: string?, skipped: string[]?)
function Fs.read_zip (path, cb) end

---Writes a zip file on disk by its full path. `files` maps each path inside the zip to its
---text, and each file is compressed. Needs the desktop app.
---@param path string
---@param files table<string, string>
---@param cb? fun(ok: any, err: string?)
function Fs.write_zip (path, files, cb) end

---Looks up any file or folder on disk by its full path. Needs the desktop app.
---@param path string
---@param cb fun(stat: Proteus.PathStat?, err: string?)
function Fs.stat_path (path, cb) end

---Makes a folder on disk, and any folders above it that are missing. Needs the desktop app.
---@param path string
---@param cb? fun(ok: any, err: string?)
function Fs.make_dir (path, cb) end

---Deletes a file on disk, or a folder and everything in it, for good. Needs the desktop app.
---@param path string
---@param cb? fun(ok: any, err: string?)
function Fs.delete_path (path, cb) end

---Moves a file on disk, or a folder and everything in it, to the Recycle Bin or the system's
---trash, where it can be brought back. Needs the desktop app.
---@param path string
---@param cb? fun(ok: any, err: string?)
function Fs.trash_path (path, cb) end

---Brings back what `trash_path` last moved to the trash from `path`, as an undo of the
---delete. It fails when something is at `path` again, and on macOS, whose Trash lets only
---the user put things back. Needs the desktop app.
---@param path string
---@param cb? fun(ok: any, err: string?)
function Fs.untrash_path (path, cb) end

---Moves or renames a file or folder on disk. Fails when `to` exists already, unless only the
---case of its letters differs. Folders above `to` are made as needed. Needs the desktop app.
---@param from string
---@param to string
---@param cb? fun(ok: any, err: string?)
function Fs.move_path (from, to, cb) end

---Copies a file, or a folder and everything in it, on disk. Fails when `to` exists already.
---Needs the desktop app.
---@param from string
---@param to string
---@param cb? fun(ok: any, err: string?)
function Fs.copy_path (from, to, cb) end

---Lists every file under a folder on disk, the way a search sees it: what `.gitignore` leaves
---out and the `.git` folder are skipped. Needs the desktop app.
---@param path string
---@param opts? Proteus.WalkOptions
---@param cb fun(result: Proteus.WalkResult?, err: string?)
function Fs.walk_dir (path, opts, cb) end

---Finds text in every file under a folder on disk. It reads the same files `walk_dir` lists,
---and skips binary files and files over 2 MB. `cancel` on the handle stops the search, and
---`cb` is not called. Needs the desktop app.
---@param path string
---@param query string
---@param opts? Proteus.SearchOptions
---@param cb fun(result: Proteus.SearchResult?, err: string?)
---@return Proteus.SearchHandle
function Fs.search_dir (path, query, opts, cb) end

---The names in a folder on disk that `.gitignore` leaves out, as `walk_dir` would, with `/`
---after folders. The rules of the folders above count too. Needs the desktop app.
---@param path string
---@param cb fun(names: string[]?, err: string?)
function Fs.ignored_names (path, cb) end

---Puts `opts.replace` in place of every match of a search in `text`, as `search_dir` finds
---them: line by line, keeping each line's ending. `cb` gets the new text and how many matches
---changed. Needs the desktop app.
---@param text string
---@param query string
---@param opts Proteus.SearchOptions
---@param cb fun(result: { text: string, count: integer }?, err: string?)
function Fs.replace_text (text, query, opts, cb) end

---Watches a folder on disk and everything in it. `fn` gets the changes in batches, a moment
---after they happen. The watcher stops when the plugin stops, or on `close`. Needs the
---desktop app.
---@param path string
---@param fn fun(ev: Proteus.DirEvent)
---@param on_error? fun(err: string) Runs when the folder cannot be watched.
---@return Proteus.WatchHandle
function Fs.watch_dir (path, fn, on_error) end

---@class Proteus.PathStat
---@field exists boolean
---@field dir boolean
---@field size number Bytes.
---@field modified number Milliseconds since 1970, or 0 when unknown.

---Which files a walk or a search looks at.
---@class Proteus.WalkOptions
---@field skip? string[] Folder names to leave out wherever they are, such as `node_modules`.
---@field include? string[] Glob patterns a file must match, such as `*.ts` or `src/**`.
---@field exclude? string[] Glob patterns that leave files out, such as `*.min.js`.
---@field limit? integer Stops after this many files or matches.
---@field no_ignore? boolean Also looks at what `.gitignore` leaves out.

---@class Proteus.WalkResult
---@field files string[] Paths from the folder, with `/`, sorted.
---@field truncated boolean True when the limit cut the list short.

---@class Proteus.SearchOptions: Proteus.WalkOptions
---@field case? boolean Letters must match in case.
---@field word? boolean Matches whole words only.
---@field regex? boolean The query is a regular expression.
---@field replace? string Text to put in place of each match. With `regex`, `$1` or `${name}` stands for a group, and `${1}` keeps a group apart from letters after it. Each match then carries `with`.

---One match. The line is split around it, so the matched text can be marked.
---@class Proteus.SearchMatch
---@field path string The file, from the folder searched, with `/`.
---@field line integer From 1.
---@field col integer From 1, counted the way the code editor counts.
---@field before string The line before the match, cut short when long.
---@field hit string The matched text.
---@field after string The line after the match, cut short when long.
---@field with? string What the match becomes, when the search has `replace`.

---@class Proteus.SearchResult
---@field matches Proteus.SearchMatch[]
---@field truncated boolean True when the limit cut the matches short.
---@field searched integer How many files were read.

---@class Proteus.DirChange
---@field path string A full path, with `/`.
---@field kind 'file'|'dir'|'remove' What is at the path now.
---@field ignored? boolean True when a `.gitignore` leaves the path out, as `walk_dir` does.

---A batch of changes in a watched folder.
---@class Proteus.DirEvent
---@field changes Proteus.DirChange[]
---@field overflow boolean Too much changed to list, so read everything again.
---@field git boolean Git's own records changed, such as the branch or a new commit.

---@class Proteus.SearchHandle
---@field cancel fun() Stops the search. Its callback is not called.

---@class Proteus.WatchHandle
---@field close fun() Stops watching.

---------------------------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------------------------

---@class Proteus.Json
local Json = {}

---@param value any
---@param pretty? boolean
---@return string
function Json.encode (value, pretty) end

---@param text string
---@return any
function Json.decode (text) end

---@class Proteus.Store
local Store = {}

---@generic T
---@param key string
---@param default? T
---@return T|any
function Store.get (key, default) end

---Saves a value. Writes reach disk a moment later, all at once.
---@param key string
---@param value any
function Store.set (key, value) end

---@return table<string, any>
function Store.all () end

---Writes any pending changes to disk now.
function Store.flush () end

---Secrets such as a sign-in, kept in the system's credential store: Windows Credential
---Manager, the macOS Keychain, or the Secret Service on Linux. The store encrypts them for
---the user, and they survive restarts. Each plugin has its own names, so no plugin reads
---another's. A browser keeps none.
---@class Proteus.Secrets
local Secrets = {}

---Reads a secret. `cb` gets nil when there is none.
---@param name string
---@param cb fun(value: string?, err: string?)
function Secrets.get (name, cb) end

---@param name string
---@param value string
---@param cb? fun(ok: any, err: string?)
function Secrets.set (name, value, cb) end

---Forgets a secret.
---@param name string
---@param cb? fun(ok: any, err: string?)
function Secrets.delete (name, cb) end

---A file the user picked for this plugin. The plugin knows it by id and name, never by path.
---@class Proteus.FileGrant
---@field id string A file picked to open keeps its id across restarts, so a document can keep it.
---@field name string The file's name, such as `kick.wav`.
---@field mode 'read'|'write' Picked in an open dialog, or a save dialog.

---A grant with its path, as the marketplace shows it.
---@class Proteus.FileGrantInfo: Proteus.FileGrant
---@field path string
---@field time number When the user picked it.
---@field sleeping? 'asks'|'refused' Set for a file picked to open before this session. `asks`: the plugin's next use asks the user first. `refused`: the user did not allow it this session.

---Files the user hands this plugin, one choice at a time, in the system's own open and save
---dialogs. No permission is needed, since the user picks each file. The plugin gets an id,
---and `view:widget ('send_file', id)` sends the file's bytes into its web view, while
---`view:widget ('allow_save', id)` lets the page write once to a file the user chose to save.
---
---A file picked to open works for the rest of the session. After a restart, the plugin's
---first `send_file` asks the user once, in the system's own dialog, about all its older
---files. Allow sends them for the session. Don't allow refuses them until the app starts
---again: the page gets `{ id, name, tag, bytes = nil, error }` in place of the bytes, as for
---a file that could not be read. A file the plugin has not used in 90 days is forgotten.
---The desktop app only.
---@class Proteus.Grants
local Grants = {}

---Asks the user for files to open. `cb` gets the grants, or nil when the user cancelled.
---Picking a file again gives back its id, and wakes it for the session.
---@param opts { title?: string, filters?: Proteus.DialogFilter[], multiple?: boolean }
---@param cb fun(grants: Proteus.FileGrant[]?, err: string?)
function Grants.open (opts, cb) end

---Asks the user where to save a file. `cb` gets the grant, or nil when the user cancelled.
---The grant allows one write, and lasts until the page writes the file or the window closes.
---@param opts { title?: string, filters?: Proteus.DialogFilter[], name?: string }
---@param cb fun(grant: Proteus.FileGrant?, err: string?)
function Grants.save (opts, cb) end

---A grant this plugin holds, or nil.
---@param id string
---@return Proteus.FileGrant?
function Grants.get (id) end

---@return Proteus.FileGrant[]
function Grants.list () end

---Gives a file back. The plugin cannot reach it again unless the user picks it again.
---@param id string
function Grants.forget (id) end

---Reads the text of a file the user picked to open. A file from an earlier session asks the
---user first. Raises an error for an id the plugin does not hold, or a file picked to save.
---@param id string
---@param cb fun(text: string?, err: string?)
function Grants.read (id, cb) end

---One message from a MIDI keyboard.
---@class Proteus.MidiMessage
---@field input string The keyboard's name.
---@field type 'note_on'|'note_off'|'pressure'|'controller'|'program'|'channel_pressure'|'pitch_bend' A note on with no velocity arrives as a note off.
---@field channel integer From 1 to 16.
---@field note? integer For notes and key pressure: 60 is middle C.
---@field velocity? integer For notes and key pressure, from 0 to 127.
---@field controller? integer For a controller, such as 1 for the mod wheel or 64 for the sustain pedal.
---@field value? integer A controller's value or a pressure from 0 to 127, a program number, or a pitch bend from -8192 to 8191.
---@field time number When it arrived, in microseconds from a fixed point.

---@class Proteus.MidiListener
---@field close fun() Stops listening now instead of when the plugin stops.

---MIDI keyboards. Only input: nothing is ever sent to a device, and no SysEx arrives.
---@class Proteus.Midi
local Midi = {}

---@param cb fun(names: string[]?, err: string?) The inputs connected now.
function Midi.inputs (cb) end

---Calls `fn` with each message from one input, or from every input connected now when
---`input` is nil. It stops when the plugin stops.
---@param fn fun(message: Proteus.MidiMessage)
---@param input? string
---@return Proteus.MidiListener
function Midi.listen (fn, input) end

---@class Proteus.Timer
local Timer = {}

---Runs `fn` once after `ms` milliseconds. Returns a function that cancels it.
---@param ms number
---@param fn fun()
---@return fun() cancel
function Timer.after (ms, fn) end

---Runs `fn` every `ms` milliseconds. Returns a function that stops it.
---@param ms number
---@param fn fun()
---@return fun() cancel
function Timer.every (ms, fn) end

---@class Proteus.FuzzyMatch
---@field index integer Position of the match in the list that was searched.
---@field score number Higher is better.
---@field html string The item with matched letters wrapped in `<b>`.

---@class Proteus.Util
local Util = {}

---A Lucide icon as an SVG string. See https://lucide.dev/icons for names.
---@param name string Such as `'save'` or `'folder-open'`.
---@param size? integer Pixels. 16 when nil.
---@return string? svg nil for an unknown name
function Util.icon (name, size) end

---@return string[]
function Util.icon_names () end

---@param text string
---@return string html
function Util.markdown (text) end

---Markdown from outside the app, such as a comment on GitHub, as HTML with only plain
---formatting. Scripts, event handlers and styles are gone. A link has no href, so a click
---stays in the app, and its address is in `data-item` as `link:<url>` for the plugin to open.
---@param text string
---@return string html
function Util.safe_markdown (text) end

---Matches a query against a list, best first. An empty query returns everything in order.
---@param query string
---@param items string[]
---@param limit? integer
---@return Proteus.FuzzyMatch[]
function Util.fuzzy (query, items, limit) end

---@param text string
---@return string
function Util.escape (text) end

---Milliseconds since 1970.
---@return number
function Util.now () end

---Language names the code widget can color.
---@return string[]
function Util.code_languages () end

---Adds a language to the code widget, described as data. It goes away when the plugin stops.
---Returns a function that takes it away sooner. Needs the feature `'languages'`.
---@param spec Proteus.LanguageSpec
---@return fun() remove
function Util.language (spec) end

---The language a plugin added for a file's extension, or nil.
---@param path string
---@return string?
function Util.language_for (path) end

---Formats a number for a locale, the way JavaScript's Intl.NumberFormat does.
---@param n number
---@param locale? string Such as `'en-US'` or `'de-DE'`.
---@param options? { style?: 'decimal'|'currency'|'percent', currency?: string, minimumFractionDigits?: integer, maximumFractionDigits?: integer }
---@return string
function Util.format_number (n, locale, options) end

---Language names `app.util.format` can format, such as `'css'`, `'json'` and `'markdown'`.
---@return string[]
function Util.format_languages () end

---Formats code with Prettier, which runs inside the app.
---@param language string
---@param text string
---@param cb fun(formatted: string?, err: string?)
function Util.format (language, text, cb) end

---Formats every `-- lang=<name>` block inside Lua code, such as CSS in a long string.
---Blocks that fail to format stay as they were, and their problems come back in `errors`.
---@param text string
---@param cb fun(result: { text: string, errors: string[] }?, err: string?)
function Util.format_embedded (text, cb) end

---Formats every `-- lang=<name>` block inside Lua code with `fn`, which gets each block's
---language and code and calls `done` with the new code, or with nil to leave it as it is.
---@param text string
---@param fn fun(lang: string, code: string, done: fun(code: string?))
---@param cb fun(result: { text: string, errors: string[] }?, err: string?)
function Util.format_blocks (text, fn, cb) end

---@class Proteus.Window
local Window = {}

---@param title string
function Window.set_title (title) end

---Reloads the whole window into the same profile.
function Window.reload () end

---Opens a profile in a window of its own, or brings that window forward. Saves in any window
---reach the others, and a running plugin reloads when its files change.
---@param profile string
---@param safe? boolean Open it in safe mode.
---@param cb? fun(ok: any, err: string?)
function Window.open (profile, safe, cb) end

function Window.quit () end

---Opens the browser developer tools. Works in debug builds.
function Window.devtools () end

---@class Proteus.System
local System = {}

---@param text string
function System.clipboard (text) end

---@param cb fun(text: string?, err: string?)
function System.clipboard_read (cb) end

---Pastes the clipboard into whatever has focus.
function System.paste () end

---@param url string
---@param cb? fun(ok: any, err: string?)
function System.open_url (url, cb) end

---@param path string
---@param cb? fun(ok: any, err: string?)
function System.open_path (path, cb) end

---Opens the workspace folder in the file manager.
---@param cb? fun(ok: any, err: string?)
function System.reveal_workspace (cb) end

---Shows a file or folder in the system file manager, selected. Needs the desktop app.
---@param path string A workspace path, or a full path on disk.
---@param cb? fun(ok: any, err: string?)
function System.reveal (path, cb) end

---Puts a shortcut on the desktop that opens straight into a profile.
---@param name string
---@param profile string
---@param cb fun(path: string?, err: string?)
function System.create_launcher (name, profile, cb) end

---------------------------------------------------------------------------------------------
-- Kernel
---------------------------------------------------------------------------------------------

---@class Proteus.LaunchInfo
---@field profile? string The profile asked for by flag or URL.
---@field workspace string The workspace folder.
---@field safe boolean
---@field folder? string A project folder to open, from `--folder` or a bare path, with `/`.
---@field started? number When the app started, in milliseconds since 1970. A reload keeps it.
---@field args string[]
---@field platform 'tauri'|'browser'
---@field os string
---@field arch? string Such as `'x86_64'` or `'aarch64'`.
---@field version? string This version of Proteus, such as `'0.2.0'`.
---@field cache? string A folder the app may use for generated files.

---@alias Proteus.PluginStatus
---| 'active' # Running.
---| 'inactive' # Found but not running.
---| 'failed' # Tried to start and failed. See `error`.
---| 'missing' # A profile or plugin asked for it, but there is no such folder.

---@class Proteus.PluginInfo
---@field id string
---@field name string
---@field description string
---@field version string
---@field depends string[]
---@field optional string[]
---@field conflicts string[]
---@field status Proteus.PluginStatus
---@field error? string
---@field in_profile boolean
---@field locked boolean True for the plugins that ship with the app outside `plugins/themes`. Their files cannot change.
---@field required boolean True for a locked plugin that stays on: one the running profile's own list names, or one in `plugins/core` that was not switched on in the app. Any other plugin can be switched on and off.
---@field group? string The group folder, such as `'themes'`.
---@field source Proteus.FileSource|'missing'
---@field path string Its `init.lua`.
---@field trusted boolean True when it ships with the app, or is a workspace edit of one.
---@field permissions string[] What it asks for.
---@field folders string[] Workspace folders it writes in.
---@field requires Proteus.Requires

---@class Proteus.ProfileInfo
---@field id string
---@field name string
---@field description string
---@field source Proteus.FileSource

---@class Proteus.LogEntry
---@field level 'info'|'warn'|'error'
---@field source string The plugin id, or `'kernel'`.
---@field text string
---@field time number Milliseconds since 1970.

---@class Proteus.ServiceInfo
---@field name string
---@field owner string The plugin that provides it.

---The project folder a window works on, and its `.proteus` folder.
---@class Proteus.ProjectLayer
---@field folder? string The open folder, with `/`. Nil when none is open.
---@field dir? string Its `.proteus` folder, with `/`.
---@field loaded boolean True when the `.proteus` files are in use.
---@field trusted boolean True when the user lets this folder's `.proteus` files load.

---@class Proteus.Kernel
---@field launch Proteus.LaunchInfo
---@field perf Proteus.Perf How long each plugin's code takes. A restricted plugin needs `kernel`.
local Kernel = {}

---Every plugin found, running or not.
---@return Proteus.PluginInfo[]
function Kernel.plugins () end

---@param id string
---@return Proteus.PluginInfo?
function Kernel.plugin (id) end

---Ids of running plugins, in the order they started.
---@return string[]
function Kernel.active () end

---Starts a plugin and what it depends on, for this session only.
---@param id string
---@return boolean ok
---@return string? err
function Kernel.activate (id) end

---Stops a plugin and everything that depends on it.
---@param id string
function Kernel.deactivate (id) end

---Stops a plugin and its dependents, reloads its code, and starts them all again.
---@param id string
---@return boolean ok
---@return string? err
function Kernel.reload (id) end

---Looks for plugin folders added since start.
function Kernel.rescan () end

---Switches a plugin on or off in a profile, and keeps the choice. In the running profile it
---also starts or stops the plugin. Another profile keeps the choice for the next time it
---opens. Fails for a builtin profile that is not `extensible`, for a `required` plugin, and
---for a plugin that conflicts with one the profile runs.
---@param id string
---@param on boolean
---@param profile? string A profile's id. The running profile when nil.
---@return boolean ok
---@return string? err
function Kernel.set_enabled (id, on, profile) end

---Reads a plugin's init.lua again and returns the table it returns, without starting it.
---`plugin` gives the copy loaded when the plugin loaded, and this one shows changes saved
---since then.
---@param id string
---@return Proteus.Plugin? manifest
---@return string? err
function Kernel.read_manifest (id) end

---The id of the plugin a file belongs to.
---@param path string
---@return string?
function Kernel.plugin_of (path) end

---The files the user gave a plugin, with their paths.
---@param plugin string
---@return Proteus.FileGrantInfo[]
function Kernel.file_grants (plugin) end

---Takes a file back from a plugin.
---@param plugin string
---@param id string
function Kernel.forget_file_grant (plugin, id) end

---True for files that can never change.
---@param path string
---@return boolean
function Kernel.locked (path) end

---@return Proteus.Profile
function Kernel.profile () end

---@return Proteus.ProfileInfo[]
function Kernel.profiles () end

---Reads a profile's file without running it: its name, plugins and settings. The running
---profile comes from `profile` instead.
---@param id string
---@return Proteus.Profile? profile
---@return string? err
function Kernel.read_profile (id) end

---The plugin ids the running profile asks for, after changes made in the app.
---@return string[]
function Kernel.profile_plugins () end

---Reloads the window into another profile.
---@param id string
function Kernel.switch_profile (id) end

---@param safe? boolean Reload into safe mode, which runs only the core plugins.
function Kernel.reload_window (safe) end

---@return boolean
function Kernel.safe_mode () end

---True when the running profile's plugin list cannot change: a builtin profile that is not
---`extensible`.
---@return boolean
function Kernel.profile_locked () end

---@return string
function Kernel.default_profile () end

---@param id string
function Kernel.set_default_profile (id) end

---The last thousand log lines.
---@return Proteus.LogEntry[]
function Kernel.logs () end

---Every permission a plugin can ask for.
---@return Proteus.PermissionInfo[]
function Kernel.permissions () end

---This version of Proteus, such as `'0.2.0'`.
---@return string
function Kernel.version () end

---The features this version of Proteus has, for `requires.features`.
---@return Proteus.Feature[]
function Kernel.features () end

---What a restricted plugin with this id may name its services, events, commands and
---settings after: the first and the last part of the id, past `proteus.`, less the parts the
---app's own plugins use. Empty when the app uses every part.
---@param id string
---@return string[]
function Kernel.namespaces (id) end

---True when `version` meets every condition in `spec`, such as `'>=0.2.0 <1.0.0'`.
---@param version string
---@param spec string
---@return boolean ok
---@return string? err Why the spec cannot be read.
function Kernel.satisfies (version, spec) end

---@return Proteus.ServiceInfo[]
function Kernel.services () end

---------------------------------------------------------------------------------------------
-- Profiling
---------------------------------------------------------------------------------------------

---The numbers kept for one kind of callback, such as `'timer'`, `'click handler'`,
---`"handler for 'fs:changed'"` or `"command 'file.save'"`. `'load'` is reading the plugin's
---file and running its top level, and `'start'` is its `activate`. Times are in milliseconds.
---@class Proteus.PerfKind
---@field calls integer
---@field self number Time in the plugin's own code: the whole time, less the callbacks of any plugin that ran inside it, such as handlers for an event it sent.
---@field total number The whole time, nested callbacks included.
---@field max number The longest self time of one call.

---What one plugin's callbacks took since counting started.
---@class Proteus.PerfPlugin: Proteus.PerfKind
---@field errors integer Callbacks that raised an error.
---@field load? number How long its code took to load the last time.
---@field start? number How long its `activate` took the last time it started.
---@field kinds table<string, Proteus.PerfKind> The same numbers for each kind of callback.

---@class Proteus.PerfEvent
---@field sent integer How many times it was sent.
---@field ms number How long its listeners took, all together.

---@class Proteus.PerfStats
---@field since number When counting started, in milliseconds since 1970: the app's start, or the last `reset`.
---@field now number
---@field busy number Milliseconds the window spent running plugin code.
---@field plugins table<string, Proteus.PerfPlugin> By plugin id. `'kernel'` holds what the kernel runs for itself.
---@field events table<string, Proteus.PerfEvent> By event name.
---@field lua_kb number Memory the Lua code holds, in kilobytes.
---@field js_kb? number Memory the page's JavaScript holds, in kilobytes, where the browser tells.

---One plugin's share of a task.
---@class Proteus.PerfPart
---@field owner string
---@field what string The kind of callback.
---@field ms number Its self time inside the task.

---A task: a callback the browser started, such as a click or a timer, with everything that ran
---inside it. Only tasks of 4 ms or more are kept, the last 500.
---@class Proteus.PerfTask
---@field seq integer Goes up by one for each task kept.
---@field at number When it ended, in milliseconds since 1970.
---@field ms number
---@field owner string The plugin whose callback started it.
---@field what string
---@field parts Proteus.PerfPart[] Each plugin's self time in it, longest first.

---A stretch of time, numbered so a reader can ask for what came after the last one it saw.
---@class Proteus.PerfMoment
---@field seq integer
---@field at number When it started, in milliseconds since 1970.
---@field ms number

---@class Proteus.PerfSecond
---@field at number The start of the second, in milliseconds since 1970.
---@field frames integer Frames drawn in it.
---@field worst number The longest time between two frames in it.

---@class Proteus.PerfFrames
---@field seconds Proteus.PerfSecond[] The last minute, oldest first.
---@field gaps Proteus.PerfMoment[] Times the page went 50 ms or more without drawing.
---@field long_tasks Proteus.PerfMoment[] Tasks of 50 ms or more, as the browser reports them.
---@field long_task_support boolean False where the browser reports no long tasks, such as on macOS.

---@class Proteus.PerfDom
---@field total integer Elements on the page.
---@field unowned? integer Elements the app's own page holds, outside every plugin.
---@field plugins table<string, { nodes: integer, widgets: integer }> Elements and widgets by plugin id.

---How long each plugin's code takes, kept by the kernel from the moment the app starts. Every
---plugin callback counts: event handlers, timers, clicks, replies and commands. The browser's
---own work, such as laying out the page, shows only in the frames.
---@class Proteus.Perf
local Perf = {}

---A copy of everything counted since the app started or the last `reset`.
---@return Proteus.PerfStats
function Perf.stats () end

---The slow tasks kept after the one numbered `after`, oldest first.
---@param after? integer
---@return Proteus.PerfTask[]
function Perf.tasks (after) end

---Starts counting again. How long each plugin took to load and start stays.
function Perf.reset () end

---How often the page drew in the last minute, and its stalls after the one numbered `after`.
---A call starts watching the frames, which stops a few seconds after the last call. Watching
---keeps the page drawing every frame, so pass false for `watch` to read what is kept without
---it. The browser's long tasks are kept either way.
---@param after? integer
---@param watch? boolean True when nil.
---@return Proteus.PerfFrames
function Perf.frames (after, watch) end

---How many elements and widgets each plugin has on the page now.
---@return Proteus.PerfDom
function Perf.dom () end

---Runs `fn` and counts its time to `owner`, as if a callback of `owner` ran it. A service calls
---it for a function another plugin gave it, such as a command's `run`. Errors pass through.
---@param owner string
---@param what string
---@param fn function
---@param ... any
---@return any ...
function Perf.charge (owner, what, fn, ...) end

---The project folder this window works on, and whether its `.proteus` files are in use.
---@return Proteus.ProjectLayer
function Kernel.project () end

---Says which folder the window works on, once it knows. The kernel remembers it for the
---profile, so the next start mounts that folder's `.proteus` files before any plugin loads.
---When the files in use belong to another folder, or the folder has trusted `.proteus` files
---that are not in use, the window reloads.
---@param folder string|false
function Kernel.set_folder (folder) end

---Remembers the folder for the running profile and reloads the window into it.
---@param folder string|false
function Kernel.open_folder (folder) end

---Lets a folder's `.proteus` files load, or stops them. They can run code, so a folder must
---be trusted first. It takes effect when the window reloads.
---@param folder string
---@param on boolean
function Kernel.trust_folder (folder, on) end

---A throwaway `app` for running scratch code. Calling `dispose()` undoes everything it did.
---@param name? string
---@return Proteus.App app
---@return fun() dispose
function Kernel.sandbox (name) end

---A language for the code widget, as data. It colors like C: `//` and `/* */` comments,
---quoted strings and numbers, plus the words given here.
---@class Proteus.LanguageSpec
---@field name string Lower case, such as `'wgsl'`. A language the app ships cannot be replaced.
---@field keywords? string|string[] Words such as `if` and `return`. A string holds them separated by spaces.
---@field types? string|string[]
---@field builtins? string|string[] Functions the language provides.
---@field atoms? string|string[] Constants such as `true`.
---@field block_keywords? string|string[] Keywords that open a block, for indenting.
---@field directive? '#'|'@'|'$'|'!'|'%' A character that makes the rest of the line preprocessor text.
---@field attribute? '#'|'@'|'$'|'!'|'%' A character that starts an attribute word, such as `@vertex`.
---@field comment? '#'|';'|'//'|'--'|string[] What starts a line comment, such as `'#'`. With it, `/*` no longer opens a C block comment.
---@field extensions? string|string[] File extensions without the dot, such as `'wgsl'`. The editor opens those files in this language.
