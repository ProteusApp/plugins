---@meta

-- Types for the shader builder: the pure core in plugins/shader/shader.core, served as the
-- `shader` service, and the services of the plugins around it.

---@alias Shader.Lang 'glsl'|'wgsl'

---A value a wire carries.
---@alias Shader.Type 'float'|'vec2'|'vec3'|'vec4'

---A port's type in the catalog. `gen` takes the widest type wired into any `gen` input of
---the node. `any` keeps the type wired in.
---@alias Shader.PortType Shader.Type|'gen'|'any'

---A uniform's type in a buffer or a control.
---@alias Shader.UniformType 'float'|'vec2'|'vec3'|'vec4'|'int'|'uint'|'bool'

---What an unwired input reads when it has one: the UV, the square UV, or the pixel position.
---@alias Shader.Builtin 'uv'|'suv'|'frag'

---@class Shader.Category
---@field id string
---@field title string
---@field color string A CSS colour for its nodes.

---@class Shader.PortDef
---@field key string
---@field label string
---@field type Shader.PortType
---@field default number[] The numbers an unwired input uses.
---@field builtin? Shader.Builtin What an unwired input reads instead of numbers.
---@field color? boolean Its numbers are edited as a colour.

---@class Shader.EmitContext
---@field lang Shader.Lang
---@field T Shader.Type The node's `gen` type.
---@field inputs table<string, string> Each input's expression, already of its type.
---@field types table<string, Shader.Type> Each input's type.
---@field settings table<string, any> Settings with defaults filled in.

---@class Shader.OutputDef
---@field key string
---@field label string
---@field type Shader.PortType|fun(settings: table<string, any>): Shader.Type
---@field glsl string|fun(ctx: Shader.EmitContext): string
---@field wgsl? string|fun(ctx: Shader.EmitContext): string The GLSL one when nil.
---@field hidden? boolean A value the other outputs share, not shown.

---@alias Shader.SettingKind 'number'|'int'|'select'|'text'|'name'|'code'|'color'|'vector'

---@class Shader.SettingDef
---@field key string
---@field label string
---@field kind Shader.SettingKind
---@field default any
---@field options? string[] For `select`.
---@field min? number For `int`.
---@field max? number For `int`.
---@field size? integer For `vector`: how many numbers.

---@class Shader.NodeDef
---@field type string
---@field title string
---@field category string
---@field description string
---@field inputs Shader.PortDef[]
---@field outputs Shader.OutputDef[]
---@field settings Shader.SettingDef[]
---@field helpers? string[] Helper functions the code calls.
---@field unique? boolean A graph has at most one.

---A node as the catalog writes it: inputs and settings may be left out.
---@class Shader.NodeSpec
---@field type string
---@field title string
---@field category string
---@field description string
---@field inputs? Shader.PortDef[]
---@field outputs Shader.OutputDef[]
---@field settings? Shader.SettingDef[]
---@field helpers? string[]
---@field unique? boolean

---@class Shader.Helper
---@field glsl string
---@field wgsl string
---@field needs? string[]

---A node in a document.
---@class Shader.Node
---@field id string
---@field type string
---@field x number
---@field y number
---@field inputs table<string, number[]> Numbers for unwired inputs.
---@field settings table<string, any>

---A wire from an output to an input.
---@class Shader.Edge
---@field from string
---@field output string
---@field to string
---@field input string

---A shader graph, as the *.shader.json file holds it.
---@class Shader.Doc
---@field format integer
---@field name string
---@field preview? Shader.Lang The language the Preview runs.
---@field nodes Shader.Node[]
---@field edges Shader.Edge[]
---@field canvas? Shader.CanvasData The canvas's frames and reroute points. The compiler never reads it.

---A titled box on the canvas behind nodes. Moving it moves the nodes inside.
---@class Shader.Frame
---@field id string Such as `'f1'`.
---@field x number
---@field y number
---@field w number Above 0.
---@field h number Above 0.
---@field title string
---@field color? string Such as `'#4f8ef7'`.

---The points the wire into one input passes through, in order from its source.
---@class Shader.Route
---@field to string
---@field input string
---@field points { x: number, y: number }[] At least one, at most 32.

---@class Shader.CanvasData
---@field frames Shader.Frame[]
---@field routes Shader.Route[]

---Nodes copied from a graph, with the wires between them, so they paste into any graph.
---@class Shader.Fragment
---@field nodes Shader.Node[]
---@field edges Shader.Edge[]
---@field frames Shader.Frame[]
---@field routes table<string, { x: number, y: number }[]> Reroute points by wire id.

