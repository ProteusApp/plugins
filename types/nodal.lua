---@meta

-- Types for Nodal, a visual builder for logic and small apps. Blocks with typed inputs and one
-- typed output are wired into a graph. The graph compiles to one program, which is evaluated
-- for a live preview and emitted three ways: a typed TypeScript module, a Lua module, and a
-- working Proteus plugin. Event and app blocks give the plugin buttons, timers and effects.
--
-- proteus.nodal.core is pure Lua: no DOM, no host, no `app`. Its modules are listed at the end of
-- this file. The UI plugins reach them through the `nodal` service.

---------------------------------------------------------------------------------------------
-- Ports and blocks
---------------------------------------------------------------------------------------------

---@alias Nodal.PortType
---| 'number' # Shown as "number". Emitted as `number`.
---| 'text' # Shown as "text". Emitted as `string`.
---| 'boolean' # Shown as "yes/no". Emitted as `boolean`.
---| 'any' # Shown as "any". Emitted as `unknown`.
---| 'list' # Shown as "list". A list of values, first item at position 1. Emitted as `unknown[]`.
---| 'record' # Shown as "record". Named fields, such as parsed JSON. Emitted as `Record<string, unknown>`.
---| 'event' # Shown as "event". A trigger, not a value: it only joins an event output to an event input.

---@alias Nodal.Category 'input'|'value'|'math'|'logic'|'text'|'list'|'data'|'flow'|'output'|'event'|'app'|'state'|'system'|'net'|'ui'|'custom'

---@alias Nodal.OutputFormat 'plain'|'money'|'percent'

---@class Nodal.TypeInfo
---@field id Nodal.PortType
---@field label string What users see, such as `'yes/no'`.
---@field ts string The emitted TypeScript type, such as `'boolean'`.
---@field color string A hex colour, such as `'#1D9E75'`.
---@field zero any The value an unconnected input with no literal and no default takes.

---@class Nodal.PortDef
---@field key string Stable. Edges point at inputs by key, never by position.
---@field label string
---@field type Nodal.PortType
---@field default? any
---For another output of a formula block: what it works out from the same inputs, such as
---Read JSON's `ok`, which is `'json_ok(text)'`.
---@field formula? string
---@field ast? Nodal.Ast That formula, parsed and checked once at load.

---@class Nodal.ConfigField
---@field key string
---@field label string
---@field kind 'number'|'select'|'text'|'boolean'|'node'
---@field default any
---@field options? string[] For `'select'`.
---@field blocks? string[] For `'node'`: the blocks the chosen node may be, such as `{ 'state.text' }`. The value is a node id, or `''` for none.

---A block definition. It is data, and its formula is the single definition of what it does.
---@class Nodal.BlockDef
---@field id string Namespaced and stable, such as `'math.multiply'`.
---@field title string Such as `'Multiply'`.
---@field description string One plain-language line.
---@field category Nodal.Category
---@field icon string A Lucide icon name.
---@field inputs Nodal.PortDef[]
---@field output Nodal.PortType? The type of the main output, whose key is `'value'`. nil for blocks with no main output, such as outputs and most app blocks.
---More outputs, each with its own key, such as a Program's `line` and its `stdout` event.
---Edges from one of these name it in `Nodal.Edge.output`.
---@field outputs? Nodal.PortDef[]
---@field formula string? nil for input and output blocks.
---@field ast? Nodal.Ast The formula, parsed and checked once at load.
---@field helpers? string[] Library helpers the formula calls, such as `'round'`.
---@field config? Nodal.ConfigField[]
---For a code block: its Lua file text. The file's `run` works out every output at once.
---@field source? string
---For a block written as a file: its first output as the file declares it, such as
---`{ key = 'first', label = 'first name', type = 'text' }`. Wires still call it `'value'`.
---@field main? Nodal.PortDef

---A block a user made. It is stored in the document, so a graph carries its own blocks.
---A formula block has one formula per output. A code block runs a Lua `run` function.
---@class Nodal.CustomBlockDef
---@field id string `'custom.'` followed by a slug of the title.
---@field title string
---@field description? string
---@field icon? string A Lucide icon name.
---@field inputs Nodal.PortDef[]
---@field output Nodal.PortType The main output's type.
---@field formula string The main output's formula. `''` for a code block.
---@field outputs? Nodal.PortDef[] More outputs, each with its own `formula` in a formula block.
---@field kind? 'formula'|'code' nil means `'formula'`.
---@field source? string The block's file text, for a block written as a `.ndb.lua` file.
---@field file? string The workspace path of that file, such as `'blocks/split-name.ndb.lua'`.

---------------------------------------------------------------------------------------------
-- Formulas
---------------------------------------------------------------------------------------------

---A node of a parsed formula. Only whitelisted forms exist.
---@class Nodal.Ast
---@field kind 'literal'|'ident'|'unary'|'binary'|'logical'|'conditional'|'array'|'call'|'member_call'
---@field value? any For `'literal'`.
---@field name? string For `'ident'`, and the function name for `'call'`, such as `'Math.min'` or `'round'`.
---@field op? string For `'unary'`, `'binary'` and `'logical'`, such as `'-'`, `'*'`, `'>='`, `'&&'`.
---@field left? Nodal.Ast
---@field right? Nodal.Ast
---@field test? Nodal.Ast For `'conditional'`.
---@field consequent? Nodal.Ast
---@field alternate? Nodal.Ast
---@field argument? Nodal.Ast For `'unary'`.
---@field elements? Nodal.Ast[] For `'array'`.
---@field args? Nodal.Ast[] For `'call'` and `'member_call'`.
---@field object? Nodal.Ast For `'member_call'`.
---@field method? string For `'member_call'`: `'toUpperCase'`, `'toLowerCase'` or `'join'`.
---@field type? Nodal.PortType Filled in by the checker.

