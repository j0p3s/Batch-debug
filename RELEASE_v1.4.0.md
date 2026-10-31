# Release v1.4.0

**Title:** v1.4.0 - Collects the files the script creates, PowerShell run from memory, admin-aware runs

## What's new

- **Files the script creates are collected.** Tools often write their own log, report or settings while they run. Debug-CMD now finds the `.log`, `.txt`, `.json`, `.csv`, `.xml` and `.ini` files created or changed during the run, in the script's folder and in folders the script mentions (`C:\Name`, `%SystemDrive%\Name`, `$env:ProgramData 'Name'`...). Their contents go into the `.log` and the `.html`, and lines that look like errors are marked. New options: `COLLECT_FILES` (default `1`) and `COLLECT_DIRS` (extra folders, separated by semicolons).
- **Single-file tools are captured.** Scripts that read their own PowerShell and run it from memory (`Invoke-Expression`) are no longer a black box: the code is cut out exactly like PowerShell does, logged with line numbers, and saved as `<name>_debug_<date>.embedded1.ps1`.
- **Every `.ps1` logged:** files written or run by the script (even temporary ones it deletes), each PowerShell process it starts, decoded `-EncodedCommand` payloads, and full command lines.
- **Administrator-aware (`ELEVATE=AUTO`, new default):** if the script contains `runas`, `fltmc`, `net session` and similar, Debug-CMD relaunches itself as administrator (one UAC prompt) so it can follow scripts that restart themselves elevated. The elevated window stays open so errors remain visible.
- **Honest status:** if a script restarted itself as administrator and could not be followed, the report says `INCOMPLETE - RESTARTED AS ADMIN` instead of `OK`.
- **HTML report** now has the PowerShell section, "Run from memory" and "Files collected" cards, and the collected files with highlighted error lines.

## Fixes

- `set "PSEXE=...powershell.exe"` and `if exist ... set ...` lines are no longer counted as PowerShell runs (debug and test mode).
- Test mode no longer analyzes embedded PowerShell as batch code: no more false "file not found" and "label does not exist" errors on single-file tools.

## Notes

- Windows only. Tested on Windows 10.
- Only text files with the extensions above are collected, from at most 15 folders, 4 levels deep. Files over 1 MB show only their last 200 KB.