---@class Shader.LayoutField
---@field name string
---@field type Shader.UniformType
---@field offset integer Bytes from the start of the buffer.
---@field builtin? string `resolution`, `time`, `frame` or `mouse`: the preview sets it.

---A WGSL uniform struct laid out in its buffer.
---@class Shader.Layout
---@field fields Shader.LayoutField[]
---@field size integer Bytes.

---A value the Preview panel shows a control for.
---@class Shader.Uniform
---@field key string The name the value is kept under.
---@field glsl? string Its name in GLSL.
---@field offset? integer Its place in the WGSL buffer.
---@field type Shader.UniformType
---@field value number[]
---@field min number
---@field max number
---@field step? number
---@field color boolean
---@field node? string The Parameter node it comes from.

---A uniform's control, from the notes in its comment.
---@class Shader.Notes
---@field min number
---@field max number
---@field step? number
---@field value number[]
---@field color boolean

---What the preview runs.
---@class Shader.Program
---@field language Shader.Lang
---@field source string The GLSL fragment shader, or the WGSL module.
---@field vertex? string The GLSL vertex shader.
---@field vertex_entry? string WGSL.
---@field fragment_entry? string WGSL.
---@field uniforms Shader.Uniform[]
---@field layout? Shader.Layout WGSL.
---@field lines? table<integer, string> Line of `source` to the node that wrote it.
---@field offset integer Lines added above the user's first line.
---@field vertex_offset? integer Lines added above the vertex shader's first line.
---@field user_lines? integer How many lines the user wrote.
---@field shadertoy? boolean A Shadertoy `mainImage` shader.

---@class Shader.CompileError
---@field message string
---@field node? string
---@field line? integer From 1, in the user's text.
---@field column? integer From 1.
---@field severity? 'error'|'warning'
---@field stage? 'vertex'|'fragment'

---@class Shader.CompileResult
---@field ok boolean
---@field errors Shader.CompileError[]
---@field uniforms Shader.Uniform[]
---@field types table<string, table<string, Shader.Type>> Each node's input types.
---@field out_types table<string, table<string, Shader.Type>> Each node's output types.
---@field glsl Shader.Program
---@field wgsl Shader.Program

---@class Shader.History
---@field past Shader.Doc[]
---@field future Shader.Doc[]
---@field doc Shader.Doc
---@field last_key? string
---@field last_time? number

---@class Shader.TypesModule
---@field names Shader.Type[]
---@field is_type fun(t: any): boolean
---@field dim fun(t: Shader.Type): integer
---@field of_dim fun(n: integer): Shader.Type
---@field widest fun(list: Shader.Type[]): Shader.Type
---@field name fun(t: Shader.Type, lang: Shader.Lang): string
---@field number fun(n: number): string
---@field literal fun(values: number[]?, t: Shader.Type, lang: Shader.Lang): string
---@field convert fun(expr: string, from: Shader.Type, to: Shader.Type, lang: Shader.Lang): string

---@class Shader.NodesModule
---@field categories Shader.Category[]
---@field list Shader.NodeDef[]
---@field dialect fun(text: string, lang: Shader.Lang): string
---@field get fun(type_id: string): Shader.NodeDef?
---@field category fun(id: string): Shader.Category?
---@field setting fun(def: Shader.NodeDef, settings: table<string, any>?, key: string): any
---@field settings_of fun(def: Shader.NodeDef, settings: table<string, any>?): table<string, any>
---@field output_type fun(def: Shader.NodeDef, out: Shader.OutputDef, settings: table<string, any>?): Shader.PortType
---@field visible_outputs fun(def: Shader.NodeDef): Shader.OutputDef[]
---@field input fun(def: Shader.NodeDef, key: string): Shader.PortDef?
---@field output fun(def: Shader.NodeDef, key: string): Shader.OutputDef?

---A node as the catalog writes it: inputs and settings may be left out.
---@class Shader.NodeSpec
---@field type string
---@field title string
---@field category string
---@field description string
---@field inputs? Shader.PortDef[]
---@field outputs Shader.OutputDef[]
---@field settings? Shader.SettingDef[]
---@field helpers? string[]
---@field unique? boolean

---@class Shader.HelpersModule
---@field all table<string, Shader.Helper>
---@field closure fun(names: string[]): string[]
---@field sources fun(names: string[], lang: Shader.Lang): string[]

