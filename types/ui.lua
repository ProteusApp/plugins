---@meta

-- Types for building screens: the `ui` service, its elements, and raw DOM access.

---What a DOM event looks like in Lua.
---@class Proteus.DomEvent
---@field type string Such as `'click'` or `'keydown'`.
---@field target? integer The handle of the element the event happened on, or its nearest parent with one.
---@field item? string The `data-item` attribute of the element the event happened on, or its nearest parent with one. Lets a list drawn with `el:html()` tell its rows apart.
---@field value? string The value of an input, for input and change events.
---@field checked? boolean For checkboxes.
---@field key? string For key events, such as `'Enter'` or `'a'`.
---@field code? string For key events, such as `'KeyA'`.
---@field ctrl? boolean
---@field shift? boolean
---@field alt? boolean
---@field meta? boolean
---@field repeat? boolean True when a held key repeats.
---@field composing? boolean True while an input method is composing text.
---@field x? number Pointer position from the left of the window.
---@field y? number Pointer position from the top of the window.
---@field button? integer 0 for the main button, 1 for the middle, 2 for the second.
---@field dx? number Wheel movement across.
---@field dy? number Wheel movement down.
---@field data? string Text an input event inserted.
---@field input_type? string Such as `'insertText'`.
---@field editable? boolean Right-click only. True over editable text.
---@field selection? string Right-click only. The selected text.
---@field paths? string[] `filedrop` only: the full paths of the files and folders dragged in from the system. A restricted plugin hears them with `files`, and only on its own elements.

---What an event handler may return.
---@alias Proteus.EventResult
---| true # Cancel the browser's default action.
---| 'prevent' # Cancel the browser's default action.
---| 'stop' # Cancel the default action and stop the event reaching parent elements.
---| nil # Let the event carry on.

---@class Proteus.ListenOptions
---@field prevent? boolean Always cancel the default action.
---@field stop? boolean Always stop the event reaching parent elements.
---@field capture? boolean Hear the event before the elements inside do.
---@field passive? boolean

---@class Proteus.FocusInfo
---@field tag string The focused element's tag, such as `'input'`, or empty when nothing has focus.
---@field editable boolean True for text fields and anything editable, where keys type text.
---@field handle? integer
---@field owns_keys? boolean True inside a widget that takes every key itself, such as a terminal.

---@class Proteus.Rect
---@field x number
---@field y number
---@field w number
---@field h number
---@field top number
---@field left number
---@field right number
---@field bottom number

---@class Proteus.StyleHandle
---@field set fun(self: Proteus.StyleHandle, text: string) Replaces the CSS.
---@field remove fun() Removes the CSS now instead of when the plugin stops.

---Raw DOM access by number handle. The `ui` service wraps all of this, so most plugins never
---need it.
---
---An element belongs to the plugin that created it, and whatever an element holds belongs to
---its owner too. A restricted plugin reaches only its own elements: a call with another
---plugin's handle raises an error.
---@class Proteus.Dom
local Dom = {}

---The window's own element. A restricted plugin cannot reach it.
---@return integer handle
function Dom.root () end

---A restricted plugin cannot make a `style`, `link`, `meta`, `base` or `script` element.
---@param tag string An HTML tag, `'#text'` for a text node, or `'svg:<tag>'` for SVG.
---@return integer handle
function Dom.create (tag) end

---HTML a restricted plugin sets loses page-wide elements and attributes that name an id.
---It cannot set `outerHTML` or `htmlFor`.
---@param handle integer
---@param prop string
---@param value any
function Dom.set (handle, prop, value) end

---@param handle integer
---@param prop string
---@return any
function Dom.get (handle, prop) end

---A restricted plugin cannot set an attribute that names another element by its id, such
---as `for` or `aria-controls`, or `data-plugin`.
---@param handle integer
---@param name string
---@param value any nil or false removes it.
function Dom.attr (handle, name, value) end

---@param handle integer
---@param name string
---@return string?
function Dom.get_attr (handle, name) end

---@param handle integer
---@param name string A CSS property or a `--variable`.
---@param value any nil removes it.
function Dom.style (handle, name, value) end

---@param handle integer
---@param name string
---@param on? boolean Toggles when nil.
---@return boolean
function Dom.class (handle, name, on) end

