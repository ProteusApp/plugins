---@meta

-- Types for every service the builtin plugins provide. Get one with `app.use('<name>')`.

---------------------------------------------------------------------------------------------
-- commands (proteus.core.commands)
---------------------------------------------------------------------------------------------

---A named action. Menus, the toolbar, keys and the palette all read from the same list.
---
---```lua
---app.use('commands').register({
---  id = 'clock.copy', title = 'Copy the Time', category = 'Clock',
---  key = 'ctrl+alt+t', menu = 'Plugins', toolbar = true, icon = 'clock',
---  run = function () end,
---})
---```
---@class Proteus.CommandSpec
---@field id string Unique, such as `'notes.new'`.
---@field title string Shown in menus and the palette.
---@field run fun(...: any)
---@field category? string Shown before the title in the palette, as in `'Notes: New Note'`.
---@field key? string|string[] A shortcut, such as `'ctrl+shift+n'` or `'f5'`.
---@field menu? string The menu bar menu, such as `'File'`, `'Edit'` or `'View'`.
---@field menu_title? string A different title for the menu.
---@field group? string Splits a menu into sections.
---@field order? number Sorts within a menu or the toolbar. Lower comes first.
---@field toolbar? boolean|number Adds a toolbar button. A number sets its position.
---@field toolbar_align? 'left'|'right'
---@field toolbar_text? string Text beside the toolbar icon.
---@field icon? string A Lucide icon name.
---@field when? fun(): boolean The command is hidden or greyed out when this returns false.
---@field hidden? boolean Leaves the command out of the palette.
---@field shared? boolean Lets restricted plugins run it. Without it they run only their own commands.
---@field owner? string Set by the service: the plugin that registered it.
---@field label? string Set by the service: category and title together.
---@field restricted? boolean Set by the service: a restricted plugin registered it. Its `key` comes after other plugins' keys.

---@class Proteus.Commands
local Commands = {}

---Adds a command. It goes away when the plugin stops.
---@param spec Proteus.CommandSpec
---@return Proteus.CommandSpec
function Commands.register (spec) end

---Removes a command this plugin added. Commands also go away when their plugin stops.
---@param id string
function Commands.unregister (id) end

---Runs a command. Returns false when it does not exist, cannot run now, or fails.
---@param id string
---@param ... any
---@return boolean
function Commands.run (id, ...) end

---@param id string
---@return Proteus.CommandSpec?
function Commands.get (id) end

---@param id string
---@return boolean
function Commands.can_run (id) end

---@return Proteus.CommandSpec[]
function Commands.list () end

---@param fn fun()
---@return fun() off
function Commands.on_change (fn) end

---------------------------------------------------------------------------------------------
-- keys (proteus.core.keys)
---------------------------------------------------------------------------------------------

---@class Proteus.KeyBinding
---@field combo string Such as `'ctrl+s'`.
---@field label string Such as `'Ctrl+S'`.
---@field command string

---@class Proteus.Keys
local Keys = {}

---Binds a key combo to a command. Most plugins set `key` on the command instead.
---@param combo string Such as `'ctrl+shift+x'`.
---@param command_id string
function Keys.bind (combo, command_id) end

---The display label of the shortest key bound to a command, such as `'Ctrl+S'`.
---@param command_id string
---@return string?
function Keys.label (command_id) end

---@param combo string
---@return string
function Keys.normalize (combo) end

---@param combo string
---@return string
function Keys.pretty (combo) end

---@return Proteus.KeyBinding[]
function Keys.list () end

---------------------------------------------------------------------------------------------
-- settings (proteus.core.settings)
---------------------------------------------------------------------------------------------

---@alias Proteus.SettingType 'boolean'|'number'|'string'|'select'|'json'|'table'

---@class Proteus.SettingSpec
---@field title? string
---@field type? Proteus.SettingType Taken from `default` when nil.
---@field default? any
---@field description? string
---@field options? string[]|fun(): string[] The choices for a `'select'` setting.
---@field sensitive? boolean True for a setting that names a program to run, or where code comes from. Only the user's choice and the default count for it, never a profile's or a folder's value.
---@field key? string Set by the service.
---@field owner? string Set by the service.

---Options with defaults, saved per profile. A value comes from the open folder's
---`.proteus/settings.json`, then the user's choice, then the profile's `settings`, then the
---default. A `sensitive` setting skips the folder and the profile.
---@class Proteus.Settings
local Settings = {}

---Declares a setting and returns its current value.
---@param key string Such as `'notes.font_size'`.
---@param spec Proteus.SettingSpec
---@return any
function Settings.define (key, spec) end

---@param key string
---@return any
function Settings.get (key) end

---Sets a value. A key the open folder's `.proteus/settings.json` sets is saved there, and
---any other key is saved as the user's choice.
---@param key string
---@param value any
function Settings.set (key, value) end

---Forgets the value that wins, the folder's or else the user's, so the next one applies.
---@param key string
function Settings.reset (key) end

---True when the open folder or the user sets the key.
---@param key string
---@return boolean
function Settings.is_set (key) end

---Where the key's value comes from.
---@param key string
---@return 'project'|'user'|'profile'|'default'
function Settings.source (key) end

---Calls `fn(value)` now, and again each time the setting changes.
---@param key string
---@param fn fun(value: any)
---@return fun() off
function Settings.watch (key, fn) end

---@return Proteus.SettingSpec[]
function Settings.all () end

---The file the user's choices are saved in.
---@return string
function Settings.path () end

---The open folder's `.proteus/settings.json` on disk, when it has one in use.
---@return string?
function Settings.project_file () end

---------------------------------------------------------------------------------------------
-- themes (proteus.core.themes)
---------------------------------------------------------------------------------------------

---@class Proteus.ThemeSpec
---@field id string
---@field name? string
---@field dark? boolean
---@field vars? table<string, string> CSS variables without the leading `--`, such as `{ bg = '#000' }`.
---@field css? string Extra CSS applied with the theme.

---@class Proteus.Themes
local Themes = {}