---@class Shader.GraphModule
---@field FORMAT integer
---@field copy fun(value: any): any
---@field node fun(doc: Shader.Doc, id: string): Shader.Node?, integer?
---@field edge_into fun(doc: Shader.Doc, to: string, input: string): Shader.Edge?, integer?
---@field next_id fun(doc: Shader.Doc): string
---@field new fun(name?: string): Shader.Doc
---@field add_node fun(doc: Shader.Doc, type_id: string, x: number, y: number): Shader.Doc?, string
---@field remove_nodes fun(doc: Shader.Doc, ids: string[]): Shader.Doc?, string?
---@field move fun(doc: Shader.Doc, moves: table<string, { x: number, y: number }>): Shader.Doc
---@field why_not fun(doc: Shader.Doc, from: string, output: string, to: string, input: string): string?
---@field connect fun(doc: Shader.Doc, from: string, output: string, to: string, input: string): Shader.Doc?, string?
---@field disconnect fun(doc: Shader.Doc, to: string, input: string): Shader.Doc?, string?
---@field set_input fun(doc: Shader.Doc, id: string, key: string, values: number[]?): Shader.Doc?, string?
---@field set_setting fun(doc: Shader.Doc, id: string, key: string, value: any): Shader.Doc?, string?
---@field duplicate fun(doc: Shader.Doc, ids: string[]): Shader.Doc?, string[]|string
---@field rename fun(doc: Shader.Doc, name: string): Shader.Doc
---@field parameter fun(doc: Shader.Doc, name: string): Shader.Node?
---@field wire_id fun(to: string, input: string): string
---@field set_canvas fun(doc: Shader.Doc, data: Shader.CanvasData?): Shader.Doc?, string?
---@field frames fun(doc: Shader.Doc): Shader.Frame[]
---@field routes fun(doc: Shader.Doc): table<string, { x: number, y: number }[]>
---@field with_canvas fun(doc: Shader.Doc, frames: Shader.Frame[], routes: table<string, { x: number, y: number }[]>): Shader.Doc
---@field next_frame_id fun(frames: Shader.Frame[]): string
---@field copy_nodes fun(doc: Shader.Doc, ids: string[], frame_ids?: string[]): Shader.Fragment
---@field paste fun(doc: Shader.Doc, fragment: Shader.Fragment, dx: number, dy: number): Shader.Doc?, string[], string[]
---@field insert fun(doc: Shader.Doc, id: string, wire: string): Shader.Doc?

---@class Shader.CompileModule
---@field GLSL_VERTEX string
---@field WGSL_VERTEX string
---@field BUILTIN_FIELDS { name: string, type: Shader.UniformType }[]
---@field bad_name fun(name: any): string?
---@field compile fun(doc: Shader.Doc): Shader.CompileResult

---@class Shader.LayoutModule
---@field sizes table<Shader.UniformType, { align: integer, size: integer }>
---@field reserved fun(word: string): boolean
---@field layout fun(fields: { name: string, type: Shader.UniformType }[]): Shader.Layout

---@class Shader.SourceModule
---@field GLSL_BUILTINS table<string, string>
---@field TEMPLATES { glsl: string, wgsl: string, shadertoy: string, vertex: string }
---@field kind_of fun(path: string): Shader.Lang?, ('fragment'|'vertex')?
---@field notes fun(comment: string, t: Shader.UniformType): Shader.Notes
---@field glsl_uniforms fun(text: string): Shader.Uniform[], table<string, boolean>, Shader.CompileError[]
---@field glsl_program fun(text: string, vertex?: string): Shader.Program, Shader.CompileError[]
---@field wgsl_uniforms fun(text: string): Shader.Layout?, Shader.Uniform[], Shader.CompileError[]
---@field wgsl_program fun(text: string): Shader.Program, Shader.CompileError[]
---@field program fun(lang: Shader.Lang, text: string, vertex?: string): Shader.Program, Shader.CompileError[]

---@class Shader.FileModule
---@field KIND string
---@field EXTENSION string
---@field array fun(t: table): table Marks a table to be written as a JSON array even when empty.
---@field encode fun(value: any): string
---@field save fun(doc: Shader.Doc): string
---@field decode fun(text: string): any, string?
---@field load fun(text: string): Shader.Doc?, string?

---@class Shader.HistoryModule
---@field new fun(doc: Shader.Doc): Shader.History
---@field push fun(h: Shader.History, doc: Shader.Doc, key?: string, now?: number)
---@field undo fun(h: Shader.History): boolean
---@field redo fun(h: Shader.History): boolean

---What a build writes files from.
---@class Shader.BuildInput
---@field name string
---@field glsl? Shader.Program
---@field wgsl? Shader.Program

---@class Shader.BuildModule
---@field stem fun(name: string): string
---@field files fun(input: Shader.BuildInput): table<string, string>

---@class Shader.ExamplesModule
---@field names string[]
---@field build fun(name: string): Shader.Doc?