---@param handle integer
---@param name string
---@return boolean
function Dom.has_class (handle, name) end

---Moves `child` to the end of `parent`. A restricted plugin may move another plugin's
---element into its own when it passes that plugin's `app.dom` as `child_dom`, as an element
---object another plugin shared with it does.
---@param parent integer
---@param child integer
---@param child_dom? Proteus.Dom The `app.dom` of the plugin that owns `child`.
function Dom.append (parent, child, child_dom) end

---@param parent integer
---@param child integer
---@param before? integer Appends when nil.
---@param child_dom? Proteus.Dom The `app.dom` of the plugin that owns `child`.
function Dom.insert (parent, child, before, child_dom) end

---Takes the element out of the page and forgets its handle.
---@param handle integer
function Dom.remove (handle) end

---Takes the element out of the page but keeps its handle.
---@param handle integer
function Dom.detach (handle) end

---@param handle integer
function Dom.clear (handle) end

---@param handle integer
---@return integer?
function Dom.parent (handle) end

---@param outer integer
---@param inner integer
---@return boolean
function Dom.contains (outer, inner) end

---True while the element exists and sits in the page.
---@param handle integer
---@return boolean
function Dom.alive (handle) end

---Calls a DOM method, such as `'focus'` or `'scrollIntoView'`. A restricted plugin cannot call
---the ones that set attributes or HTML, or `showModal`, `showPopover` and `requestFullscreen`.
---@param handle integer
---@param method string
---@param ... any
---@return any
function Dom.call (handle, method, ...) end

---@param handle integer
---@return Proteus.Rect
function Dom.rect (handle) end

---@return { w: number, h: number }
function Dom.viewport () end

---The handle of the focused element, if it has one this plugin can reach.
---@return integer?
function Dom.active () end

---What has keyboard focus, even an element with no handle, such as text in a code editor.
---@return Proteus.FocusInfo
function Dom.focus_info () end

---Runs a browser editing command, such as `'copy'`, `'undo'` or `'insertText'`. A restricted
---plugin cannot run `'insertHTML'`.
---@param command string
---@param value? string
---@return boolean
function Dom.exec (command, value) end

---@param handle integer
---@param event string
---@param fn fun(ev: Proteus.DomEvent): Proteus.EventResult
---@param opts? Proteus.ListenOptions
---@return integer listener
function Dom.on (handle, event, fn, opts) end

---Listens on the whole window. Stops by itself when the plugin stops. For a restricted plugin,
---an event on another plugin's element tells only its type, the pointer, the wheel and the
---modifier keys, plus the key for a shortcut pressed outside a text field.
---@param event string
---@param fn fun(ev: Proteus.DomEvent): Proteus.EventResult
---@param opts? Proteus.ListenOptions
---@return fun() off
function Dom.on_global (event, fn, opts) end

---@param listener integer
function Dom.off (listener) end

---True when this plugin may use the element. Always true for a builtin plugin.
---@param handle integer
---@return boolean
function Dom.owns (handle) end

---Hands an element to another plugin, such as the body of a modal to the plugin that opened
---it. Only builtin plugins can.
---@param handle integer
---@param plugin string
function Dom.give (handle, plugin) end

---Adds CSS to the page. It goes away when the plugin stops. A restricted plugin's CSS styles
---only its own elements.
---@param text string
---@return Proteus.StyleHandle
function Dom.css (text) end

---A widget by name: `'code'`, `'terminal'` (needs the `process` permission) or `'webview'`.
---@overload fun(kind: 'terminal', opts?: Proteus.TerminalOptions): integer
---@overload fun(kind: 'webview', opts: Proteus.WebviewOptions): integer
---@param kind 'code'
---@param opts? Proteus.CodeOptions
---@return integer handle
function Dom.widget (kind, opts) end

---@param handle integer
---@param method string
---@param ... any
---@return any
function Dom.widget_call (handle, method, ...) end

---------------------------------------------------------------------------------------------
-- Elements
---------------------------------------------------------------------------------------------

---Anything that can go inside an element.
---@alias Proteus.Child Proteus.El|string|number|boolean|nil|Proteus.Child[]