---------------------------------------------------------------------------------------------
-- The document
---------------------------------------------------------------------------------------------

---@class Nodal.Position
---@field x number
---@field y number

---@class Nodal.Node
---@field id string Never reused within a document.
---@field block string A block id.
---@field name string The display name. Empty means "use the block's title".
---@field position Nodal.Position Never affects the emitted code.
---@field config table<string, any> Such as `{ operator = '>=' }` or `{ value = 49 }` for inputs.
---@field literals table<string, any> Values for unconnected inputs, by input key.

---@class Nodal.Edge
---@field id string
---@field from string The source node id.
---@field output? string The source output's key. nil for the main output, `'value'`.
---@field to string The target node id.
---@field input string The target input's key.

---@class Nodal.Settings
---@field locale string Such as `'en-US'`.
---@field currency string Such as `'USD'`.

---One box in the app's layout: a UI block from the graph, or a container of more boxes.
---@class Nodal.LayoutBox
---@field node? string A UI block's node id. nil for a container.
---@field id? string A container's id, such as `'box3'`. Unique in the layout. The root's id is `'root'`.
---@field kind? 'row'|'column'|'card'|'free' A container's kind. The root is a column.
---@field title? string A card's title.
---@field children? Nodal.LayoutBox[] A container's boxes, in order.
---@field grow? boolean Takes the space left over in its container.
---@field width? number Pixels. nil or 0 means automatic.
---@field height? number
---@field x? number Pixels from the left of a free container. Used only inside one.
---@field y? number

---@class Nodal.Doc
---@field version integer The file format version.
---@field settings Nodal.Settings
---@field blocks Nodal.CustomBlockDef[]
---@field nodes Nodal.Node[]
---@field edges Nodal.Edge[]
---@field next_id integer The next node or edge number, so ids are never reused.
---Where the app's UI blocks sit. The visual designer edits it, and the graph never reads it.
---nil puts every shown UI block in one column, in node order.
---@field layout? Nodal.LayoutBox

---@alias Nodal.RefusalCode
---| 'type-mismatch' # detail: { from, to }
---| 'cycle'
---| 'self-connection'
---| 'name-taken' # detail: { name }
---| 'formula-syntax' # detail: { token, position }
---| 'formula-unknown' # detail: { name, position }
---| 'formula-type' # detail: { expected, got, position }
---| 'unknown-block' # detail: { block }
---| 'unknown-node' # detail: { node }
---| 'unknown-input' # detail: { input }
---| 'invalid-value' # detail: { key }. For a layout, key is 'layout' and there is also { reason, field }. See `Nodal.GraphModule.set_layout`.
---| 'nothing-to-undo'
---| 'nothing-to-redo'
---| 'invalid-file' # detail: { reason }
---| 'invalid-lua' # Text that is not a Lua table of values. detail: { reason: 'syntax'|'not-data', line, col, expected?, got? }
---| 'invalid-interface' # detail: { reason, field, line?, ... }. See `Nodal.InterfaceReason`.
---| 'invalid-block' # detail: { reason: 'shape'|'unknown-field'|'syntax'|'runtime'|'formula', field, expected?, line?, message?, refusal? }. `message` is the Lua error for 'syntax' and 'runtime'. `refusal` is the formula's own refusal for 'formula'.

---Why an operation did not happen. Core returns codes. The UI owns the sentences.
---@class Nodal.Refusal
---@field code Nodal.RefusalCode
---@field detail? table<string, any>

---Undo and redo over whole documents. Pure: every call returns a new history.
---@class Nodal.History
---@field past Nodal.Doc[]
---@field present Nodal.Doc
---@field future Nodal.Doc[]
---@field last_key? string The coalescing key of the last entry.
---@field last_time? number When the last entry was pushed, in milliseconds.

---------------------------------------------------------------------------------------------
-- The program: one IR, two backends
---------------------------------------------------------------------------------------------

---@class Nodal.Param
---@field node string
---@field ident string The identifier in the emitted code, such as `'price'`.
---@field type Nodal.PortType
---@field value any The input node's own value. evaluate uses it when no input is passed.
---@field block string The input block, such as `'input.slider'`, which picks the form field.
---@field label string The node's name, or the block's title when it has none.
---@field config table<string, any> Every setting, with defaults filled in, such as a slider's `min`.

---An argument to a step: a reference to a value, or a typed literal.
---@class Nodal.Arg
---@field ref? string A value reference: a node id for a main output, or `'<node>.<key>'` for another output. See `Nodal.GraphModule.ref`.
---@field value? any A literal, when `ref` is nil.
---@field type Nodal.PortType

---@class Nodal.Step
---@field node string
---@field output? string For another output of a formula block, such as `'ok'`. Its value is at `'<node>.<output>'`, and the step comes right after the node's main one.
---@field ident string
---@field block string
---@field ast Nodal.Ast
---@field args table<string, Nodal.Arg> By input key.
---@field type Nodal.PortType
---True for a code block's step. Its `ast` is a placeholder: calling the block's `run` gives
---every output at once, the main one at the node id and each other at `'<node>.<key>'`.
---@field code? boolean

---@class Nodal.Result
---@field node string
---@field key string The field name in `Outputs`, such as `'total'`.
---@field source Nodal.Arg
---@field format Nodal.OutputFormat
---@field label string The node's name, or the block's title when it has none.
---@field style 'card'|'text'|'console' How the app shows it. `'console'` is a log that scrolls.

