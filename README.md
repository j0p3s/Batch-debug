# Debug-CMD

English | [Português](README.pt-PT.md)

Drag a `.cmd` or `.bat` file onto `Debug-CMD.cmd` and get a `.log` of everything the script did, plus a summary of what worked and what failed.

A single file, nothing to install: it uses the PowerShell that already ships with Windows 10/11.

## Features

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
3. When it finishes, the window stays open and the log opens in Notepad.

The log is created next to your script and named `ScriptName_debug_YYYY-MM-DD_HH-MM-SS.log`. If that folder isn't writable, it goes to the temp folder instead.

## Options

These are at the top of `Debug-CMD.cmd` (`1` = yes, `0` = no):

| Option | Default | What it does |
|---|---|---|
| `ELEVAR` | `0` | Requests administrator rights (one UAC prompt) |
| `ECHO_ON` | `1` | Forces `echo on` in the temporary copy |
| `IGNORAR_PAUSE` | `1` | Replaces `pause` in the copy with a note |
| `ABRIR_LOG` | `1` | Opens the log in Notepad when done |

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

The labels in the actual log are currently in Portuguese (`RESUMO`, `O QUE FALHOU`, `O QUE CORREU BEM`).

## How it works

1. The `.cmd` extracts the PowerShell code embedded in it into a temporary `.ps1` file and runs it.
2. PowerShell makes a copy of the target script (`__dbg_<name>`) with `echo off` changed to `echo on` and `pause` skipped. The copy preserves the original bytes.
3. It runs the copy with `cmd /c`, merges `stdout` and `stderr` in the order they appear, and logs each line with a timestamp.
4. At the end, the log is analyzed: lines matching error patterns (Portuguese and English) are attached to the command that produced them.

## Limitations

- `cmd` doesn't let you see inside a script, so errors are detected by **keywords** in the output (for example "is not recognized", "access is denied", "failed"). It can miss errors in other languages and can produce false positives, such as an `echo` that prints "error".
- There is no per-command exit code, only the final one.
- Commands using `>nul 2>&1` hide their own errors.
- Only the dragged script is forced to `echo on`. Scripts it launches with `call` keep their own `echo off`.
- `%0`, `%~nx0`, and similar point to the `__dbg_...` copy.
- Skipping `pause` and using a copy slightly changes the script's behavior. Set `IGNORAR_PAUSE=0` and `ECHO_ON=0` if that matters.
- If you press Ctrl+C and see "Terminate batch job (Y/N)?", answer `N` to see the summary.
- Don't use Ctrl+C to copy text from the window: in this console it interrupts the run.
- The summary and log labels are in Portuguese for now.

## Requirements

- Windows 10 or 11 with Windows PowerShell 5.1 (included).

## Warning

Your script is **actually executed**. If it deletes files, installs software, or changes settings, it will do the same during debugging. Test carefully.

## License

[MIT](LICENSE)
