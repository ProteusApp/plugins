# Shaders on disk

Edit the shaders in a Code Editor project with the Shader Builder, beside the rest of the project's files.

## What it does

- **Opens shaders in the builder.** A node graph (`.shader.json`) opens on the node canvas. A code shader (`.frag`, `.vert`, `.glsl`, `.wgsl` or `.gdshader`) opens in the builder's code view.
- **Shows them running.** The Preview panel runs the shader in front and redraws as you type or change nodes.
- **Godot shaders run too.** A `.gdshader` file runs in the Preview as GLSL. canvas_item, spatial and sky shaders work. Each uniform gets a control from its hints, such as `hint_range` and `source_color`.
- **Open as Text** in the file tree's right-click menu opens a shader in the plain editor instead. **Open in the Shader Builder** opens it in the builder.
- **Saves go back to the file.** Changes made outside the builder load again, and a shader with unsaved edits asks first.

## Setting it up

Switch this plugin on in the Code Editor, from the marketplace or the Profiles page. It brings the Shader Builder's canvas, code view and Preview with it.

The builder reads the files beside a shader too, so a `.vert` file and buffers such as `water.buffer-a.frag` work as they do in the Shader Builder.