---A restricted plugin cannot replace a theme another plugin registered.
---@param spec Proteus.ThemeSpec
function Themes.register (spec) end

---Removes a theme. Themes also go away when their plugin stops. A restricted plugin removes
---only its own.
---@param id string
function Themes.unregister (id) end

---Shows a theme now without saving the choice. A restricted plugin cannot: the user picks.
---@param id string
---@return boolean
function Themes.apply (id) end

---Shows a theme and saves the choice. A restricted plugin cannot: the user picks.
---@param id string
function Themes.choose (id) end

---@return string?
function Themes.current () end

---@return Proteus.ThemeSpec[]
function Themes.list () end

---Every theme variable with its default value.
---@return table<string, string>
function Themes.defaults () end

---------------------------------------------------------------------------------------------
-- icons (proteus.core.icons)
---------------------------------------------------------------------------------------------

---How a file or a folder looks: a Lucide icon, or a badge of up to three letters.
---@class Proteus.FileIcon
---@field icon? string A Lucide icon name, such as `'file-code'`.
---@field text? string A badge's letters, such as `'TS'`, shown when there is no `icon`.
---@field color? string Any CSS color, such as `'#dea584'` or `'var(--syn-keyword)'`.
---@field open? string For a folder: the Lucide icon while it is open.

---The value of an association of the kind `'icon'` in proteus.core.files.
---@class Proteus.IconAssociation: Proteus.FileIcon
---@field pack? string The pack it belongs to. Without one, it counts in every pack, after the pack's own.
---@field folder? boolean True when the pattern names folders, not files.

---@class Proteus.IconPackSpec
---@field id string
---@field name? string
---@field description? string
---@field file? Proteus.FileIcon The icon of a file nothing else fits.
---@field folder? Proteus.FileIcon The icon of a folder nothing else fits, with `open`.

---@class Proteus.IconPack: Proteus.IconPackSpec
---@field name string
---@field owner string The plugin that registered it.

---File icon packs. A pack plugin registers the pack, then adds associations of the kind
---`'icon'` through proteus.core.files, each with `pack` set to the pack's id. The setting `icon_pack`
---picks one, and `'default'` keeps the icons each plugin draws.
---
---```lua
---app.use('icons').register({ id = 'vivid', name = 'Vivid' })
---app.use('files').associate({
---  kind = 'icon', pattern = '*.rs', value = { pack = 'vivid', icon = 'cog', color = '#dea584' },
---})
---```
---@class Proteus.Icons
local Icons = {}

---Adds a pack. It goes away when its plugin stops.
---@param spec Proteus.IconPackSpec
function Icons.register (spec) end

---Removes a pack. A restricted plugin removes only its own.
---@param id string
function Icons.unregister (id) end

---Shows a pack now without saving the choice. False when no such pack is registered.
---@param id string
---@return boolean
function Icons.apply (id) end

---Shows a pack and saves the choice.
---@param id string
function Icons.choose (id) end

---The id of the pack in use, or `'default'`.
---@return string
function Icons.current () end

---@return Proteus.IconPack[]
function Icons.list () end

---The icon for a file, or nil when the plugin asking should draw its own.
---@param path string
---@return Proteus.FileIcon?
function Icons.file (path) end

---The icon for a folder, or nil when the plugin asking should draw its own.
---@param path string
---@param open? boolean
---@return Proteus.FileIcon?
function Icons.folder (path, open) end

---------------------------------------------------------------------------------------------
-- menus (proteus.ui.menus)
---------------------------------------------------------------------------------------------

---@class Proteus.MenuItem
---@field label? string
---@field run? fun()
---@field key? string A shortcut shown beside the label. It does not bind anything.
---@field icon? string
---@field disabled? boolean
---@field danger? boolean Shows the item in red.
---@field separator? boolean A line between groups. Other fields are ignored.

---@class Proteus.PopupOptions
---@field owner? Proteus.El Clicks inside this element do not close the menu.
---@field on_close? fun()
---@field on_key? fun(ev: Proteus.DomEvent): Proteus.EventResult

---@class Proteus.Menus
local Menus = {}

---Opens a menu at a point on screen.
---@param items Proteus.MenuItem[]
---@param x number
---@param y number
---@param opts? Proteus.PopupOptions
---@return Proteus.El?
function Menus.popup (items, x, y, opts) end

function Menus.close () end

---Undo, Cut, Copy, Paste and Select All, for a right-click on text.
---@param ev Proteus.DomEvent
---@return Proteus.MenuItem[]
function Menus.edit_items (ev) end

---Adds items to the right-click menu for `el` and everything inside it. Return nil to let the
---next element out answer instead. Returns a function that removes the menu.
---@param el Proteus.El
---@param fn fun(ev: Proteus.DomEvent): Proteus.MenuItem[]?
---@return fun() detach
function Menus.attach (el, fn) end

---------------------------------------------------------------------------------------------
-- shell (proteus.ui.shell)
---------------------------------------------------------------------------------------------

---@alias Proteus.ShellRegion
---| 'menubar' # The strip along the top.
---| 'toolbar' # Under the menu bar.
---| 'left_bar' # A thin strip at the left edge, outside the left dock. Empty takes no room.
---| 'left' # The left dock.
---| 'main' # The middle of the window.
---| 'right' # The right dock.
---| 'right_bar' # A thin strip at the right edge, outside the right dock. Empty takes no room.
---| 'bottom' # Under the main area.
---| 'status' # The strip along the bottom.
---| 'overlay' # Floats above everything.

---@alias Proteus.Dock 'left'|'right'|'bottom'

---@class Proteus.MountOptions
---@field order? number Lower comes first.

---The window layout.
---@class Proteus.Shell
local Shell = {}

---@param name Proteus.ShellRegion
---@return Proteus.El
function Shell.region (name) end

---Adds an element to a region. It goes away when the plugin stops.
---@param name Proteus.ShellRegion
---@param el Proteus.El
---@param opts? Proteus.MountOptions
---@return Proteus.El
function Shell.mount (name, el, opts) end

---@param dock Proteus.Dock
---@param on boolean
function Shell.set_visible (dock, on) end