---Something that fires: a button, a timer, the plugin starting, a text field's Enter, a
---program's new line. A block updates its value outputs first, then fires, so everything wired
---to the event sees the new values.
---@class Nodal.Trigger
---@field node string
---@field output string The event output's key: `'value'` for the event blocks, such as a button's click, or a key such as `'submitted'` or `'stdout'`.
---@field block string Such as `'event.button'`.
---@field ident string An identifier for the handler, such as `'onSayTotal'`.
---@field config table<string, any> The block's settings, such as `{ label = 'Say total', icon = 'play' }`.

---Something the program does in the app, such as showing a message.
---@class Nodal.Effect
---@field node string
---@field block string Such as `'app.notify'`.
---@field trigger string? The trigger node that fires it. nil for live effects, such as status bar text, which follow the values.
---@field trigger_output? string The key of the trigger's event output. nil means `'value'`.
---@field outputs? string[] The keys of its own outputs, for blocks that report back, such as `system.run`.
---Every wired event input, by input key, such as a Program's `start` and `stop`.
---@field events? table<string, { node: string, output: string }>
---@field args table<string, Nodal.Arg> Its value inputs, by key. Event inputs are left out.
---@field config table<string, any>

---A value the app keeps and changes with Set blocks, such as a terminal's scrollback.
---@class Nodal.Variable
---@field node string
---@field ident string
---@field type Nodal.PortType
---@field value any What it starts at.

---One thing the app shows. Items form a tree, from the layout: each sits in the app itself or
---in a container.
---@class Nodal.UiItem
---A node id, or `'layout:' .. id` for a container of the layout, such as `'layout:box3'`.
---@field node string
---Such as `'ui.textbox'` or `'input.number'`. A container is `'ui.row'`, `'ui.column'`,
---`'ui.card'` or `'ui.free'`, which are not blocks of the catalog.
---@field block string
---@field kind 'input'|'button'|'result'|'status'|'component'|'container' The first four are the simple blocks. `'component'` is a `ui.*` block, and `'container'` a box of the layout.
---@field parent? string The `'layout:' .. id` of the container it sits in. nil for the root's own boxes.
---@field order number Its place in its container, from 1.
---@field grow boolean Takes the space left over in its container, such as a log view.
---@field title? string A card's title.
---@field width number Pixels. 0 means as wide as it needs, or the space it is given.
---@field height number Pixels. 0 means as tall as it needs.
---@field x number Pixels from the left of a Free layout. Used only inside one.
---@field y number Pixels from the top of a Free layout. Used only inside one.

---A value from outside the pure logic that steps or results read: a variable, or an output a
---block reports at run time, such as a Program's `line` or a text box's text. The emitted `run`
---takes each one as an extra input, after the parameters.
---@class Nodal.StateInput
---@field ref string Its reference, such as `'n3'` for a variable or a text box, or `'n2.line'`.
---@field ident string The identifier in the emitted code, such as `'log'` or `'shellLine'`.
---@field type Nodal.PortType
---@field value any What it starts at: a variable's start value, or the type's zero.

---@class Nodal.Program
---@field variables Nodal.Variable[] In node-id order. Pure code gets them as inputs.
---@field state Nodal.StateInput[] What steps and results read from state, in node-id order.
---@field ui Nodal.UiItem[] What the app shows. Parents come before their children, and siblings are in order.
---The whole layout: the document's, with boxes for nodes that are gone or not shown left out,
---and every shown UI block it does not name added to the root, in node-id order.
---@field layout Nodal.LayoutBox
---Right-click menus, in node-id order: each `ui.menu` block and the component it opens on.
---A menu is not drawn, so it is not in `ui`. One whose target is not a drawn component is left out.
---@field menus { node: string, target: string }[]
---@field params Nodal.Param[] In node-id order.
---@field steps Nodal.Step[] In topological order, node id breaking ties.
---@field results Nodal.Result[] In node-id order.
---@field helpers string[] Helpers used, sorted.
---@field triggers Nodal.Trigger[] In node-id order.
---@field effects Nodal.Effect[] In node-id order.
---@field settings Nodal.Settings
---@field blocks table<string, Nodal.BlockDef> Every block the program uses, custom ones included.

---What one node evaluated to. Exactly one of `value` and `error` is set, unless the value is nil.
---@class Nodal.NodeValue
---@field value? any
---@field error? string

---Number formatting the evaluator uses for money and percent outputs. The editor passes
---Intl-backed versions, and tests use the built-in fallback.
---@class Nodal.Formatters
---@field money fun(n: number, settings: Nodal.Settings): string
---@field percent fun(n: number, settings: Nodal.Settings): string

---@class Nodal.Emitted
---@field source string The TypeScript module.
---@field lines table<integer, string> Line number, from 1, to the node id it came from.

---------------------------------------------------------------------------------------------
-- proteus.nodal.core modules. Each file in plugins/nodal/proteus.nodal.core returns one of these.
---------------------------------------------------------------------------------------------

---@class Nodal.TypesModule
---@field list Nodal.TypeInfo[]
---@field info fun(t: Nodal.PortType): Nodal.TypeInfo
---@field compatible fun(from: Nodal.PortType, to: Nodal.PortType): boolean
---@field zero fun(t: Nodal.PortType): any

---@class Nodal.FormulaModule
---Parses a formula and checks it against the input types. Returns the typed AST.
---@field parse fun(source: string, inputs: table<string, Nodal.PortType>): Nodal.Ast?, Nodal.Refusal?
---Every helper and function a formula may call.
---@field functions fun(): string[]

