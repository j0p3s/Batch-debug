# Release v1.3.0

**Title:** v1.3.0 - Logs PowerShell run from memory, admin-aware runs, cleaner test mode

## What's new

- **Single-file tools are now captured.** Scripts that read their own PowerShell and run it from memory (`Invoke-Expression`) no longer log nothing. Debug-CMD finds the marker (e.g. `#PS-BEGIN`), cuts the code out exactly like PowerShell does, logs it with line numbers, and saves it as `<name>_debug_<date>.embedded1.ps1`.
- **Every `.ps1` logged:** files written or run by the script (even temporary ones it deletes), each PowerShell process it starts, and decoded `-EncodedCommand` payloads. Full command lines are kept in the log.
- **Administrator-aware (`ELEVATE=AUTO`, new default):** if the script contains `runas`, `fltmc`, `net session` and similar, Debug-CMD relaunches itself as administrator (one UAC prompt) so it can follow scripts that restart themselves elevated. The elevated window stays open so errors remain visible.
- **Honest status:** if a script restarted itself as administrator and could not be followed, the report says `INCOMPLETE - RESTARTED AS ADMIN` instead of `OK`.
- **HTML report** updated with the PowerShell section, "Run from memory" cards and full command lines.

## Fixes

- `set "PSEXE=...powershell.exe"` and `if exist ... set ...` lines are no longer counted as PowerShell runs.
- Test mode no longer analyzes embedded PowerShell as batch code: no more false "file not found" and "label does not exist" errors on single-file tools.

## Notes

- Capturing what happens inside a GUI is limited to what the script runs and writes; files the tool creates on its own are not collected yet.
- Windows only. Tested on Windows 10.