---@param dock Proteus.Dock
---@return boolean
function Shell.is_visible (dock) end

---@param dock Proteus.Dock
function Shell.toggle (dock) end

---Folds the bottom dock down to its tab strip, or opens it again. Side docks do not fold.
---@param dock Proteus.Dock
---@param on boolean
function Shell.set_collapsed (dock, on) end

---@param dock Proteus.Dock
---@return boolean
function Shell.is_collapsed (dock) end

---------------------------------------------------------------------------------------------
-- views (proteus.ui.views)
---------------------------------------------------------------------------------------------

---@class Proteus.ViewSpec
---@field id string
---@field title? string
---@field icon? string
---@field content Proteus.El
---@field order? number
---@field key? string A shortcut that shows the view.
---@field on_show? fun()
---@field shared? boolean Lets restricted plugins show and toggle it, and run its command. Without it they show and toggle only their own views.

---@class Proteus.View
---@field id string
---@field title string
---@field dock Proteus.Dock
---@field remove fun() Takes the panel away now instead of when the plugin stops.

---A floating window on the desktop, from `windows.add`.
---@class Proteus.WindowSpec
---@field id string Unique, such as the plugin's id: `'beats.mixer'`. A restricted plugin starts it with one of its own names.
---@field title string
---@field icon? string A Lucide icon name, for the title bar and the toolbar.
---@field content Proteus.El
---@field key? string A key that shows or hides it, such as `'f9'`.
---@field category? string The category of its show-or-hide command. `'Windows'` when nil.
---@field order? number Its place among the toolbar's window buttons. 50 when nil.
---@field open? boolean Open the first time, before the user moved anything.
---@field x? number Where it first sits, in pixels, or as a share of the desktop from 0 to 1.
---@field y? number
---@field w? number
---@field h? number
---@field z? number Its first place in the stack, higher in front.
---@field min_w? number
---@field min_h? number
---@field on_show? fun() Called each time it opens, such as to draw what changed while it was closed.
---@field shared? boolean Lets restricted plugins show, hide and toggle it. Without it they reach only their own windows.

---Floating windows on a desktop in the middle of the window, in the manner of FL Studio.
---A window goes away when the plugin that added it stops. `windows:changed (id, open)` fires
---when one opens or closes.
---@class Proteus.Windows
local Windows = {}

---Adds a window, or replaces one with the same id. A restricted plugin cannot replace another
---plugin's window, and the command that shows or hides its window is its own, such as
---`beats.toggle.beats_mixer`.
---@param spec Proteus.WindowSpec
function Windows.add (spec) end

---Opens a window and brings it to the front. A restricted plugin opens its own windows and
---those marked `shared`, and so it is for `hide` and `toggle`.
---@param id string
function Windows.show (id) end

---@param id string
function Windows.hide (id) end

---@param id string
function Windows.toggle (id) end

---@param id string
---@return boolean
function Windows.is_open (id) end

---A restricted plugin renames only its own windows.
---@param id string
---@param title string
function Windows.set_title (id, title) end

---Switchable panels in the docks.
---@class Proteus.Views
local Views = {}

---Adds a panel. It goes away when the plugin stops. A restricted plugin cannot use the id of
---another plugin's view, and the command that shows its view is its own, such as
---`rust.show.cargo`. A builtin plugin's view with the id of a restricted plugin's view takes
---that view away.
---@param dock Proteus.Dock
---@param spec Proteus.ViewSpec
---@return Proteus.View
function Views.add (dock, spec) end

---Shows a view. Returns false when there is none with that id. A restricted plugin shows its
---own views and those marked `shared`, and returns false for any other.
---@param id string
---@return boolean
function Views.show (id) end

---Shows the view, or hides its dock when the view already shows. A restricted plugin toggles
---its own views and those marked `shared`.
---@param id string
function Views.toggle (id) end

---@param dock Proteus.Dock
---@return { id: string, title: string }[]
function Views.list (dock) end

---Adds a section under a view's content, with a heading that folds it, such as a panel about
---the file in front under the Explorer. It goes away when the plugin stops. Returns nil when
---there is no view with that id. A restricted plugin adds sections only to its own views.
---@param view_id string Such as `'explorer'`.
---@param spec Proteus.ViewSectionSpec
---@return Proteus.ViewSection?
function Views.add_section (view_id, spec) end

---@class Proteus.ViewSectionSpec
---@field id string Keeps its folded state across restarts.
---@field title? string
---@field icon? string
---@field content Proteus.El
---@field actions? Proteus.El[] Small buttons at the right of the heading.
---@field open? boolean Unfolded the first time. True when nil.

---@class Proteus.ViewSection
---@field show fun(on: boolean) Shows or hides the whole section.
---@field set_title fun(text: string)
---@field open fun() Unfolds it.
---@field remove fun() Takes it away now instead of when the plugin stops.

---------------------------------------------------------------------------------------------
-- tabs (proteus.ui.tabs)
---------------------------------------------------------------------------------------------

---@class Proteus.TabSpec
---@field id string Opening an id that is open already switches to it. A builtin plugin that opens the id of a restricted plugin's tab closes that tab first.
---@field title? string
---@field tooltip? string
---@field icon? string|Proteus.FileIcon A Lucide icon name, or a file icon from proteus.core.icons.
---@field content Proteus.El
---@field closable? boolean True when nil.
---@field background? boolean Opens without switching to it.
---@field data? table Anything the owner wants to keep with the tab.
---@field on_close? fun(): boolean? Return false to keep the tab open.
---@field on_focus? fun()

---@class Proteus.Tab
---@field id string
---@field content Proteus.El
---@field data? table
---@field set_title fun(text: string)
---@field set_tooltip fun(text: string)
---@field set_icon fun(icon?: string|Proteus.FileIcon) Changes the icon, or takes it away.
---@field set_dirty fun(on: boolean) Shows a dot for unsaved changes.
---@field is_dirty fun(): boolean
---@field set_preview fun(on: boolean) Shows the title in italics.
---@field close fun(force?: boolean): boolean
---@field focus fun()
---@field is_active fun(): boolean
---@field set_id fun(id: string) Gives the tab a new id, such as after its file moves.