---@class Nodal.BlocksModule
---@field catalog fun(): Nodal.BlockDef[] The built-in blocks, parsed and checked.
---@field get fun(doc: Nodal.Doc, id: string): Nodal.BlockDef? Built-in or custom.
---@field custom fun(spec: { title: string, description?: string, inputs: Nodal.PortDef[], output?: Nodal.PortType, formula: string }): Nodal.CustomBlockDef?, Nodal.Refusal?
---@field categories fun(): { id: Nodal.Category, title: string, color: string }[]
---Every output of a block, the main one first with the key `'value'`. Its label is the
---block's `main` label, or empty.
---@field outputs fun(def: Nodal.BlockDef): Nodal.PortDef[]
---@field helper_source fun(name: string, settings: Nodal.Settings): string? The TypeScript source of a helper.

---Every operation returns a new document, or nil and a refusal. Documents are never changed.
---@class Nodal.GraphModule
---@field new_doc fun(settings?: Nodal.Settings): Nodal.Doc
---@field add_node fun(doc: Nodal.Doc, block: string, position: Nodal.Position): Nodal.Doc?, Nodal.Refusal|string Returns the new node id second on success.
---Removes the node, its wires, and its box in the layout.
---@field remove_node fun(doc: Nodal.Doc, id: string): Nodal.Doc?, Nodal.Refusal?
---Connects a source output to a target input. `output` is the source output's key, nil for `'value'`.
---An input read only when an event fires, such as any input of a block with an event
---input, does not count toward loops: a Set block may write what it reads.
---@field connect fun(doc: Nodal.Doc, from: string, to: string, input: string, output?: string): Nodal.Doc?, Nodal.Refusal?
---@field can_connect fun(doc: Nodal.Doc, from: string, to: string, input: string, output?: string): boolean, Nodal.Refusal?
---@field disconnect fun(doc: Nodal.Doc, to: string, input: string): Nodal.Doc?, Nodal.Refusal?
---@field rename fun(doc: Nodal.Doc, id: string, name: string): Nodal.Doc?, Nodal.Refusal?
---@field set_literal fun(doc: Nodal.Doc, id: string, key: string, value: any): Nodal.Doc?, Nodal.Refusal?
---@field set_config fun(doc: Nodal.Doc, id: string, key: string, value: any): Nodal.Doc?, Nodal.Refusal?
---@field move fun(doc: Nodal.Doc, id: string, position: Nodal.Position): Nodal.Doc?, Nodal.Refusal?
---Puts a new layout in place, or none for nil. The root is a column with the id `'root'`.
---Container ids are unique and not empty. A node box names a node the app shows (a `ui.*`
---component other than `ui.menu`, an input, a button, an output or status text), each at
---most once. Numbers are finite and not negative, and unknown fields are refused. A refusal is
---`'invalid-value'` with `{ key = 'layout', reason, field }`, such as `reason = 'unknown-node'`.
---@field set_layout fun(doc: Nodal.Doc, layout: Nodal.LayoutBox?): Nodal.Doc?, Nodal.Refusal?
---@field add_block fun(doc: Nodal.Doc, block: Nodal.CustomBlockDef): Nodal.Doc?, Nodal.Refusal?
---Replaces the custom block with the same id. Wires into inputs it no longer has are removed,
---and so are values set on them and wires from outputs it no longer has. A wire its new types
---cannot carry is refused. A code block (`kind = 'code'`) is made again from its `source`.
---@field update_block fun(doc: Nodal.Doc, block: Nodal.CustomBlockDef): Nodal.Doc?, Nodal.Refusal?
---@field node fun(doc: Nodal.Doc, id: string): Nodal.Node?
---@field edge_into fun(doc: Nodal.Doc, to: string, input: string): Nodal.Edge?
---The reference for a node's output: the node id for `'value'` or nil, else `'<node>.<key>'`.
---@field ref fun(node: string, output?: string): string
---The value an unconnected input takes: its literal, else the default, else the type's zero.
---@field literal fun(doc: Nodal.Doc, node: Nodal.Node, key: string): any
---The type of a node's output, or nil for output blocks.
---@field output_type fun(doc: Nodal.Doc, node: Nodal.Node): Nodal.PortType?
---Checks all five invariants, and the layout. Returns nil when they hold.
---@field check fun(doc: Nodal.Doc): Nodal.Refusal?

---@class Nodal.HistoryModule
---@field new fun(doc: Nodal.Doc): Nodal.History
---Records a new document. Pushes with the same `coalesce` key within 500 ms replace the last entry.
---@field push fun(h: Nodal.History, doc: Nodal.Doc, now: number, coalesce?: string): Nodal.History
---@field undo fun(h: Nodal.History): Nodal.History?, Nodal.Refusal?
---@field redo fun(h: Nodal.History): Nodal.History?, Nodal.Refusal?

---@class Nodal.CompileModule
---@field compile fun(doc: Nodal.Doc): Nodal.Program
---Turns a display name into an identifier: "Free shipping" becomes `freeShipping`.
---@field ident fun(name: string): string

---@class Nodal.EvaluateModule
---Runs the program. Never raises. `inputs` are values by parameter node id, and default to
---each input node's own value. Returns a value or an error for every node, and the outputs
---by result key.
---@field evaluate fun(program: Nodal.Program, inputs?: table<string, any>, formatters?: Nodal.Formatters): table<string, Nodal.NodeValue>, table<string, any>
---The built-in formatters, used when none are passed.
---@field formatters Nodal.Formatters
---The values an effect's inputs take, given the values evaluate returned.
---@field effect_args fun(program: Nodal.Program, values: table<string, Nodal.NodeValue>, effect: Nodal.Effect): table<string, any>
---Evaluates with state: `state` holds values by reference for variables and for outputs that
---blocks report at run time, such as a Program's `line`. Missing ones take their start value.
---@field evaluate_state fun(program: Nodal.Program, inputs?: table<string, any>, state?: table<string, any>, formatters?: Nodal.Formatters): table<string, Nodal.NodeValue>, table<string, any>
---Like evaluate_state, but each step is worked out only when its value, or a value that needs
---it, is read. The runtime uses it, so a step only a Set block reads costs nothing until then.
---@field evaluate_lazily fun(program: Nodal.Program, inputs?: table<string, any>, state?: table<string, any>, formatters?: Nodal.Formatters): table<string, Nodal.NodeValue>, table<string, any>