---The table that builds an element. Named keys set things. Numbered entries are children.
---
---```lua
---ui.div({ class = 'row', ui.span({ 'Hello' }), onclick = function () end })
---```
---@class Proteus.ElementSpec
---@field [integer] Proteus.Child
---@field class? string|string[]
---@field style? table<string, string|number>|string Such as `{ color = 'red', ['--gap'] = '4px' }`.
---@field text? string|number Sets the text.
---@field html? string Sets the inner HTML.
---@field attrs? table<string, any> HTML attributes.
---@field icon? string A Lucide icon placed before the children.
---@field ref? fun(el: Proteus.El) Receives the new element.
---@field variant? 'primary'|'ghost'|'danger' For `ui.button`.
---@field multiline? boolean For `ui.input`: a text area.
---@field title? string A tooltip.
---@field value? string|number
---@field placeholder? string
---@field type? string Such as `'checkbox'`, `'color'` or `'number'`.
---@field checked? boolean
---@field selected? boolean
---@field disabled? boolean
---@field spellcheck? boolean
---@field href? string
---@field src? string
---@field onclick? fun(ev: Proteus.DomEvent): Proteus.EventResult
---@field ondblclick? fun(ev: Proteus.DomEvent): Proteus.EventResult
---@field oninput? fun(ev: Proteus.DomEvent): Proteus.EventResult
---@field onchange? fun(ev: Proteus.DomEvent): Proteus.EventResult
---@field onkeydown? fun(ev: Proteus.DomEvent): Proteus.EventResult
---@field onkeyup? fun(ev: Proteus.DomEvent): Proteus.EventResult
---@field onmousedown? fun(ev: Proteus.DomEvent): Proteus.EventResult
---@field onmouseup? fun(ev: Proteus.DomEvent): Proteus.EventResult
---@field onmouseover? fun(ev: Proteus.DomEvent): Proteus.EventResult
---@field onmouseenter? fun(ev: Proteus.DomEvent): Proteus.EventResult
---@field onmouseleave? fun(ev: Proteus.DomEvent): Proteus.EventResult
---@field onfocus? fun(ev: Proteus.DomEvent): Proteus.EventResult
---@field onblur? fun(ev: Proteus.DomEvent): Proteus.EventResult
---@field onscroll? fun(ev: Proteus.DomEvent): Proteus.EventResult
---@field onwheel? fun(ev: Proteus.DomEvent): Proteus.EventResult
---@field [string] any Any other property or `on<event>` handler.

---An element on screen. Most methods return the element, so calls chain.
---@class Proteus.El
---@field id integer The DOM handle.
---@field dom Proteus.Dom
local El = {}

---Adds children at the end.
---@param ... Proteus.Child
---@return Proteus.El
function El:append (...) end

---@param child Proteus.El
---@param ref? Proteus.El Appends when nil.
---@return Proteus.El
function El:insert_before (child, ref) end

---Replaces all children.
---@param list Proteus.Child[]
---@return Proteus.El
function El:set_children (list) end

---@return Proteus.El
function El:clear () end

---Removes the element for good.
function El:remove () end

---Takes the element off screen but keeps it for later.
---@return Proteus.El
function El:detach () end

---@param prop string
---@param value any
---@return Proteus.El
function El:set (prop, value) end

---@param prop string
---@return any
function El:get (prop) end

---Sets an attribute, or reads it when `value` is nil.
---@overload fun(self: Proteus.El, name: string): string?
---@param name string
---@param value any
---@return Proteus.El
function El:attr (name, value) end

---@param name string
---@return Proteus.El
function El:unattr (name) end

---Sets one style, or several from a table.
---@overload fun(self: Proteus.El, styles: table<string, any>): Proteus.El
---@param name string
---@param value any nil removes it.
---@return Proteus.El
function El:style (name, value) end

---Adds a class, removes it when `on` is false, or toggles it when `on` is nil.
---@param name string
---@param on? boolean
---@return Proteus.El
function El:class (name, on) end

---@param name string
---@return boolean
function El:has_class (name) end

---@param text any
---@return Proteus.El
function El:text (text) end

---@param html string
---@return Proteus.El
function El:html (html) end

---Reads the value when called with no argument, or sets it.
---@overload fun(self: Proteus.El): string
---@param value string|number
---@return Proteus.El
function El:value (value) end