---Tabbed documents in the main area.
---@class Proteus.Tabs
local Tabs = {}

---@param spec Proteus.TabSpec
---@return Proteus.Tab
function Tabs.open (spec) end

---A restricted plugin gets only its own tabs, and a builtin plugin never gets a restricted
---plugin's tab from it.
---@param id string
---@return Proteus.Tab?
function Tabs.get (id) end

---@return Proteus.Tab?
function Tabs.active () end

---@return Proteus.Tab[]
function Tabs.list () end

---A restricted plugin switches only to its own tabs.
---@param id string
function Tabs.focus (id) end

---A restricted plugin closes only its own tabs.
---@param id string
---@param force? boolean Skips the tab's `on_close`.
---@return boolean closed
function Tabs.close (id, force) end

---@param fn fun(active_id: string?)
---@return fun() off
function Tabs.on_change (fn) end

---Shows `el` in the main area while no tab is open, in place of the usual hint, and hides the
---tab strip meanwhile. A start page uses it. The last one set wins, but a restricted plugin
---never takes the place of another plugin's. Returns a function that takes it away, which
---also happens when the plugin stops.
---@param el Proteus.El
---@return fun() remove
function Tabs.set_empty (el) end

---------------------------------------------------------------------------------------------
-- picker (proteus.ui.palette)
---------------------------------------------------------------------------------------------

---@class Proteus.PickItem
---@field label string
---@field detail? string Grey text after the label.
---@field hint? string Text on the right, such as a shortcut.
---@field icon? string
---@field value? any
---@field search? string Text to match against instead of the label and detail.

---@class Proteus.PickOptions
---@field items Proteus.PickItem[]
---@field placeholder? string
---@field prompt? string A line above the input.
---@field value? string The starting query.
---@field empty? string Shown when nothing matches.
---@field on_pick? fun(item: Proteus.PickItem)
---@field on_highlight? fun(item: Proteus.PickItem) Runs as the arrow keys move.
---@field on_cancel? fun()

---@class Proteus.InputOptions
---@field prompt? string
---@field value? string
---@field placeholder? string
---@field select? boolean Selects the starting text. True when nil.
---@field validate? fun(text: string): string? Return a message to refuse the text.
---@field on_submit? fun(text: string)
---@field on_cancel? fun()

---@class Proteus.ConfirmOptions
---@field message string
---@field yes? string The label of the yes button.
---@field no? string
---@field on_yes? fun()
---@field on_no? fun()

---Pick lists, text prompts and yes-or-no questions, in the palette box.
---@class Proteus.Picker
local Picker = {}

---@param opts Proteus.PickOptions
function Picker.pick (opts) end

---@param opts Proteus.InputOptions
function Picker.input (opts) end

---@param opts Proteus.ConfirmOptions
function Picker.confirm (opts) end

function Picker.close () end

---------------------------------------------------------------------------------------------
-- overlays (proteus.ui.overlays)
---------------------------------------------------------------------------------------------

---@class Proteus.OverlayOptions
---@field dim? boolean Dims the window behind the box. True when nil.
---@field dismiss? boolean Escape and a click on the backdrop close the box. True when nil.
---@field focus? Proteus.El Gets the focus when the box opens. The backdrop gets it when nil.
---@field on_close? fun() Runs once the box has closed, whatever closed it.

---A button along the bottom of a modal.
---@class Proteus.ModalButton
---@field label string
---@field variant? 'primary'|'ghost'|'danger' A primary button gets the focus when the modal opens.
---@field icon? string A Lucide icon name.
---@field run? fun(): boolean? Runs on a click. The modal closes afterwards unless it returns false.

---@class Proteus.ModalOptions
---@field title? string The heading. The X button needs one.
---@field body? Proteus.Child What the modal shows: an element, text, or a list of them.
---@field buttons? Proteus.ModalButton[] Along the bottom, left to right.
---@field width? number|string Pixels, or any CSS width. 440 pixels when nil.
---@field dismiss? boolean Escape, a click on the backdrop and the X button close the modal. True when nil.
---@field focus? Proteus.El Gets the focus when the modal opens. The primary button gets it when nil.
---@field on_close? fun() Runs once the modal has closed, whatever closed it.

---A box on screen.
---@class Proteus.Overlay
---@field el Proteus.El The element that floats.
---@field close fun() Takes the box down. Does nothing once it is closed.
---@field is_open fun(): boolean

---@class Proteus.Modal: Proteus.Overlay
---@field body Proteus.El The middle of the modal. Change its children to change what it shows.

---Modals and other boxes that float above the window. The boxes a plugin opened close when
---that plugin stops.
---
---```lua
---app.use('overlays').modal({
---  title = 'Delete board?',
---  body = 'Its cards go too.',
---  buttons = { { label = 'Cancel' }, { label = 'Delete', variant = 'danger', run = delete } },
---})
---```
---@class Proteus.Overlays
local Overlays = {}

---Opens a modal with a title, content and buttons.
---@param opts Proteus.ModalOptions
---@return Proteus.Modal
function Overlays.modal (opts) end

---Floats any element in the middle of the window, over a backdrop.
---@param el Proteus.El
---@param opts? Proteus.OverlayOptions
---@return Proteus.Overlay
function Overlays.open (el, opts) end

---------------------------------------------------------------------------------------------
-- notify (proteus.ui.notify)
---------------------------------------------------------------------------------------------

---@class Proteus.NotifyOptions
---@field timeout? number Milliseconds. 0 keeps the message until it is closed.
---@field action? { label: string, run: fun() } A button on the message.

---Pop-up messages in the corner. Each function returns one that closes the message.
---@class Proteus.Notify
---@field info fun(text: string, opts?: Proteus.NotifyOptions): fun()
---@field success fun(text: string, opts?: Proteus.NotifyOptions): fun()
---@field warn fun(text: string, opts?: Proteus.NotifyOptions): fun()
---@field error fun(text: string, opts?: Proteus.NotifyOptions): fun()