---Emits the pure part of the program, `run(inputs)`. Event and app blocks are left out.
---@class Nodal.EmitModule
---@field emit fun(program: Nodal.Program, source_name?: string): Nodal.Emitted

---@class Nodal.PluginOptions
---@field id string The plugin id, such as `'tip.calculator'`.
---@field name string
---@field description? string
---@field placement 'panel'|'bottom'|'app' `'panel'` adds a panel to the right dock, and `'bottom'` one to the bottom dock. `'app'` fills the main area, or the whole window when there is no layout.
---@field source_name? string The graph file, named in the header comment.
---@field version? string The plugin's version, `'1.0.0'` when left out. The runtime plugin declares it.
---@field graph_file? string The graph's file name beside init.lua, such as `'clock.ndg'`. A runtime plugin reads it when it starts.

---Emits a complete Proteus plugin: the logic, a form for the inputs, the results, and the
---triggers and effects wired into the app. The source follows the project's StyLua, selene
---and strict LuaLS rules.
---@class Nodal.PluginEmitModule
---@field emit fun(program: Nodal.Program, opts: Nodal.PluginOptions): Nodal.Emitted
---The plugins the emitted plugin needs, for a profile that runs it as an app.
---@field profile_plugins fun(program: Nodal.Program, opts: Nodal.PluginOptions): string[]
---False when the program uses what only the runtime can run: variables, Set, flow, system,
---file, net, UI and code blocks, events from outputs other than `'value'`, or a console
---output. Such graphs build as a plugin that runs the graph with `Nodal.RuntimeModule`
---instead. For them `emit` returns a stub plugin that does nothing.
---@field supported fun(program: Nodal.Program): boolean
---The permissions a graph's blocks need when it runs as a plugin that does not ship with the app.
---@field permissions_of fun(graph: string): string[]
---A plugin that reads the graph file beside it, `opts.graph_file`, and runs it with the Nodal
---runtime, as the preview does. Every graph plugin is built this way. `graph` is the file's
---text, for the permissions its blocks need.
---@field runtime fun(graph: string, opts: Nodal.PluginOptions): string

---------------------------------------------------------------------------------------------
-- The runtime: a graph running as a live app
---------------------------------------------------------------------------------------------

---What a finished command reports.
---@class Nodal.RunResult
---@field code integer
---@field stdout string
---@field stderr string

---What a running program reports.
---@class Nodal.ProcessEvents
---@field stdout fun(line: string) One line the program printed.
---@field stderr fun(line: string) One line of its error output.
---@field exit fun(code: integer?)

---@class Nodal.ProcessHandle
---@field write fun(text: string) Writes the text and a line break to the program's input.
---@field stop fun()

---A command a graph adds to the app: a palette entry, with an optional shortcut and menu.
---@class Nodal.CommandSpec
---@field id string Unique within the graph, such as `'nodal.n4'`.
---@field title string
---@field key? string Such as `'ctrl+shift+n'`.
---@field menu? string A menu to list it in, such as `'File'`.
---@field icon? string

---A setting a graph defines. It shows on the settings screen like any plugin's.
---@class Nodal.SettingSpec
---@field key string Such as `'notes.folder'`.
---@field title string
---@field type 'text'|'number'|'boolean'
---@field default any
---@field description? string

---A theme a graph adds. It shows in the theme picker like any theme.
---@class Nodal.ThemeSpec
---@field id string
---@field name string
---@field dark boolean
---@field vars table<string, string> CSS variables without `--`, such as `{ bg = '#101418', accent = '#4f9cff' }`.

---@class Nodal.RunOptions
---@field cwd? string
---@field stdin? string

---@class Nodal.HttpRequest
---@field method string Such as `'GET'` or `'POST'`.
---@field url string
---@field headers table<string, string>
---@field body? string

---@class Nodal.HttpResponse
---@field status integer 0 when there was no answer at all.
---@field headers table<string, string> Names in lower case.
---@field body string
---@field error? string Why there was no answer, such as a bad address.

