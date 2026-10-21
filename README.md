# Debug-CMD

English | [Português](README.pt-PT.md)

Drag a `.cmd` or `.bat` file onto `Debug-CMD.cmd` and get a `.log` of everything the script did, plus a summary of what worked and what failed.

A single file, nothing to install: it uses the PowerShell that already ships with Windows 10/11.

## Features

- **Easy-to-read HTML report:** besides the `.log`, you get a self-contained `.html` page (no internet needed) with a status badge, summary cards, expandable failed commands, a list of what worked, and a filterable full log. It follows your light/dark theme.
- **Safe test mode:** choose `T` at the start to only analyze the script. Nothing is executed. It flags dangerous commands (delete, format, registry, shutdown, downloads...) and broken `goto`/`call` targets.
- **Line-by-line debugging:** runs a temporary copy of your script with `echo on`, so the log shows each command right before its output.
- **Timestamped log:** every line carries a time with milliseconds. The top of the log lists the user, the Windows version, and whether it ran as administrator.
- **Summary at the top of the log and on screen:**
  - final status: `OK`, `WITH PROBLEMS`, or `INTERRUPTED`;
  - exit code and duration;
  - **WHAT FAILED:** commands with errors, along with the error lines;
  - **WHAT WORKED:** commands with no detected errors.
- **Hands-off:** `pause` commands in the copy are skipped so the script runs to the end.
- **Robust:** on Ctrl+C the log and summary are still saved, the process is stopped, and the temporary copy is deleted.
- **Doesn't look frozen:** during long, silent commands it prints "running for mm:ss" every 10 seconds.
- **Original untouched:** the script you drag in is never modified.

## Usage

1. Download `Debug-CMD.cmd`.
2. Drag your `.cmd` or `.bat` file onto it.
3. When it finishes, the window stays open and the HTML report opens in your browser.

The log is created next to your script and named `ScriptName_debug_YYYY-MM-DD_HH-MM-SS.log`. If that folder isn't writable, it goes to the temp folder instead.

## Modes

When you drag a script in, you are asked to choose:

- **`E` - Execute:** runs the script for real and debugs it (log + summary).
- **`T` - Test only:** static analysis. The script is only read, **never executed**. You get a `Name_test_<date>.log` report with the risk verdict, the lines that can change the system (grouped as HIGH / MEDIUM / LOW), and structural problems such as a `goto` to a label that doesn't exist or a `call` to a missing file.

Set `MODE` to `RUN` or `TEST` to skip the question.

## Options

These are at the top of `Debug-CMD.cmd` (`1` = yes, `0` = no):

| Option | Default | What it does |
|---|---|---|
| `ELEVATE` | `0` | Requests administrator rights (one UAC prompt) |
| `ECHO_ON` | `1` | Forces `echo on` in the temporary copy |
| `SKIP_PAUSE` | `1` | Replaces `pause` in the copy with a note |
| `OPEN_REPORT` | `1` | Opens the report when done (HTML in the browser, or the log in Notepad) |
| `GENERATE_HTML` | `1` | Also creates the `.html` report next to the `.log` |
| `MODE` | `ASK` | `ASK` asks every time, `RUN` always executes, `TEST` only analyzes (executes nothing) |

## Example summary

```
==============================================================================
 SUMMARY
==============================================================================
Script           : C:\Scripts\example.cmd
Status           : WITH PROBLEMS
Exit code        : 1
Duration         : 00:00:03.412
Commands         : 6 run | 5 with no detected errors | 1 with problems
Error lines      : 1

==============================================================================
 WHAT FAILED
==============================================================================
[FAILED] [23:10:16.531] copy source.txt dest\
           > The system cannot find the file specified.
```

## How it works

1. The `.cmd` extracts the PowerShell code embedded in it into a temporary `.ps1` file and runs it.
2. PowerShell makes a copy of the target script (`__dbg_<name>`) with `echo off` changed to `echo on` and `pause` skipped. The copy preserves the original bytes.
3. It runs the copy with `cmd /c`, merges `stdout` and `stderr` in the order they appear, and logs each line with a timestamp.
4. At the end, the log is analyzed: lines matching error patterns (Portuguese and English) are attached to the command that produced them.

## Limitations

- Test mode is a keyword scan of the script text: it does not expand variables, does not follow scripts it calls, and can't see commands built at run time. It lowers the risk, it doesn't guarantee safety.
- `cmd` doesn't let you see inside a script, so errors are detected by **keywords** in the output (for example "is not recognized", "access is denied", "failed"). It can miss errors in other languages and can produce false positives, such as an `echo` that prints "error".
- There is no per-command exit code, only the final one.
- Commands using `>nul 2>&1` hide their own errors.
- Only the dragged script is forced to `echo on`. Scripts it launches with `call` keep their own `echo off`.
- `%0`, `%~nx0`, and similar point to the `__dbg_...` copy.
- Skipping `pause` and using a copy slightly changes the script's behavior. Set `SKIP_PAUSE=0` and `ECHO_ON=0` if that matters.
- If you press Ctrl+C and see "Terminate batch job (Y/N)?", answer `N` to see the summary.
- Don't use Ctrl+C to copy text from the window: in this console it interrupts the run.

## Requirements

- Windows 10 or 11 with Windows PowerShell 5.1 (included).

## Warning

Your script is **actually executed**. If it deletes files, installs software, or changes settings, it will do the same during debugging. Test carefully.

## License

[MIT](LICENSE)