---Reads the checked state when called with no argument, or sets it.
---@overload fun(self: Proteus.El): boolean
---@param on boolean
---@return Proteus.El
function El:checked (on) end

---Listens for an event. Returns a function that stops listening.
---@param event string Such as `'click'`, `'input'` or `'keydown'`.
---@param fn fun(ev: Proteus.DomEvent): Proteus.EventResult
---@param opts? Proteus.ListenOptions
---@return fun() off
function El:on (event, fn, opts) end

---Shows the element, or hides it when `on` is false.
---@param on? boolean
---@return Proteus.El
function El:show (on) end

---@return Proteus.El
function El:focus () end

---@return Proteus.El
function El:blur () end

---Selects all the text of an input.
---@return Proteus.El
function El:select () end

---@param method string
---@param ... any
---@return any
function El:call (method, ...) end

---@return Proteus.Rect
function El:rect () end

---@return boolean
function El:alive () end

---@param other Proteus.El
---@return boolean
function El:contains (other) end

---@return Proteus.El
function El:scroll_into_view () end

---Calls a method on a widget made with `ui.widget`.
---@overload fun(self: Proteus.El, method: 'get_text'): string
---@overload fun(self: Proteus.El, method: 'set_text', text: string)
---@overload fun(self: Proteus.El, method: 'selection'): string
---@overload fun(self: Proteus.El, method: 'cursor'): { line: integer, col: integer }
---@overload fun(self: Proteus.El, method: 'goto', line: integer, col?: integer)
---@overload fun(self: Proteus.El, method: 'reveal', line: integer)
---@overload fun(self: Proteus.El, method: 'scroll_to', line: integer)
---@overload fun(self: Proteus.El, method: 'viewport'): { first: integer, last: integer }?
---@overload fun(self: Proteus.El, method: 'selections'): { first: integer, last: integer }[]
---@overload fun(self: Proteus.El, method: 'insert', text: string)
---@overload fun(self: Proteus.El, method: 'focus')
---@overload fun(self: Proteus.El, method: 'select_all')
---@overload fun(self: Proteus.El, method: 'undo')
---@overload fun(self: Proteus.El, method: 'redo')
---@overload fun(self: Proteus.El, method: 'find')
---@overload fun(self: Proteus.El, method: 'line_count'): integer
---@overload fun(self: Proteus.El, method: 'set_language', language: string)
---@overload fun(self: Proteus.El, method: 'set_readonly', on: boolean)
---@overload fun(self: Proteus.El, method: 'set_wrap', on: boolean)
---@overload fun(self: Proteus.El, method: 'set_completions', words: string[])
---@overload fun(self: Proteus.El, method: 'set_diagnostics', list: Proteus.Diagnostic[])
---@overload fun(self: Proteus.El, method: 'set_provider', provider: Proteus.CodeProvider?)
---@overload fun(self: Proteus.El, method: 'set_schema', schema: string|(fun(): string?)|nil)
---@overload fun(self: Proteus.El, method: 'set_highlight', lines: integer[])
---@overload fun(self: Proteus.El, method: 'replace_text', text: string)
---@param method string
---@param ... any
---@return any
function El:widget (method, ...) end

---------------------------------------------------------------------------------------------
-- The code widget
---------------------------------------------------------------------------------------------

---A real terminal. It runs a program in a pseudo-terminal, so colours, cursor keys and
---full-screen programs such as vim work. Needs the desktop app.
---Methods: `start`, `stop`, `restart`, `send` (text), `focus`, `clear`, `fit`, `running`,
---`set_program` (program, args?, cwd?), `set_font_size` (size).
---@class Proteus.TerminalOptions
---@field program? string The system shell when empty.
---@field args? string[]
---@field cwd? string The home folder when empty.
---@field font_size? number
---@field autostart? boolean Starts once it has a size. True when nil.
---@field on_started? fun()
---@field on_exit? fun(code: integer?)
---@field on_title? fun(title: string)