---What the runtime needs from the app around it. The Nodal preview and built plugins pass
---the real thing. Tests pass fakes.
---@class Nodal.Host
---@field notify fun(text: string, kind: string)
---@field log fun(text: string)
---@field clipboard fun(text: string)
---Runs a program to the end. A program that cannot start reports code -1 and the reason in stderr.
---@field run fun(program: string, args: string[], opts: Nodal.RunOptions, done: fun(result: Nodal.RunResult))
---Starts a program that keeps running. One that cannot start reports a line on stderr, then exit.
---@field process fun(program: string, args: string[], cwd: string?, on: Nodal.ProcessEvents): Nodal.ProcessHandle
---@field http fun(request: Nodal.HttpRequest, done: fun(response: Nodal.HttpResponse))
---Folder entries, names only, folders ending in `/`. nil when the folder cannot be read.
---@field list_folder fun(path: string, done: fun(names: string[]?))
---@field read_file fun(path: string, done: fun(text: string?))
---@field write_file fun(path: string, text: string, done: fun(ok: boolean))
---Asks the app to act on a UI component, such as starting the program in a `ui.terminal`
---(`'start'`, `'restart'`, `'stop'`) or typing text into it (`'send'`, with the text).
---The app reports back with `Runtime.input`, such as `input (node, { running = false, code = 0 }, 'exited')`.
---@field component fun(node: string, action: string, value?: any)
---Adds a command. Returns a function that removes it. Optional: older hosts lack it.
---@field command? fun(spec: Nodal.CommandSpec, run: fun()): fun()
---Defines a setting and returns its value now. `changed` runs when the user changes it.
---@field setting? fun(spec: Nodal.SettingSpec, changed: fun(value: any)): any
---Adds a theme. Returns a function that removes it.
---@field theme? fun(spec: Nodal.ThemeSpec): fun()
---Does something in the app: open a file in the editor, open a web address, run a command
---by id, or switch to a profile by id.
---@field act? fun(action: 'file'|'url'|'command'|'profile', target: string)
---Removes a file. `done` gets whether it worked.
---@field delete_file? fun(path: string, done: fun(ok: boolean))
---Asks for a line of text. `done` gets the text, or nil when the user cancels.
---@field ask? fun(prompt: string, value: string, done: fun(text: string?))
---Asks a yes or no question. `done` gets true for yes and false for no.
---@field confirm? fun(message: string, yes: string, danger: boolean, done: fun(yes: boolean))
---Shows a list to pick from. `labels` are what each item shows. `done` gets the position of
---the item picked, from 1, or nil when the user cancels.
---@field pick? fun(prompt: string, labels: string[], done: fun(position: integer?))
---Renames or moves a file. `done` gets whether it worked.
---@field rename_file? fun(from: string, to: string, done: fun(ok: boolean))
---The time now, in milliseconds since 1970. Optional: without it the runtime reads Lua's clock.
---@field now? fun(): number
---@field after fun(ms: number, fn: fun()): fun() Returns a cancel function.
---@field every fun(ms: number, fn: fun()): fun() Returns a cancel function.
---@field changed fun() Values changed, so the UI should show them again.

---A graph running as an app: its inputs, its state, its events and its effects.
---@class Nodal.Runtime
---@field program Nodal.Program
---Values by reference, as evaluate returns them, with state applied.
---@field values fun(): table<string, Nodal.NodeValue>
---Formatted results by result key.
---@field outputs fun(): table<string, any>
---The value of an input block, such as text typed in a field.
---@field set_input fun(node: string, value: any)
---Fires an event output: a button's click, or `'submitted'` when Enter is pressed in a text field.
---@field fire fun(node: string, output?: string)
---What the user did to a UI component: new values for its outputs, then the event to fire.
---For example `input ('n4', { value = 'ls' }, 'changed')` as the user types in a text box.
---@field input fun(node: string, changes: table<string, any>, event?: string)
---The current values of a block's inputs, by key, such as a text view's `text` or a list
---view's `items`. The app reads it to draw each UI component.
---@field args fun(node: string): table<string, any>
---Starts timers and fires start events. Then each `ui.terminal` set to start on its own gets
---`host.component (node, 'start')`.
---@field start fun()
---Cancels timers and waits, stops running programs, and sends each terminal `'stop'`.
---@field stop fun()
---Swaps in a changed program and keeps what still fits: input values, variables, what
---components report, running programs.
---@field update fun(program: Nodal.Program)
---The last problem an effect had, by node id, such as a command that would not start.
---@field problems fun(): table<string, string>

---@class Nodal.RuntimeModule
---@field new fun(program: Nodal.Program, host: Nodal.Host, formatters?: Nodal.Formatters): Nodal.Runtime

---------------------------------------------------------------------------------------------
-- The interface: the graph's inputs and outputs, written as a Lua table
---------------------------------------------------------------------------------------------

---@alias Nodal.InputKind
---| 'number' # A number field. The block `input.number`.
---| 'slider' # A number on a slider. The block `input.slider`.
---| 'text' # A text field. The block `input.text`.
---| 'toggle' # A yes or no switch. The block `input.toggle`.

---One input of the app.
---@class Nodal.InterfaceInput
---@field id? string The block it stands for, such as `'n1'`. Leave it out to add a new input.
---@field name string What the field is called, and the name the code uses.
---@field kind Nodal.InputKind
---@field value? number|string|boolean What the field starts at.
---@field min? number Sliders only.
---@field max? number Sliders only.
---@field step? number Sliders only. Above 0.

---One result the app shows.
---@class Nodal.InterfaceOutput
---@field id? string The output block it stands for. Leave it out to add a new output.
---@field name string What the result is called, and its field in `Outputs`.
---@field from? string The block whose value it shows: its name, or its id when names repeat.
---@field value? number|string|boolean A fixed value, used when `from` is left out.
---@field format? Nodal.OutputFormat `'plain'` when left out.

---Everything a user sees of the app's logic: what goes in and what comes out.
---Entries left out are removed from the graph. Everything between stays as wired.
---@class Nodal.Interface
---@field inputs Nodal.InterfaceInput[]
---@field outputs Nodal.InterfaceOutput[]
---Where each entry starts in the text, by field path such as `'inputs[2]'` or
---`'inputs[2].kind'`. Filled in by `parse`, so a refusal can point at a line.
---@field lines? table<string, integer>

---@alias Nodal.InterfaceReason
---| 'shape' # A field has the wrong type or is missing. detail: { field, expected }
---| 'unknown-field' # detail: { field }
---| 'unknown-id' # No block has this id, or it is the wrong kind of block. detail: { field, id }
---| 'repeated-id' # detail: { field, id }
---| 'unknown-source' # No block has this name or id. detail: { field, name }
---| 'unclear-source' # Several blocks have this name. detail: { field, name, ids }

