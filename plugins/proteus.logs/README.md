# Logs

A log viewer. It follows log files and running programs, and shows their lines as they arrive. Install the **Logs** profile from the marketplace to run it as an app of its own.

## What it does

- **Sources.** Follow a log file (Ctrl+O), open a whole file from its first line (Ctrl+Shift+O), run a command and read what it prints (Ctrl+Shift+R), or paste a log. Each one is a source in the Sources view, and Open Recent brings one back.
- **Gzip and rotated files.** A file that ends in `.gz` opens like any other, read whole, since it does not grow. **Open Rotated Log File** takes one file of a rotated log, such as `app.log` or `app.log.1`, and shows the whole log as one source: the files it was rotated into first, oldest first, such as `app.log.2.gz` and then `app.log.1`, or dated ones such as `app.log-20240301.gz`, then `app.log`, which it follows.
- **Filter.** Ctrl+F filters the lines: words, `-word` to leave lines out, `"a phrase"`, `/a|b/` for a regular expression and `-/a|b/` to leave out what it matches, `level:error` to keep one level and `-level:error` to hide one. `level:` takes `error`, `warn`, `info`, `debug` and `other`, the lines with no level, or the start of one, such as `level:w`. The level buttons show or hide errors, warnings, info, debug and the rest. A regular expression ignores case, like the words, and reads `.`, `[...]`, `\d \w \s`, `\b`, `^ $`, groups, `|` and `* + ? {n,m}`. `is:marked` keeps the bookmarked lines.
- **Time.** Each line's time comes from an ISO 8601 date, a JSON or logfmt field such as `time` or `ts`, a web server's `[10/Oct/2000:13:55:36 -0700]`, syslog's `Oct 10 13:55:36`, or glog's `I1010 13:55:36`. A line with no time of its own, such as a line of a stack trace, takes the time of the line above. `after:` and `before:` keep a span: `after:2024-03-01T12:00`, `before:2024-03-02`, `after:12:00 before:12:30` for a time of day on any day, or `after:-15m` for the last 15 minutes before the newest line. `since:` and `until:` do the same. A line with no time is outside any span. A time with no zone counts as it is written.
- **Histogram.** Bars above the list show how many lines that match were written over time, each bar a round span such as 10 seconds or 5 minutes, with errors, warnings and the other levels in their colours. A click on a bar keeps the lines of its span, and a drag across bars keeps the lines of all of them: the span goes into the filter as `after:` and `before:`, and the bars show it in finer bars. **All Time** takes the span out again. **Histogram** on the bar, or **Toggle Histogram**, shows and hides it.
- **All sources, by time.** With two sources or more, **All sources, by time** at the top of the Sources view shows every line of every source in one list, in order of time, each with its source's name. Lines that arrive while it shows join at the bottom.
- **Formats and columns.** **New Format** makes a format from a regular expression with a named group for each field, such as `^(?<time>\S+) \[(?<level>\w+)\] (?<msg>.*)$`, or from the fields to pick from JSON or logfmt lines, such as `level, msg, user.id`, which it suggests from the lines it finds. **Set Format**, or **Format…** on a source's right-click menu, gives a source a format, and its fields show as columns in the list. A click on a column's name sorts the list by it, up and then down, and a third click puts the lines back in the order they came. `field:value` in the filter keeps the lines whose field holds the value, `field:=value` wants it whole, `field:>500` and the like compare, `field:"two words"` takes spaces, and `-field:value` hides what it finds. A field named `level`, `lvl` or `severity` also sets the line's level. **Change Format** and **Delete Format** keep the list of formats tidy.
- **Levels.** A line's level comes from a JSON or logfmt field such as `level=warn`, from the letter that starts a glog or klog line such as `E1001 12:00:00.000000`, or from a word such as `ERROR` near the start.
- **Detail.** A click shows a whole line, its time, and its JSON formatted. Copy one line or every line that matches.
- **Bookmarks.** Ctrl+F2, or M in the list, bookmarks the selected line, and does it again to take the bookmark away. F2 and Shift+F2 go to the next and the previous bookmark, **Go to Bookmark** lists them all, and `is:marked` in the filter keeps only the bookmarked lines. Bookmarks last until the source closes or restarts.
- **Export.** **Export Matching Lines** writes the lines that pass the filter to a file you pick: as they read, or as CSV, with each line's number, time, level, columns and text, when the name ends in `.csv`.
- **Follow.** The list keeps to the newest line until you scroll up.

It keeps up to 50,000 lines for each source, and 250,000 for a whole file, a gzip file or a rotated log. The list draws up to 5,000 of the lines that match at a time. **Show Earlier** and **Show Later** at its top and bottom, or Ctrl+PageUp and Ctrl+PageDown, move it, so every line that matches can be reached, and **Newest** (Ctrl+End) goes back to the end.

## What it needs

The desktop app. A file is followed with `tail -F`, or with PowerShell's `Get-Content -Wait` on Windows. A whole file is read the same way, from its first line. A gzip file is unpacked with `gzip -dc`, or with .NET's `GZipStream` in PowerShell on Windows. In a browser only a pasted log works.

## Permissions

| Permission | Why |
|------------|-----|
| `process` | It runs the commands you give it, and the program that follows a file. |
| `files` | It asks for a log file in the system's dialog and follows it by its path, anywhere on disk, and lists the folder of a rotated log to find its older files. |
| `clipboard` | Paste Log reads the log from the clipboard. |