---The `shader` service from `shader.core`.
---@class Shader.Core
---@field types Shader.TypesModule
---@field nodes Shader.NodesModule
---@field helpers Shader.HelpersModule
---@field graph Shader.GraphModule
---@field compile Shader.CompileModule
---@field layout Shader.LayoutModule
---@field source Shader.SourceModule
---@field file Shader.FileModule
---@field history Shader.HistoryModule
---@field examples Shader.ExamplesModule
---@field build Shader.BuildModule

---------------------------------------------------------------------------------------------
-- The plugins around the core
---------------------------------------------------------------------------------------------

---@alias Shader.DocKind 'graph'|'code'

---A shader open in the builder.
---@class Shader.OpenDoc
---@field path string Its workspace path.
---@field kind Shader.DocKind
---@field language Shader.Lang For a graph, the language the Preview runs.
---@field stage 'fragment'|'vertex' For code.
---@field title string
---@field text string For code: the text now.
---@field saved string The text last saved.
---@field dirty boolean
---@field version integer Goes up with each change.
---@field history? Shader.History For a graph: its document and undo.
---@field selection string[] For a graph: the picked nodes.
---@field values table<string, number[]> For code: the values the Preview's controls set.
---@field tab? Proteus.Tab

---The `shader.docs` service from `shader.docs`.
---@class Shader.Docs
---@field folder string Where new shaders go.
---@field extensions string[]
---@field kind_of fun(path: string): Shader.DocKind?
---@field register_opener fun(kind: Shader.DocKind, fn: fun(doc: Shader.OpenDoc): Proteus.El)
---@field open fun(path: string): Shader.OpenDoc?
---@field get fun(path: string): Shader.OpenDoc?
---@field active fun(): Shader.OpenDoc? The shader whose tab was in front last.
---@field list fun(): Shader.OpenDoc[]
---@field files fun(): string[] Every shader in shaders/, apart from builds.
---@field change fun(path: string, doc: Shader.Doc, key?: string) Records a new graph. Quick changes with the same key merge into one undo step.
---@field set_text fun(path: string, text: string)
---@field undo fun(path: string): boolean
---@field redo fun(path: string): boolean
---@field save fun(path: string): boolean
---@field select fun(path: string, ids: string[])
---@field compiled fun(path: string): Shader.CompileResult? A graph compiled, kept until it changes.
---@field program fun(path: string, lang?: Shader.Lang): Shader.Program?, Shader.CompileError[] What the Preview runs.
---@field set_language fun(path: string, lang: Shader.Lang)
---@field set_uniform fun(path: string, key: string, value: number[])
---@field new_graph fun(name?: string): Shader.OpenDoc?
---@field new_code fun(lang: Shader.Lang|'vertex', name?: string, template?: string): Shader.OpenDoc?

---The `shader.canvas` service from `shader.canvas`.
---@class Shader.CanvasService
---@field add fun(type_id: string): boolean Adds a node to the graph in front.
---@field fit fun()
---@field select fun(path: string, ids: string[])

---What a node shows beside the document.
---@class ShaderCanvas.NodeInfo
---@field ins table<string, Shader.Type>
---@field outs table<string, Shader.Type>
---@field linked table<string, boolean>
---@field used table<string, boolean>
---@field error? string
---@field gen? Shader.Type

---What is picked on a shader canvas. Several nodes, frames and reroute points can be picked.
---@class ShaderCanvas.Picked
---@field nodes table<string, boolean>
---@field frames table<string, boolean>
---@field points table<string, boolean> By point key, `<wire>#<index>`.