---Turns the graph's inputs and outputs into a Lua table and back. The text is read as data by
---a small parser: nothing in it runs, and only tables, strings, numbers, booleans and nil exist.
---@class Nodal.InterfaceModule
---@field describe fun(doc: Nodal.Doc): Nodal.Interface
---The describe table as Lua source, with a `---@type Nodal.Interface` line.
---@field source fun(doc: Nodal.Doc): string
---@field parse fun(text: string): Nodal.Interface?, Nodal.Refusal?
---Changes the graph to match. Graph refusals, such as `'name-taken'`, come back with a
---`field` added to their detail.
---@field apply fun(doc: Nodal.Doc, spec: Nodal.Interface): Nodal.Doc?, Nodal.Refusal?

---------------------------------------------------------------------------------------------
-- A block written as a Lua file: blocks/<name>.ndb.lua
---------------------------------------------------------------------------------------------

---One input or output of a block written in a file.
---@class Nodal.CodeBlockPort
---@field key string The name `run` and formulas use, such as `'amount'`.
---@field label? string What the block shows. The key when left out.
---@field type Nodal.PortType `'number'`, `'text'`, `'boolean'`, `'list'`, `'record'` or `'any'`.
---@field default? any An input's value while nothing is connected.
---@field formula? string An output of a formula block: what it works out, such as `'amount * rate / 100'`.

---A block written as a Lua file. Give it a `run` function, or a formula on each output.
---@class Nodal.CodeBlock
---@field title string What the block is called, such as `'Split name'`.
---@field description? string One line on what it does.
---@field icon? string A Lucide icon name, such as `'scissors'`.
---@field inputs Nodal.CodeBlockPort[]
---@field outputs Nodal.CodeBlockPort[] The first is the main output.
---Works out the outputs from the inputs. Return a table with one field per output key.
---With a single output, returning the value itself works too. It must not wait or loop forever.
---@field run? fun(input: table<string, any>): any

---Loads and writes blocks kept as `.ndb.lua` files. The file is real Lua, run in a small
---sandbox with the string, table, math and utf8 libraries and nothing that reaches outside.
---@class Nodal.CodeBlockModule
---Loads a block file. A refusal (`'invalid-block'`) carries the line when there is one.
---@field load fun(source: string, file?: string): Nodal.CustomBlockDef?, Nodal.Refusal?
---The file text for a block: a formula block as formulas, a code block as its own source.
---@field source fun(block: Nodal.CustomBlockDef): string
---A new block file to start from, with a `run` function and two outputs.
---@field starter fun(title: string): string

---------------------------------------------------------------------------------------------
-- A custom block, written as a Lua table
---------------------------------------------------------------------------------------------

---One input of a custom block.
---@class Nodal.BlockSpecInput
---@field key string The name the formula uses, such as `'amount'`.
---@field label? string What the block shows. The key when left out.
---@field type Nodal.PortType `'number'`, `'text'`, `'boolean'` or `'any'`.
---@field default? number|string|boolean The value while nothing is connected.

---A custom block as a Lua table: what Make block builds from.
---@class Nodal.BlockSpec
---@field title string What the block is called, such as `'Tax'`.
---@field description? string One line on what it does.
---@field inputs Nodal.BlockSpecInput[]
---@field output? Nodal.PortType What it gives. Worked out from the formula when left out.
---@field formula string What it works out, such as `'amount * rate / 100'`.

---Turns a custom block into a Lua table and back. The text is read as data: nothing in it runs.
---@class Nodal.BlockSourceModule
---The block as Lua source, with a `---@type Nodal.BlockSpec` line. nil gives a starter block.
---@field source fun(block?: Nodal.CustomBlockDef): string
---Reads the text and makes the block, as `blocks.custom` does. A refusal carries the line it
---is about, and a column for a problem inside the formula.
---@field build fun(text: string): Nodal.CustomBlockDef?, Nodal.Refusal?
---The line of a top-level field, such as `'title'`, in text that may not read yet.
---@field line_of fun(text: string, field: string): integer?

---@class Nodal.JsonModule
---@field encode fun(value: any, key_order?: string[]): string Deterministic, pretty, keys in a fixed order.
---@field decode fun(text: string): any, string?

---@class Nodal.FileModule
---@field save fun(doc: Nodal.Doc): string Byte-identical for equal documents.
---@field load fun(text: string): Nodal.Doc?, Nodal.Refusal?

---@class Nodal.FixturesModule
---@field pricing fun(): Nodal.Doc The acceptance fixture from ARCHITECTURE §2.
---@field tips fun(): Nodal.Doc A tip calculator that uses a button, a message and status bar text.
---@field terminal fun(): Nodal.Doc A real terminal: a `ui.terminal` block, with a shell picker and a restart button.
---@field pipes fun(): Nodal.Doc A terminal built from plain blocks: a Program running PowerShell, text blocks that spot the ready marker, and UI components.
---@field split_name fun(): Nodal.Doc A graph using a code block with two outputs.
---@field notes fun(): Nodal.Doc Markdown notes: a list of files, a code editor, a preview, commands, a right-click menu and a folder setting.
---@field todo fun(): Nodal.Doc A to-do list kept in a list variable and saved to a file.
---@field http fun(): Nodal.Doc An HTTP client: an address, a method, a Send button, and the answer as formatted JSON.
---@field kanban fun(): Nodal.Doc Boards of cards in columns, saved as JSON files, with a card panel, labels, archive and undo.

---The `nodal` service: every core module in one table.
---@class Nodal.Core
---@field types Nodal.TypesModule
---@field formula Nodal.FormulaModule
---@field blocks Nodal.BlocksModule
---@field graph Nodal.GraphModule
---@field history Nodal.HistoryModule
---@field compile Nodal.CompileModule
---@field evaluate Nodal.EvaluateModule
---@field emit Nodal.EmitModule TypeScript.
---@field emit_lua Nodal.EmitModule A Lua module.
---@field emit_plugin Nodal.PluginEmitModule A Proteus plugin.
---@field json Nodal.JsonModule
---@field file Nodal.FileModule
---@field fixtures Nodal.FixturesModule
---@field interface Nodal.InterfaceModule The inputs and outputs as a Lua table.
---@field block_source Nodal.BlockSourceModule A custom block as a Lua table.
---@field code_block Nodal.CodeBlockModule Blocks written as `.ndb.lua` files.
---@field runtime Nodal.RuntimeModule Runs a graph as a live app.

