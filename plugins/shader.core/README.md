# Shader Builder

Builds GLSL and WGSL shaders from a node graph or as code, with a live preview. Install the **Shader Builder** profile from the marketplace to get every part, then open it from **Profile**.

| Plugin | What it does | Permissions |
|--------|--------------|-------------|
| `shader.core` | The node catalog, graph operations, the GLSL and WGSL compiler, code shaders and files. Pure Lua, with tests in `tests/`. | none |
| `shader.docs` | The open shaders and their undo. It copies the examples into `shaders/`, and its `handbook/` folder holds Learning shaders, a course in the Handbook from a first shader to a weather system. | none, writes in `shaders/` |
| `shader.canvas` | The node editor. | none |
| `shader.code` | Code shaders, with GLSL and WGSL added to the code editor as data languages. | none |
| `shader.preview` | Runs the shader live: GLSL on WebGL 2 and WGSL on WebGPU, in a sandboxed web view, `page/`. | none |
| `shader.library` | The list of shaders and nodes. | none |
| `shader.build` | Writes a build to `shaders/build`, and exports one to any folder on disk. | `files`, for Export to Folder |

The types live in `shader.core/types/shader.lua`. A plugin that uses the services casts them, such as `app.use ('shader.docs') --[[@as Shader.Docs]]`.