---One open shader's canvas: what its modules share. Each module adds its own functions.
---@class ShaderCanvas.Ctx
---@field app Proteus.App
---@field ui Proteus.UI
---@field nc NodeCanvas
---@field core Shader.Core
---@field docs Shader.Docs
---@field commands Proteus.Commands
---@field catalog Shader.NodesModule
---@field html ShaderCanvas.Html
---@field html_m { TYPE_COLORS: table<string, string> }
---@field refuse fun(text: string)
---@field doc Shader.OpenDoc
---@field path string
---@field view NodeCanvas.View
---@field picked ShaderCanvas.Picked
---@field live table<string, NodeCanvas.Point> Nodes' places during a drag or a tidy.
---@field live_frames table<string, NodeCanvas.Box>
---@field live_points table<string, NodeCanvas.Point> By point key.
---@field routes table<string, { x: number, y: number }[]> Each wire's reroute points.
---@field elements table<string, Proteus.El> Each node's element.
---@field drawn table<string, string> What each node's element was drawn from.
---@field shown table<string, { placed?: string, picked?: boolean, bad?: boolean }>
---@field heights table<string, number> Each node's measured height, in world units.
---@field held? string A node whose colour is being picked, so it does not draw again.
---@field drag? NodeCanvas.Gesture
---@field selected_wire? string
---@field insert_wire? string The wire a dragged node would go into.
---@field snap_grid fun(): boolean
---@field root Proteus.El
---@field viewport Proteus.El
---@field world Proteus.El
---@field frames_el Proteus.El
---@field wires_svg Proteus.El
---@field temp_wire Proteus.El
---@field marquee Proteus.El
---@field zoom_label Proteus.El
---@field minimap NodeCanvas.Minimap
---@field wire_layer NodeCanvas.WireLayer
---@field point_layer NodeCanvas.PointLayer
---@field frame_layer NodeCanvas.FrameLayer
---@field current fun(): Shader.Doc
---@field node fun(id: string): Shader.Node?
---@field save_view fun()
---@field apply_view fun()
---@field set_view fun(view: NodeCanvas.View)
---@field to_world fun(x: number, y: number): number, number
---@field position fun(n: Shader.Node): NodeCanvas.Point
---@field height fun(n: Shader.Node): number
---@field box fun(n: Shader.Node): NodeCanvas.Box
---@field boxes fun(picked_only?: boolean): NodeCanvas.Box[]
---@field port_point fun(n: Shader.Node, side: 'in'|'out', key: string): number, number
---@field view_center fun(): number, number
---@field fit fun()
---@field center_on fun(id: string)
---@field edges_of fun(id: string): Shader.Edge[]
---@field wire fun(id: string): Shader.Edge?
---@field route_of fun(e: Shader.Edge): NodeCanvas.Point[]?
---@field out_type fun(from: string, output: string): Shader.Type
---@field draw_wires fun(nodes?: table<string, boolean>, wires?: table<string, boolean>)
---@field draw_points fun()
---@field show_insert fun(wire?: string)
---@field wire_at fun(box: NodeCanvas.Box, skip: string): string?
---@field point_index fun(e: Shader.Edge, x: number, y: number): integer
---@field find_targets fun(from: string, output: string)
---@field snap_target fun(x: number, y: number): NodeCanvas.Target?
---@field frames fun(): Shader.Frame[]
---@field frame_box fun(id: string): NodeCanvas.Box?
---@field draw_frames fun()
---@field place_frames fun(ids: table<string, boolean>)
---@field set_picked fun(nodes: table<string, boolean>, frames?: table<string, boolean>, points?: table<string, boolean>)
---@field nothing_picked fun(): boolean
---@field picked_nodes fun(): string[]
---@field commit fun(doc: Shader.Doc?, refusal?: any, key?: string): boolean
---@field add_node fun(type_id: string, at?: NodeCanvas.Point, from?: { node: string, output: string, type: Shader.Type }): string?
---@field ask_add fun(at?: NodeCanvas.Point, from?: { node: string, output: string, type: Shader.Type })
---@field copy fun(): boolean
---@field can_paste fun(): boolean
---@field paste fun()
---@field cut fun()
---@field duplicate fun()
---@field delete_picked fun()
---@field select_all fun()
---@field finish_move fun(nodes: table<string, NodeCanvas.Point>, frames: table<string, NodeCanvas.Box>, points: table<string, NodeCanvas.Point>, insert?: string)
---@field align fun(edge: NodeCanvas.Edge)
---@field distribute fun(axis: 'x'|'y')
---@field tidy fun()
---@field add_frame fun(box: NodeCanvas.Box)
---@field frame_picked fun()
---@field set_frame_title fun(id: string, title: string)
---@field add_point fun(wire: string, x: number, y: number)
---@field remove_point fun(wire: string, index: integer)
---@field on_move fun(ev: Proteus.DomEvent): Proteus.EventResult
---@field on_up fun(ev: Proteus.DomEvent): Proteus.EventResult
---@field draw_minimap fun()
---@field place fun(id: string)
---@field show_picked fun()
---@field render fun()

---@class ShaderPreview.Instance
---@field root Proteus.El
---@field refresh fun()
---@field set_playing fun(on: boolean)
---@field playing fun(): boolean
---@field set_scale fun(s: number)
---@field uniform fun(path: string, key: string, value: number[])

---A problem the preview page found while compiling on the GPU.
---@class Shader.GpuError
---@field line? integer
---@field column? integer
---@field message string
---@field stage 'vertex'|'fragment'|'link'|'pipeline'|'setup'
---@field severity 'error'|'warning'