---------------------------------------------------------------------------------------------
-- The document store (proteus.nodal.state)
---------------------------------------------------------------------------------------------

---@class Nodal.Snapshot
---@field doc Nodal.Doc
---@field revision integer Goes up by one with every change.
---@field program Nodal.Program
---@field values table<string, Nodal.NodeValue> By node id.
---@field outputs table<string, any> By result key.
---@field emitted Nodal.Emitted TypeScript.
---@field emitted_lua Nodal.Emitted
---@field emitted_plugin Nodal.Emitted

---The open document, its history, the selection and the file it lives in.
---Every change goes through `apply`, which runs a core graph operation, records it in the
---history, recompiles, re-evaluates and sends `nodal:changed`.
---@class Nodal.Store
---@field snapshot fun(): Nodal.Snapshot
---Runs a `Nodal.GraphModule` operation on the current document. Returns the refusal when
---there is one. `coalesce` merges quick repeats, such as typing in a field, into one undo step.
---@field apply fun(op: string, args: any[], coalesce?: string): Nodal.Refusal?, any
---Shows a refusal to the user in plain words.
---@field explain fun(refusal: Nodal.Refusal): string
---@field undo fun(): Nodal.Refusal?
---@field redo fun(): Nodal.Refusal?
---@field selection fun(): string?
---@field select fun(id: string?)
---@field path fun(): string? The workspace path of the open file.
---@field new fun()
---@field open fun(path: string): Nodal.Refusal?
---@field save fun(path?: string)
---@field dirty fun(): boolean
---True when the graph is what the user is working on: always in the Nodal profile, and
---while the graph's tab is in front inside the editor.
---@field active fun(): boolean
---True inside another profile, such as the editor, where the graph is one tab among others.
---@field embedded boolean
---Closes the graph. Only inside the editor.
---@field close fun()
---The plugin id the graph builds as, from its file name, such as `'pricing'`.
---@field plugin_id fun(): string
---Puts a whole new document in place as one undo step, such as one from `interface.apply`.
---@field replace fun(doc: Nodal.Doc, coalesce?: string): Nodal.Refusal?

---------------------------------------------------------------------------------------------
-- A graph as a live app (proteus.nodal.app)
---------------------------------------------------------------------------------------------

---@class Nodal.AppOptions
---@field status_bar? boolean Status text goes to the window's status bar, as in a built plugin. Otherwise the app shows it itself.
---@field on_problem? fun(node: string, text: string)
---Runs when the user changes an input field, so a preview can write the value back to the graph.
---@field on_input? fun(node: string, value: any)
---A preview: commands go in the palette only, without shortcuts or menus, so they never take
---the editor's own keys.
---@field preview? boolean
---False leaves the app still: no timers, programs or start events. For a designer.
---@field start? boolean
---Design mode picked a box: a UI block's node id, `'layout:' .. id` for a container, or nil.
---@field on_select? fun(node: string?)
---Design mode changed the layout: moved, sized or added a box. Save it with `set_layout`.
---@field on_layout? fun(layout: Nodal.LayoutBox)

---One running app: its element and the runtime behind it.
---@class Nodal.AppHandle
---@field el Proteus.El
---@field runtime Nodal.Runtime
---Swaps in a changed program and keeps what still fits, such as a shell and its output.
---@field update fun(program: Nodal.Program)
---Stops timers and shells.
---@field stop fun()
---Turns design mode on or off. In design mode the app takes no input: blocks are moved,
---sized and picked instead.
---@field set_design fun(on: boolean)
---Shows which block is picked, as when it is selected on the canvas.
---@field set_picked fun(node: string?)

---Small helpers for editing a layout tree. A reference is a UI block's node id, or
---`'layout:' .. id` for a container.
---@class Nodal.LayoutTools
---@field copy fun(box: Nodal.LayoutBox): Nodal.LayoutBox A deep copy.
---@field find fun(root: Nodal.LayoutBox, ref: string): Nodal.LayoutBox?, Nodal.LayoutBox? The box, and the container it sits in.
---@field take fun(root: Nodal.LayoutBox, ref: string): Nodal.LayoutBox? Removes a box and returns it.
---@field new_id fun(root: Nodal.LayoutBox): string A container id no box uses yet.

---Runs a graph as a live app, with real commands, shells, files and messages. The Nodal
---preview and every built plugin use it, so both behave the same.
---@class Nodal.AppService
---@field mount fun(program: Nodal.Program, opts?: Nodal.AppOptions): Nodal.AppHandle
---@field layout Nodal.LayoutTools
---Loads a graph file's text and mounts it.
---@field mount_text fun(text: string, opts?: Nodal.AppOptions): Nodal.AppHandle?, Nodal.Refusal?

---------------------------------------------------------------------------------------------
-- The canvas (proteus.nodal.canvas)
---------------------------------------------------------------------------------------------

---@class Nodal.Canvas
---@field center fun(): Nodal.Position The middle of the visible area, in graph coordinates.
---@field fit fun() Frames every block.
---@field tidy fun() Arranges blocks in layered columns, outputs last, then fits.
---@field zoom fun(factor: number) Zooms about the middle of the view.
---The graph point under a screen point, or nil when the point is not over the canvas.
---The next block added lands there, as when a block is dragged in from the library.
---@field drop_at fun(x: number, y: number): Nodal.Position?
