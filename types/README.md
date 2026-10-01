# Types

These files tell lua-language-server what the app gives a plugin, so an editor can check a
plugin's code. Nothing here runs.

All but `tests.lua` are copies of `lua/types` in the Proteus app. Copy them again when the app
changes its types. `tests.lua` describes the globals that `scripts/lua-test.mjs` gives a
plugin's tests.
