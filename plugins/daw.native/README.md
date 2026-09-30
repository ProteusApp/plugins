# Native plugins

The CLAP and VST3 plugins installed on this computer, as instruments and effects for the DAW. Each shows in the browser under **CLAP** or **VST3**, with a control in the rack for each of its parameters.

- Only the native sound engine plays them. Set **Sound engine** (`daw.engine`) to `native` in the settings. The web engine plays the rest of the song, and says which devices it cannot play.
- The plugin needs the `native-plugins` permission, since a native plugin runs with your rights. The app also asks you the first time a song loads each one, and the plugin never learns where the files are.
- **Look for Native Plugins** looks again after you install one. Looking loads each plugin in a process of its own, so one that crashes is left out.
- VST3 parameters run from 0 to 1, as VST3 hosts see them.