---------------------------------------------------------------------------------------------
-- toolbar (proteus.ui.toolbar) and status (proteus.ui.statusbar)
---------------------------------------------------------------------------------------------

---@class Proteus.ToolbarOptions
---@field align? 'left'|'right'
---@field order? number

---@class Proteus.Toolbar
local Toolbar = {}

---Puts any element on the toolbar. Commands with `toolbar = true` get a button without this.
---@param el Proteus.El
---@param opts? Proteus.ToolbarOptions
---@return Proteus.El
function Toolbar.add (el, opts) end

---@class Proteus.StatusSpec
---@field id? string
---@field text? string
---@field icon? string
---@field tooltip? string
---@field align? 'left'|'right'
---@field order? number
---@field command? string A command to run on click.
---@field run? fun() A function to run on click.

---@class Proteus.StatusItem
---@field set fun(text: string)
---@field set_tooltip fun(text: string?)
---@field set_icon fun(name: string?)
---@field show fun(on: boolean)
---@field accent fun(on: boolean) Shows the text in the accent color.
---@field remove fun()

---@class Proteus.Status
local Status = {}

---@param spec Proteus.StatusSpec
---@return Proteus.StatusItem
function Status.add (spec) end

---------------------------------------------------------------------------------------------
-- editor (proteus.editor.core)
---------------------------------------------------------------------------------------------

---@class Proteus.OpenOptions
---@field line? integer From 1.
---@field col? integer From 1.
---@field as_text? boolean Opens the file as text even when another plugin has its own opener for it.
---@field keep_focus? boolean Shows the file without moving the keyboard focus into the editor.

---The document in the active editor tab.
---@class Proteus.CurrentDoc
---@field path string
---@field external boolean True for a file outside the workspace.
---@field language string
---@field dirty boolean
---@field text fun(): string
---@field selection fun(): string
---@field insert fun(text: string)
---@field save fun(cb?: fun())
---@field replace fun(text: string) Replaces the whole text as one edit that can be undone.
---@field viewport fun(): { first: integer, last: integer }? The first and last lines on screen, from 1. Nil while the editor is out of sight.
---@field scroll_to fun(line: integer) Scrolls so the line, from 1, sits at the top. The cursor and the focus stay put.
---@field selections fun(): { first: integer, last: integer }[] The lines each selection covers, from 1. A bare cursor selects none.

---Where a side sits.
---@class Proteus.EditorSidePlace
---@field side? 'left'|'right' The edge it sits at. `'right'` when nil.
---@field width? number Its width in pixels. 120 when nil.
---@field over? boolean Lies over the text, clear of the line numbers and the scroll bar, instead of taking room beside it.

---@class Proteus.EditorSideSpec: Proteus.EditorSidePlace
---@field content Proteus.El

---@class Proteus.EditorSide
---@field set fun(place: Proteus.EditorSidePlace) Moves it, or changes its width. Fields left out stay as they were.
---@field remove fun() Takes it away now instead of when the plugin stops.

---A document open in an editor tab, as language plugins see it.
---@class Proteus.DocInfo
---@field path string A workspace path, or a full path for a file outside the workspace.
---@field external boolean
---@field language string
---@field readonly boolean
---@field version fun(): integer Goes up by one with every edit.
---@field text fun(): string
---@field dirty fun(): boolean True while the document has unsaved edits.

---Builds the help a language plugin gives one document, or nil to give none.
---@alias Proteus.ProviderFactory fun(doc: Proteus.DocInfo): Proteus.CodeProvider?

---@class Proteus.Editor
local Editor = {}

---Opens a workspace file in a tab, as text. `open_file` lets other plugins open it first.
---@param path string
---@param opts? Proteus.OpenOptions
function Editor.open (path, opts) end

---Opens a file the way `file:open` does: a plugin that opens some files its own way, such
---as Nodal for a graph, comes first. A restricted plugin cannot send `file:open`, so it calls
---this instead.
---@param path string
---@param opts? Proteus.OpenOptions
function Editor.open_file (path, opts) end

---Opens a file anywhere on disk by its full path.
---@param path string
---@param opts? Proteus.OpenOptions
function Editor.open_external (path, opts) end

---Tells the editor that files on disk changed, as `disk:changed` does. Open files among them
---read their text again, unless they have unsaved edits. `ev.overflow` means too much changed
---to list, and every open file on disk is read again.
---@param changes Proteus.DirChange[]?
---@param ev? Proteus.DirEvent
function Editor.disk_changed (changes, ev) end

---Tells the editor that a file or folder on disk moved, as `disk:renamed` does. Open files at
---`from`, or inside it, follow it to `to`.
---@param from string A full path.
---@param to string A full path.
function Editor.disk_renamed (from, to) end

---A bare code editor to put anywhere.
---@param opts? Proteus.CodeOptions
---@return Proteus.El
function Editor.create (opts) end

---Saves the active document.
function Editor.save () end

---@return Proteus.CurrentDoc?
function Editor.current () end

---Adds words to autocomplete in Lua files.
---@param words string[]
function Editor.add_completions (words) end

---Every open document.
---@return Proteus.DocInfo[]
function Editor.docs () end

---Gives every document in `language` smarter help, such as from a language server. Open
---documents get it at once. Returns a function that takes it away again, which also happens
---when the plugin stops.
---@param language string Such as `'lua'`.
---@param factory Proteus.ProviderFactory
---@return fun() remove
function Editor.set_provider (language, factory) end

---Lets a plugin open some files its own way, such as a graph file in a canvas. The
---function returns true when it opened the file, and false to leave it to the editor.
---Returns a function that removes the opener.
---@param fn fun(path: string, opts: Proteus.OpenOptions?): boolean
---@return fun() remove
function Editor.add_opener (fn) end

---Puts an element at the side of the editor in front, beside the text or over it. The editor
---moves it into whichever document comes to the front, and takes it off screen while no
---document is in front. It goes away when the plugin stops.
---@param spec Proteus.EditorSideSpec
---@return Proteus.EditorSide
function Editor.add_side (spec) end

