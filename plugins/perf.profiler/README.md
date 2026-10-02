# Profiler

The Profiler shows which plugin works the hardest, and why the window lags.

Open it with **Profiler: Open Profiler** (Ctrl+Alt+Shift+P), or click the gauge in the status bar. The status bar shows how busy plugin code kept the window over the last 10 seconds. It turns to **Stall** for a few seconds after the window freezes.

## What it measures

Proteus runs every plugin's Lua on one thread, the same one that draws the window. While a plugin's code runs, nothing else does: no click, no key, no frame. The kernel times every plugin callback (event handlers, timers, clicks, replies and commands) and counts it to the plugin it belongs to. The Profiler reads those numbers once a second.

- **Share** is time in the plugin's own code. Time spent in the handlers of other plugins it set off, such as listeners for an event it sent, counts to those plugins.
- **With nested** adds those handlers back in.
- **Longest** is the plugin's biggest share of one task. Only tasks of 4 ms or more are kept, so a dash means it never took that long.
- **Elements** is how many elements the plugin has on the page. A large page is slow to lay out.
- **Start** is the time to load the plugin's code and run its `activate`. **Restart and time its start**, under a row, reloads the plugin to measure it again. It stops the plugins that use it too, and starts them again.

## Why the window lagged

A stall is a time the window froze for 50 ms or more. It comes from three places: gaps between frames, the long tasks the browser reports, and plugin tasks over 50 ms. Each stall is split into plugin code, by plugin, and the rest. The rest is the browser's own work: laying out and painting the page, collecting garbage, or a widget such as the code editor. A striped bar marks it.

Frames are counted only while the Profiler shows, because counting them keeps the page drawing every frame. The browser's long tasks are counted all the time on Windows and Linux. macOS reports none, so there a stall shows only while the Profiler is open, or when a plugin task alone ran 50 ms.

**What stands out** turns the numbers into sentences, worst first: the plugin that used the most time and in which callback, timers that run many times a second, events sent in a flood, plugins with very many elements, errors, slow starts and memory that keeps growing. Click one that names a plugin to open its row.

## Reports

**Copy Report** puts the chosen stretch on the clipboard as Markdown. **Save Report** writes it to `data/perf.profiler/` in the workspace. Nothing leaves the computer.

## Needs

Proteus with the `perf` feature, which adds `app.kernel.perf`. The plugin asks for the `kernel` permission, since what every plugin does is as revealing as their logs.