---@class Proteus.CodeOptions
---@field text? string
---@field language? string See `app.util.code_languages()`.
---@field readonly? boolean
---@field wrap? boolean
---@field completions? string[] Extra words to offer.
---@field on_change? fun() Runs after each edit. Read the text with `get_text`.
---@field on_cursor? fun(line: integer, col: integer) Lines and columns start at 1.
---@field on_scroll? fun(first: integer, last: integer) Runs with the first and last lines on screen, from 1, when they change.
---@field on_select? fun(ranges: { first: integer, last: integer }[]) Runs with the lines each selection covers, from 1, when they change.
---@field provider? Proteus.CodeProvider Smarter help from a language server.
---@field schema? string|fun(): string? A JSON schema as JSON text, or a function that returns it each time it is needed. A JSON file gets completion, hover help and checks from it.

---A position inside a document. Both start at 0, as in the Language Server Protocol.
---@class Proteus.CodePosition
---@field line integer
---@field character integer

---@class Proteus.CompletionItem
---@field label string
---@field kind? string Such as `'function'`, `'variable'`, `'keyword'` or `'property'`. `'text'` marks a plain word with no type behind it, shown dimmed.
---@field detail? string A short type or signature.
---@field documentation? string Markdown.
---@field insert? string Text to insert when it differs from the label.

---@class Proteus.CompletionResult
---@field items Proteus.CompletionItem[]
---@field from? integer Column, from 0, where the word being completed starts.

---Hooks a language server fills in for one editor. Each gets a `respond` function to call
---with its answer, now or later.
---@class Proteus.CodeProvider
---@field complete? fun(pos: Proteus.CodePosition, respond: fun(result: Proteus.CompletionResult?))
---@field resolve? fun(item: Proteus.CompletionItem, respond: fun(documentation: string?))
---@field hover? fun(pos: Proteus.CodePosition, respond: fun(markdown: string?))
---@field definition? fun(pos: Proteus.CodePosition)

---@alias Proteus.Severity 'error'|'warning'|'info'|'hint'

---A problem in a file, from a linter or a language server.
---@class Proteus.Diagnostic
---@field line integer From 0.
---@field character integer From 0.
---@field end_line? integer From 0. The same line when nil.
---@field end_character? integer From 0.
---@field severity Proteus.Severity
---@field message string
---@field source? string Such as `'luals'` or `'selene'`.
---@field code? string A rule name, such as `'undefined-field'`.

---------------------------------------------------------------------------------------------
-- The ui service
---------------------------------------------------------------------------------------------

---Builds elements from tables. Every tag works as a function: `ui.div`, `ui.span`, `ui.h1`...
---@class Proteus.UI
---@field div fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field span fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field p fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field a fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field h1 fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field h2 fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field h3 fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field h4 fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field ul fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field ol fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field li fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field img fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field label fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field code fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field pre fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field kbd fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field strong fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field em fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field small fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field section fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field header fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field footer fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field nav fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field table fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field tr fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field td fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field th fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field option fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field textarea fun(spec?: Proteus.ElementSpec|string): Proteus.El
---@field [string] fun(spec?: Proteus.ElementSpec|string): Proteus.El
local UI = {}

---Builds any tag.
---@param tag string
---@param spec? Proteus.ElementSpec|string
---@return Proteus.El
function UI.h (tag, spec) end

---Applies a spec to an element that already exists.
---@param el Proteus.El
---@param spec Proteus.ElementSpec
---@return Proteus.El
function UI.apply (el, spec) end

---Wraps a raw DOM handle as an element.
---@param handle integer
---@return Proteus.El
function UI.wrap (handle) end

---Gives an element to the plugin a service works for, and returns it as that plugin's own. A
---builtin service calls it for each element it hands to a restricted plugin, such as the body
---of a modal. A builtin plugin gets the element back unchanged.
---@param el Proteus.El
---@param consumer Proteus.App The plugin's `app`, as `provide_scoped` passes it.
---@return Proteus.El
function UI.hand (el, consumer) end

---Takes an element a plugin passed to a service, such as a view's content, after checking
---that it is a real element whose maker owns it: the plugin's own, or one another plugin
---shared with it. Returns it as the service's own, or raises an error. A builtin plugin's
---element comes back unchanged.
---@param el Proteus.El
---@param consumer Proteus.App The plugin's `app`, as `provide_scoped` passes it.
---@param what string What the element is for, such as `'shell.mount'`, for the error.
---@return Proteus.El
function UI.adopt (el, consumer, what) end

---@param value any
---@return boolean
function UI.is (value) end