---Adds a formatter for a language. Format Document runs every formatter for the file's
---language in turn, and so does each save while the `editor.format_on_save` setting is on.
---Call `done(new_text)` with the result, or `done()` to leave the text as it is.
---Returns a function that removes the formatter.
---@param language string
---@param fn fun(doc: Proteus.DocInfo, text: string, done: fun(text: string?))
---@return fun() remove
function Editor.add_formatter (language, fn) end

---Runs before each save. Call `done(new_text)` to save different text, such as formatted
---code, or `done()` to save it as it is. Returns a function that removes the hook.
---@param fn fun(doc: Proteus.DocInfo, text: string, done: fun(text: string?))
---@return fun() off
function Editor.on_before_save (fn) end

---------------------------------------------------------------------------------------------
-- console (proteus.dev.console)
---------------------------------------------------------------------------------------------

---@class Proteus.Console
local Console = {}

---Runs Lua at the Console prompt and prints the result.
---@param code string
function Console.run (code) end

---@param value any
---@param level? 'info'|'warn'|'error'|'result'
function Console.print (value, level) end

---Turns any value into readable text, tables included.
---@param value any
---@return string
function Console.inspect (value) end

function Console.clear () end

---------------------------------------------------------------------------------------------
-- tools (proteus.tools.registry)
---------------------------------------------------------------------------------------------

---@alias Proteus.ToolState
---| 'running' # A server that is up.
---| 'starting' # A server on its way up.
---| 'ready' # A command-line tool that is installed.
---| 'stopped' # A server that is not running.
---| 'missing' # Not installed.
---| 'error' # Failed. See the log.

---@class Proteus.ToolSpec
---@field id string Such as `'luals'`.
---@field name string Such as `'Lua Language Server'`.
---@field description? string
---@field program string The executable name or path.
---@field kind 'server'|'command' A server keeps running. A command runs once per job.
---@field install? string How to install it, shown when it is missing.
---@field homepage? string
---@field start? fun() For servers.
---@field stop? fun() For servers.
---@field check? fun() Looks for the tool again, for example after it was installed.
---@field settings? string[] Setting keys that belong to this tool, shown beside it.
---@field release? Proteus.ToolRelease An official download, for when the program is not on the PATH.

---An official release of a tool, pinned by checksums, which `proteus.tools.registry` can download.
---@class Proteus.ToolRelease
---@field version string Such as `'0.10.0'`.
---@field from string Who publishes it, shown when asking, such as `'github.com/tamasfe/taplo'`.
---@field assets table<string, Proteus.ToolAsset> By platform, such as `'windows-x86_64'`, `'linux-aarch64'` or `'macos-aarch64'`.

---One platform's file in a release.
---@class Proteus.ToolAsset
---@field url string An https address.
---@field sha256 string The file's SHA-256 checksum, in hex.
---@field file? string The program's name inside a `.zip`. A `.gz` holds the program alone.

---@class Proteus.ToolInfo: Proteus.ToolSpec
---@field state Proteus.ToolState
---@field version? string
---@field path? string Where the executable was found.
---@field detail? string A short note on the state, such as an error.

---@class Proteus.ToolLogLine
---@field time number
---@field stream 'out'|'err'|'info'|'send'|'recv'
---@field text string

---A shared list of external tools, their state and their logs.
---@class Proteus.Tools
local Tools = {}

---Adds a tool. It goes away when the plugin stops. Returns a handle for updating it.
---@param spec Proteus.ToolSpec
---@return Proteus.ToolHandle
function Tools.register (spec) end

---@param id string
---@return Proteus.ToolInfo?
function Tools.get (id) end

---@return Proteus.ToolInfo[]
function Tools.list () end

---@param id string
---@return Proteus.ToolLogLine[]
function Tools.log (id) end

---@param id string
function Tools.clear_log (id) end

---A folder on disk holding the builtin plugins, types and tool settings, for tools that need
---real files. It is written once and shared by every tool.
---@param cb fun(folder: string?, err: string?)
function Tools.builtin_dir (cb) end

---@class Proteus.ToolHandle
---@field set_state fun(state: Proteus.ToolState, detail?: string)
---@field set_version fun(version: string?)
---@field set_path fun(path: string?)
---@field log fun(stream: 'out'|'err'|'info'|'send'|'recv', text: string)
---@field locate fun(cb: fun(path: string?)) Finds the program on the PATH, then among downloads. When neither has it, it offers the download and gives nil.
---@field cached fun(cb: fun(path: string?)) The downloaded copy of the release, if there is one.
---@field offer fun() Offers the release's download, once. Useful when the copy on the PATH does not run.

---------------------------------------------------------------------------------------------
-- diagnostics (proteus.tools.diagnostics)
---------------------------------------------------------------------------------------------

---Problems in files, gathered from every linter and language server.
---@class Proteus.Diagnostics
local Diagnostics = {}

---Replaces one source's problems for a file. An empty list clears them.
---@param source string Such as `'selene'`.
---@param path string A workspace path, or a full path for a file outside it.
---@param list Proteus.Diagnostic[]
function Diagnostics.set (source, path, list) end

---Every source's problems for a file.
---@param path string
---@return Proteus.Diagnostic[]
function Diagnostics.get (path) end

---Paths that have problems, each with its list.
---@return { path: string, items: Proteus.Diagnostic[] }[]
function Diagnostics.all () end

---@return { errors: integer, warnings: integer }
function Diagnostics.counts () end

---------------------------------------------------------------------------------------------
-- lsp (proteus.lang.luals)
---------------------------------------------------------------------------------------------

---The running Lua language server.
---@class Proteus.Lsp
local Lsp = {}

---@return boolean
function Lsp.running () end

---Sends a request and calls `cb(result, err)` with the answer.
---@param method string Such as `'textDocument/hover'`.
---@param params table
---@param cb fun(result: any, err: table?)
function Lsp.request (method, params, cb) end

---@param method string
---@param params table
function Lsp.notify (method, params) end

---The `file:///` address the server uses for a workspace path.
---@param path string
---@return string?
function Lsp.uri (path) end

