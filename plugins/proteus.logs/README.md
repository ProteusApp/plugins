# Logs

A log viewer. It follows log files and running programs, and shows their lines as they arrive. Install the **Logs** profile from the marketplace to run it as an app of its own.

## What it does

- **Sources.** Follow a log file (Ctrl+O), open a whole file from its first line (Ctrl+Shift+O), run a command and read what it prints (Ctrl+Shift+R), or paste a log. Each one is a source in the Sources view, and Open Recent brings one back.
- **Filter.** Ctrl+F filters the lines: words, `-word` to leave lines out, `"a phrase"`, `/a|b/` for a regular expression and `-/a|b/` to leave out what it matches, `level:error` to keep one level and `-level:error` to hide one. `level:` takes `error`, `warn`, `info`, `debug` and `other`, the lines with no level, or the start of one, such as `level:w`. The level buttons show or hide errors, warnings, info, debug and the rest. A regular expression ignores case, like the words, and reads `.`, `[...]`, `\d \w \s`, `\b`, `^ $`, groups, `|` and `* + ? {n,m}`.
- **Time.** Each line's time comes from an ISO 8601 date, a JSON or logfmt field such as `time` or `ts`, a web server's `[10/Oct/2000:13:55:36 -0700]`, syslog's `Oct 10 13:55:36`, or glog's `I1010 13:55:36`. A line with no time of its own, such as a line of a stack trace, takes the time of the line above. `after:` and `before:` keep a span: `after:2024-03-01T12:00`, `before:2024-03-02`, `after:12:00 before:12:30` for a time of day on any day, or `after:-15m` for the last 15 minutes before the newest line. `since:` and `until:` do the same. A line with no time is outside any span. A time with no zone counts as it is written.
- **All sources, by time.** With two sources or more, **All sources, by time** at the top of the Sources view shows every line of every source in one list, in order of time, each with its source's name. Lines that arrive while it shows join at the bottom.
- **Levels.** A line's level comes from a JSON or logfmt field such as `level=warn`, from the letter that starts a glog or klog line such as `E1001 12:00:00.000000`, or from a word such as `ERROR` near the start.
- **Detail.** A click shows a whole line, its time, and its JSON formatted. Copy one line or every line that matches.
- **Follow.** The list keeps to the newest line until you scroll up.

It keeps up to 50,000 lines for each source, and 250,000 for a whole file. The list draws up to 5,000 of the lines that match at a time. **Show Earlier** and **Show Later** at its top and bottom, or Ctrl+PageUp and Ctrl+PageDown, move it, so every line that matches can be reached, and **Newest** (Ctrl+End) goes back to the end.

## What it needs

The desktop app. A file is followed with `tail -F`, or with PowerShell's `Get-Content -Wait` on Windows. A whole file is read the same way, from its first line. In a browser only a pasted log works.

## Permissions

| Permission | Why |
|------------|-----|
| `process` | It runs the commands you give it, and the program that follows a file. |
| `files` | It asks for a log file in the system's dialog and follows it by its path, anywhere on disk. |
| `clipboard` | Paste Log reads the log from the clipboard. |
