# Godot resource inspector

Opens `.tres` files from the Code Editor's project explorer in an editable inspector. Enable `view.tres` with the Code Editor plugins, then open a resource on disk.

Select the main resource or a subresource in the left panel. Filter properties by name.

Saved booleans, numbers, strings, vectors and colors have dedicated controls. Resource fields list references declared in the file. Arrays, dictionaries and other values use Godot text fields.

Save writes the file in place. Undo and Redo step through field edits.

Reload reads the file again and asks before discarding edits. Open as text opens the regular editor after edits have been saved or discarded. A changed file on disk blocks saving until it has been reloaded.

Only saved properties appear. Godot's default values, script export hints, enum names and previews require information outside the resource file.

Raw fields check brackets and strings but do not validate Godot types. Open the saved resource in Godot to check those values.

Edits preserve the surrounding file text, including headers, resource IDs and untouched properties. This plugin reads and writes files picked through the project explorer, so it requires the `files` permission.