---------------------------------------------------------------------------------------------
-- discord (proteus.discord.rpc)
---------------------------------------------------------------------------------------------

---What Discord shows under the user's name. Every field is optional. Text can hold words in
---braces, such as `'On branch {branch}'`, filled in from `vars`.
---@class Proteus.DiscordPresence
---@field details? string The first line, such as what the user is doing.
---@field state? string The second line.
---@field start? integer When it began, in seconds, such as `os.time ()`. Discord counts up from it.
---@field finish? integer When it ends, in seconds. Discord counts down to it.
---@field large_image? string An art asset name from the Discord application, or an image URL.
---@field large_text? string Shown when the pointer rests on the large image.
---@field small_image? string An art asset name, or an image URL.
---@field small_text? string Shown when the pointer rests on the small image.
---@field buttons? Proteus.DiscordButton[] Up to two links.

---@class Proteus.DiscordButton
---@field label string
---@field url string

---Shows what the user is doing on their Discord profile, when they switch it on. Each plugin
---gets its own handle, and what it set goes away when it stops.
---@class Proteus.Discord
local Discord = {}

---Lays this presence over the app's own lines. Fields left out keep the app's text. The
---plugin that set one most recently wins.
---@param presence Proteus.DiscordPresence
function Discord.set (presence) end

---Takes this plugin's presence away, so the app's own lines show again.
function Discord.clear () end

---Fills words in the app's lines and in presences, such as `{ branch = 'main' }` for
---`'On branch {branch}'`. A line whose words are not all known is skipped. `false` removes a
---word.
---@param vars table<string, string|number|false>
function Discord.vars (vars) end

---True while Discord is listening.
---@return boolean
function Discord.connected () end

---------------------------------------------------------------------------------------------
-- files (proteus.core.files)
---------------------------------------------------------------------------------------------

---Ties a kind of file to a value, such as a JSON schema.
---@class Proteus.FileAssociation
---@field kind string Such as `'schema'`. The plugins that handle a kind decide what its values mean.
---@field pattern string Which files: `'Cargo.toml'` matches the name anywhere, `'*.ndg'` any name that fits, and `'.cargo/config.toml'` the end of a path. `**` crosses folders.
---@field value any For `'schema'`, a JSON schema's address. For `'completion'`, a function `(doc, pos, respond)` that answers `respond ({ items = ..., from = column })` with more completion, which language plugins built on `lsp.client` show. For `'icon'`, a `Proteus.IconAssociation`, which proteus.core.icons shows.
---@field owner? string Set by the service: the plugin that added it.

---The file association system. Any plugin adds associations, and the plugins that handle
---their kind hear about each one. Everything a plugin adds goes away when it stops.
---
---```lua
---app.use('files').associate({
---  kind = 'schema', pattern = 'Cargo.toml', value = 'https://www.schemastore.org/cargo.json',
---})
---```
---@class Proteus.Files
local Files = {}

---Adds an association. Returns a function that takes it away.
---@param association Proteus.FileAssociation
---@return fun() remove
function Files.associate (association) end

---Calls `fn` with every association of `kind` now, and again after each change. Returns a
---function that stops it.
---@param kind string
---@param fn fun(list: Proteus.FileAssociation[])
---@return fun() off
function Files.handle (kind, fn) end

---Every association of a kind, oldest first.
---@param kind string
---@return Proteus.FileAssociation[]
function Files.list (kind) end

---The values of the associations of `kind` whose pattern fits `path`, newest first.
---@param kind string
---@param path string
---@return any[]
function Files.find (kind, path) end

---True when `path` fits `pattern`. Case does not matter on Windows.
---@param pattern string
---@param path string
---@return boolean
function Files.matches (pattern, path) end

---A pattern as a regular expression over a full path or address, for a program that takes one.
---@param pattern string
---@return string
function Files.to_regex (pattern) end

---------------------------------------------------------------------------------------------
-- marketplace (marketplace)
---------------------------------------------------------------------------------------------

