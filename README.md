# Debug-CMD

English | [Português](README.pt-PT.md)

Drag a `.cmd` or `.bat` file onto `Debug-CMD_v1.4.1.cmd` and get a `.log` of everything the script did, plus a summary of what worked and what failed.

A single file, nothing to install: it uses the PowerShell that already ships with Windows 10/11.

## Features

- **Easy-to-read HTML report:** besides the `.log`, you get a self-contained `.html` page (no internet needed) with a status badge, summary cards, expandable failed commands, a list of what worked, and a filterable full log. It follows your light/dark theme.
- **PowerShell logged too:** if your script writes `.ps1` files or runs PowerShell, the log keeps the full contents of every `.ps1` it writes or runs (even temporary ones the script deletes right after), each PowerShell it starts (even when the command isn't echoed), decoded `-EncodedCommand` payloads, and the `.ps1` line where PowerShell reported an error.
- **Single-file `.cmd` tools too:** many tools carry their PowerShell inside the `.cmd` and run it from memory (`Invoke-Expression`), so no `.ps1` ever exists on disk. Debug-CMD cuts that code out of the file exactly as PowerShell does, logs it with line numbers, and saves it next to the log as `<name>_debug_<date>.embedded1.ps1`, so PowerShell's `At line:N` numbers match that file.
- **Files the script creates are collected:** many tools write their own log, report or settings while they run (`.log`, `.txt`, `.json`, `.csv`, `.xml`, `.ini`). Debug-CMD finds the ones created or changed during the run, in the script's folder and in folders the script mentions (such as `C:\Name` or `%SystemDrive%\Name`), and puts their contents in the report with lines that look like errors marked. Add more folders with `COLLECT_DIRS`.
- **Scripts that ask for administrator rights:** with `ELEVATE=AUTO` (the default), Debug-CMD runs as administrator when the script contains `runas`, `fltmc`, `net session` and similar. Otherwise the script restarts itself in a new window that can't be followed.
- **Safe test mode:** choose `T` at the start to only analyze the script. Nothing is executed. For single-file tools, the batch checks (`goto`, `call`, labels) stop at the `#PS-BEGIN` marker and only the risk rules run on the embedded PowerShell. It flags dangerous commands (delete, format, registry, shutdown, downloads...) in the script, in inline and encoded PowerShell, and in `.ps1` files it uses that are already on disk, plus broken `goto`/`call` targets.
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

1. Download `Debug-CMD_v1.4.1.cmd`.
2. Drag your `.cmd` or `.bat` file onto it.
3. When it finishes, the window stays open and the HTML report opens in your browser.

The log is created next to your script and named `ScriptName_debug_YYYY-MM-DD_HH-MM-SS.log`. If that folder isn't writable, it goes to the temp folder instead.

## Modes

When you drag a script in, you are asked to choose:

- **`E` - Execute:** runs the script for real and debugs it (log + summary).
- **`T` - Test only:** static analysis. The script is only read, **never executed**. You get a `Name_test_<date>.log` report with the risk verdict, the lines that can change the system (grouped as HIGH / MEDIUM / LOW), structural problems such as a `goto` to a label that doesn't exist or a `call` to a missing file, and a PowerShell section listing the lines that write `.ps1` files or run PowerShell.

Set `MODE` to `RUN` or `TEST` to skip the question.

## Options

These are at the top of `Debug-CMD_v1.4.1.cmd` (`1` = yes, `0` = no; `ELEVATE` and `MODE` take words):

| Option | Default | What it does |
|---|---|---|
| `ELEVATE` | `AUTO` | `0` never, `1` always, `AUTO` only when the script asks for administrator rights (one UAC prompt) |
| `ECHO_ON` | `1` | Forces `echo on` in the temporary copy |
| `SKIP_PAUSE` | `1` | Replaces `pause` in the copy with a note |
| `OPEN_REPORT` | `1` | Opens the report when done (HTML in the browser, or the log in Notepad) |
| `GENERATE_HTML` | `1` | Also creates the `.html` report next to the `.log` |
| `LOG_PS1` | `1` | Also logs PowerShell: the `.ps1` files the script writes or runs (full contents), the PowerShell processes it starts, and decoded `-EncodedCommand` |
| `COLLECT_FILES` | `1` | Also collects the text files the script creates or changes while it runs (its own logs, reports, settings) and shows them in the report |
| `COLLECT_DIRS` | *(empty)* | Extra folders to look in, separated by semicolons (the script's folder and folders it mentions are automatic) |
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
PowerShell       : 1 run(s) | 1 .ps1 file(s) logged | 0 script(s) run from memory

==============================================================================
 WHAT FAILED
==============================================================================
[FAILED] [23:10:16.531] copy source.txt dest\
           > The system cannot find the file specified.

==============================================================================
 POWERSHELL   (the full .ps1 contents are at the end of this log)
==============================================================================
[RUN]    [23:10:17.002] powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\Me\AppData\Local\Temp\fix.ps1"
           > runs C:\Users\Me\AppData\Local\Temp\fix.ps1
[PS1 1]  C:\Users\Me\AppData\Local\Temp\fix.ps1
           > written during the run | ran 1x | deleted before the end | 12 lines
```

## How it works

1. The `.cmd` extracts the PowerShell code embedded in it into a temporary `.ps1` file and runs it.
2. PowerShell makes a copy of the target script (`__dbg_<name>`) with `echo off` changed to `echo on` and `pause` skipped. The copy preserves the original bytes.
3. It runs the copy with `cmd /c`, merges `stdout` and `stderr` in the order they appear, and logs each line with a timestamp.
4. While it runs, a file watcher on the script's folder and `%TEMP%` (including subfolders) reads every `.ps1` the moment it's written, and a process watcher spots each PowerShell the script starts. `.ps1` files named in echoed `powershell` commands are read too, wherever they are. CLIXML that PowerShell prints when its output is redirected is turned back into readable text.
5. When a PowerShell command reads code from a file and runs it with `Invoke-Expression` / `iex` (for example `$t.Substring($t.IndexOf('#PS-BEGIN'))` or `iex (${file.cmd} | out-string)`), the same code is cut out of that file, logged as "run from memory" and saved as a real `.ps1` next to the log.
6. At the end, the log is analyzed: lines matching error patterns (Portuguese and English) are attached to the command that produced them, and every `.ps1` captured is appended to the log with line numbers.

## Limitations

- Test mode is a keyword scan of the script text: it does not expand variables, does not follow scripts it calls, and can't see commands built at run time. It lowers the risk, it doesn't guarantee safety.
- `cmd` doesn't let you see inside a script, so errors are detected by **keywords** in the output (for example "is not recognized", "access is denied", "failed"). It can miss errors in other languages and can produce false positives, such as an `echo` that prints "error".
- There is no per-command exit code, only the final one.
- Commands using `>nul 2>&1` hide their own errors.
- Only the dragged script is forced to `echo on`. Scripts it launches with `call` keep their own `echo off`.
- `%0`, `%~nx0`, and similar point to the `__dbg_...` copy.
- PowerShell code that is built or downloaded at run time (for example `iex (irm https://...)`, or a string assembled in memory) can't be cut out of a file. Its command line is logged in full, but the code itself is not.
- A script that restarts itself as administrator in another window (`Start-Process -Verb RunAs`) can only be followed if Debug-CMD itself runs as administrator. The log warns about it and keeps the temporary copy.
- A `.ps1` written outside the script's folder and `%TEMP%` is only logged if a PowerShell command that runs it is seen. A PowerShell that isn't echoed and ends in under about half a second can be missed by the process watcher.
- If the live capture can't start (for example, a policy that blocks compiling), only `.ps1` files run by echoed commands are logged. The log says so.
- Skipping `pause` and using a copy slightly changes the script's behavior. Set `SKIP_PAUSE=0` and `ECHO_ON=0` if that matters.
- If you press Ctrl+C and see "Terminate batch job (Y/N)?", answer `N` to see the summary.
- Don't use Ctrl+C to copy text from the window: in this console it interrupts the run.

## Requirements

- Windows 10 or 11 with Windows PowerShell 5.1 (included).

## Warning

Your script is **actually executed**. If it deletes files, installs software, or changes settings, it will do the same during debugging. Test carefully.

## License

[MIT](LICENSE)