---A Lucide icon. See https://lucide.dev/icons for names. A `Proteus.FileIcon`, as proteus.core.icons
---gives, also works: its icon or its letter badge, in its color.
---@param name string|Proteus.FileIcon
---@param size? integer
---@return Proteus.El
function UI.icon (name, size) end

---A styled button. Pass `variant = 'primary'`, `'ghost'` or `'danger'` to change its look.
---@param spec Proteus.ElementSpec|string
---@return Proteus.El
function UI.button (spec) end

---A styled text input, or a text area with `multiline = true`.
---@param spec? Proteus.ElementSpec
---@return Proteus.El
function UI.input (spec) end

---@param text string
---@param spec? Proteus.ElementSpec
---@return Proteus.El
function UI.markdown (text, spec) end

---A ready-made widget. `'code'` is a full code editor. `'terminal'` is a real terminal, which
---needs the `process` permission. `'webview'` is a sandboxed page: `ui.webview` builds one.
---@overload fun(kind: 'terminal', opts?: Proteus.TerminalOptions): Proteus.El
---@overload fun(kind: 'webview', opts: Proteus.WebviewOptions): Proteus.El
---@param kind 'code'
---@param opts? Proteus.CodeOptions
---@return Proteus.El
function UI.widget (kind, opts) end

---A page the plugin ships, run in a sandboxed frame: its own scripts, WebGL, WebGPU, audio,
---a chart library. The page cannot reach the app, the network or the plugin's powers. It
---talks to the plugin only through messages: plain JSON, sent with `proteus.post(message)`
---and received with `proteus.on(fn)`. Needs the feature `'webview'`.
---
---`page` is read from the plugin's folder, and the scripts and style sheets it names by
---relative path are put inside it. Post to the page with `el:widget('post', message)`, and
---start it again with `el:widget('reload')`.
---@param opts Proteus.WebviewSpec
---@return Proteus.El
function UI.webview (opts) end

---Adds a language to the code editor, described as data: `app.util.language`. It goes
---away when the plugin stops. Needs the feature `'languages'`.
---@param spec Proteus.LanguageSpec
---@return fun() remove
function UI.language (spec) end

---The element everything on screen lives in. A restricted plugin cannot reach it.
---@return Proteus.El
function UI.root () end

---Puts an element straight on the window, or inside `parent`. It goes away when the plugin stops.
---@param el Proteus.El
---@param parent? Proteus.El
---@return Proteus.El
function UI.mount (el, parent) end

---Adds CSS to the page. It goes away when the plugin stops. A restricted plugin's CSS styles
---only its own elements.
---@param text string
---@return Proteus.StyleHandle
function UI.css (text) end

---@param text string
---@return string
function UI.escape (text) end

---@class Proteus.WebviewOptions
---@field html string The whole page.
---@field on_message? fun(message: any) A message from the page, as plain data.
---@field on_status? fun(status: { responsive: boolean, error?: string }) The page stopped answering, answers again, or failed to load.
---@field autoplay? boolean Lets the page play sound before anyone clicks in it. Needs the feature `'autoplay'`.
---@field on_saved? fun(id: string, error: string?) A save the page asked for with `proteus.save` finished.
---@field folder? string A folder of the plugin whose files the page loads by relative address. The kernel lists them.
---@field mounts? string[] Plugins whose exported folders the page loads, under `_/<plugin id>/<folder>/`.

---@class Proteus.WebviewSpec
---@field page? string A page in the plugin's folder, such as `'page/preview.html'`. Defaults to `'index.html'`.
---@field html? string The whole page, instead of `page`.
---@field class? string
---@field on_message? fun(message: any) A message from the page, as plain data.
---@field on_status? fun(status: { responsive: boolean, error?: string }) The page stopped answering, answers again, or failed to load.
---@field autoplay? boolean Lets the page play sound before anyone clicks in it. Needs the feature `'autoplay'`.
---@field on_saved? fun(id: string, error: string?) A save the page asked for with `proteus.save` finished.
---@field files? boolean Serve the page with the files of its folder instead of inlining them, so it can load modules, worklets and WebAssembly. Needs the feature `'webview-files'`.
---@field mounts? string[] With `files`, running plugins whose `exports` the page loads, under `_/<plugin id>/<folder>/`.