---Plugins and profiles from four places: built-in, local (the workspace), project (the open
---folder's `.proteus` folder) and community (the registry). Each is a `Store.Entry` in the
---registry, from `store_core`.
---@class Proteus.Marketplace
local Marketplace = {}

---What the marketplace panel shows. A field left out keeps what it showed before.
---@class Proteus.MarketShowOptions
---@field query? string A search.
---@field source? 'all'|'builtin'|'local'|'project'|'community'
---@field kind? 'all'|'plugin'|'profile'

---Shows the marketplace panel, with an optional search, source and kind.
---@param opts? Proteus.MarketShowOptions
function Marketplace.show (opts) end

---Opens the page about one plugin or profile.
---@param kind 'plugin'|'profile'
---@param id string
function Marketplace.open (kind, id) end

---Reads the registry's index again. `done` runs once it is read.
---@param done? fun()
function Marketplace.refresh (done) end

---Runs `done` once the registry's index is read, reading it the first time.
---@param done fun()
function Marketplace.with_index (done) end

---What the registry lists for a plugin or profile, or nil.
---@param kind 'plugin'|'profile'
---@param id string
---@return Store.Entry?
function Marketplace.entry (kind, id) end

---When the index was last read, in milliseconds since 1970, or 0 before the first read.
---@return number
function Marketplace.read_at () end

---Every plugin and profile the registry lists, sorted by name. Empty before the index is read.
---@return Store.Entry[]
function Marketplace.entries () end

---The registry, as owner/name.
---@return string
function Marketplace.repository () end

---What the marketplace installed from the registry into the workspace, or nil.
---@param kind 'plugin'|'profile'
---@param id string
---@return Market.Installed?
function Marketplace.installed (kind, id) end

---------------------------------------------------------------------------------------------
-- publishing (proteus.plugin.publish)
---------------------------------------------------------------------------------------------

---The Publishing card on the page of one of your own plugins. The service needs the `kernel`
---permission.
---@class Proteus.Publishing
local Publishing = {}

---Fills `el` with the Publishing card of your own plugin `id`, and keeps it up to date: where
---the plugin stands in the registry, links to its issue and pull request, the conversation
---with the reviewers, and a box to reply. The card stays hidden for a plugin never sent.
---Returns a function that stops the updates.
---@param id string
---@param el Proteus.El
---@return fun()
function Publishing.follow (id, el) end

---------------------------------------------------------------------------------------------
-- project (proteus.code.project)
---------------------------------------------------------------------------------------------

---The folder the Code Editor works on. Every path is a full path with `/`, such as
---`C:/code/app/src/main.rs`. Opening another folder reloads the window, so a plugin reads
---`root` once when it starts. Changes on disk arrive as the `code:disk_changed` event.
---@class Proteus.Project
local Project = {}

---The open folder, or nil when none is open.
---@return string?
function Project.root () end

---The open folder's name, such as `app`, or nil when none is open.
---@return string?
function Project.name () end

---Opens a folder. It asks about unsaved changes first, then the window reloads into it.
---@param path string
function Project.open (path) end

---Shows the Open Folder dialog, then opens the folder picked.
function Project.pick () end

---Closes the folder. The window reloads with no folder open.
function Project.close () end

---Folders opened before, newest first.
---@return string[]
function Project.recent () end

---Takes a folder off the recent list.
---@param path string
function Project.forget (path) end

---Every file in the folder, as paths from the root, sorted. What `.gitignore` leaves out and
---the folder names in `excluded` are skipped. The list is kept until files come or go.
---@param cb fun(files: string[]?, err: string?)
function Project.files (cb) end

---The path from the root, or nil for a path outside the folder. '' is the root itself.
---@param path string
---@return string?
function Project.relative (path) end

---The full path for a path from the root.
---@param rel string
---@return string
function Project.absolute (rel) end

---Folder names that search and Go to File leave out, from the `project.exclude` setting.
---@return string[]
function Project.excluded () end

---True when the user trusts the open folder. Opening a folder runs nothing of its own until
---then: its `.proteus` files, its Git settings and its build scripts all wait.
---@return boolean
function Project.trusted () end

---Asks the user to trust the open folder. Trusting reloads the window, so a plugin that
---waits on it reads `trusted` again when it starts.
---@param reason? string What waits for it, such as `'Git'`.
function Project.ask_trust (reason) end

---------------------------------------------------------------------------------------------
-- app.process (the kernel)
---------------------------------------------------------------------------------------------

---@class Proteus.RunOptions
---@field cwd? string
---@field stdin? string Text written to the program before it reads.
---@field env? table<string, string> Variables added to the app's own environment, such as `{ GIT_TERMINAL_PROMPT = '0' }`.
---@field timeout? number Milliseconds before the program is stopped. `cb` then gets an error. None when nil.

---A program `app.process.run` is running.
---@class Proteus.RunHandle
---@field cancel fun() Stops the program. `cb` gets an error that says it was cancelled. Does nothing once it has ended.

---@class Proteus.RunResult
---@field code integer The exit code. 0 means success for most programs.
---@field stdout string
---@field stderr string

---@class Proteus.SpawnOptions
---@field cwd? string
---@field framing? 'lsp'|'lines' `'lsp'` reads and writes Language Server Protocol messages.
---@field on_message? fun(text: string) One message or one line from the program.
---@field on_stderr? fun(line: string)
---@field on_exit? fun(code: integer?)
---@field on_error? fun(err: string) The program could not start.

---@class Proteus.ProcessHandle
---@field write fun(text: string) Sends one message or line. Text sent before the program starts waits for it.
---@field kill fun()
---@field alive fun(): boolean

---@class Proteus.HttpRequest
---@field method? string `'GET'` when nil.
---@field url string
---@field headers? table<string, string>
---@field body? string

---@class Proteus.HttpReply
---@field status integer
---@field headers table<string, string> Names in lower case.
---@field body string

---HTTP from plugins. The desktop app sends requests itself, so any address works. The
---browser can only reach addresses that allow cross-origin requests.
---@class Proteus.Net
local Net = {}

---Sends a request. `err` means there was no answer at all. A 404 or 500 is an answer.
---@param request Proteus.HttpRequest
---@param cb fun(reply: Proteus.HttpReply?, err: string?)
function Net.fetch (request, cb) end

---Runs programs. Needs the desktop app.
---@class Proteus.Process
local Process = {}

---Runs a program to completion and reports its output. The handle stops it early.
---@param program string
---@param args string[]
---@param opts? Proteus.RunOptions
---@param cb fun(result: Proteus.RunResult?, err: string?)
---@return Proteus.RunHandle
function Process.run (program, args, opts, cb) end

---Starts a program that keeps running. It stops when the plugin stops.
---@param program string
---@param args string[]
---@param opts Proteus.SpawnOptions
---@return Proteus.ProcessHandle
function Process.spawn (program, args, opts) end

---Finds a program on the PATH.
---@param program string
---@param cb fun(path: string?)
function Process.which (program, cb) end

---Copies the builtin plugins, profiles, docs and types to a folder on disk, for tools that
---need real files. Calls `cb(folder)`.
---@param cb fun(folder: string?, err: string?)
function Process.export_builtin (cb) end

---One platform's download of a tool, pinned by its checksum.
---@class Proteus.ToolDownload
---@field id string The tool's id, such as `'taplo'`.
---@field version string
---@field name string The program's file name once installed, such as `'taplo.exe'`.
---@field url string An https address.
---@field sha256 string The download's SHA-256 checksum, in hex.
---@field file? string The program's name inside a `.zip`. A `.gz` holds the program alone.

---The path of a tool downloaded before, or nil when that version is not downloaded yet.
---@param spec { id: string, version: string, name: string }
---@param cb fun(path: string?, err: string?)
function Process.cached_tool (spec, cb) end

---Downloads a tool into the app's cache folder. The download is thrown away unless its
---checksum matches. Most plugins let `proteus.tools.registry` do this, since it asks the user first.
---@param spec Proteus.ToolDownload
---@param cb fun(path: string?, err: string?)
function Process.download_tool (spec, cb) end
