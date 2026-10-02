# Logs

A log viewer. It follows log files and running programs, and shows their lines as they arrive. Install the **Logs** profile from the marketplace to run it as an app of its own.

## What it does

- **Sources.** Follow a log file (Ctrl+O), run a command and read what it prints (Ctrl+Shift+R), or paste a log. Each one is a source in the Sources view, and Open Recent brings one back.
- **Filter.** Ctrl+F filters the lines: words, `-word` to leave lines out, `"a phrase"`, `level:error` to keep one level and `-level:error` to hide one. `level:` takes `error`, `warn`, `info`, `debug` and `other`, the lines with no level, or the start of one, such as `level:w`. The level buttons show or hide errors, warnings, info, debug and the rest.
- **Levels.** A line's level comes from a JSON or logfmt field such as `level=warn`, from the letter that starts a glog or klog line such as `E1001 12:00:00.000000`, or from a word such as `ERROR` near the start.
- **Detail.** A click shows a whole line, with its JSON formatted. Copy one line or every line that matches.
- **Follow.** The list keeps to the newest line until you scroll up.

It keeps up to 50,000 lines for each source and draws the last 5,000.

## What it needs

The desktop app. A file is followed with `tail -F`, or with PowerShell's `Get-Content -Wait` on Windows. In a browser only a pasted log works.

## Permissions

| Permission | Why |
|------------|-----|
| `process` | It runs the commands you give it, and the program that follows a file. |
| `files` | It asks for a log file in the system's dialog and follows it by its path, anywhere on disk. |
| `clipboard` | Paste Log reads the log from the clipboard. |
