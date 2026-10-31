@echo off
setlocal EnableExtensions
title Debug-CMD
rem ======================================================================
rem  Debug-CMD.cmd
rem  Drag a .cmd or .bat file onto this file.
rem  It runs the script with echo on, records everything in a .log (next to the
rem  script) and builds a summary of what worked and what failed.
rem  If the script writes or runs PowerShell (.ps1) files, their full contents
rem  are logged too, along with every PowerShell it starts.
rem  Nothing to install: it uses the PowerShell that already ships with Windows.
rem  The window always stays open at the end (pause) so you can read the result.
rem ======================================================================

rem ---- Options (1 = yes, 0 = no) ----
rem ELEVATE         asks for administrator rights (one UAC prompt): 0 = never, 1 = always,
rem                 AUTO = only when the script itself asks for them (runas, fltmc, net session...)
rem                 A script that restarts itself as administrator cannot be followed
rem                 unless Debug-CMD already runs as administrator
rem ECHO_ON         forces echo on in a temporary copy of the script
rem SKIP_PAUSE      replaces pause in the copy with a note, so it runs hands-off
rem OPEN_REPORT     opens the report when done (HTML in the browser, or the .log in Notepad)
rem GENERATE_HTML   also creates an easy-to-read .html report (next to the .log)
rem LOG_PS1         also logs PowerShell: the .ps1 files the script writes or runs (full
rem                 contents, even if the script deletes them), the PowerShell processes it
rem                 starts, and decoded -EncodedCommand payloads
rem COLLECT_FILES   also collects the text files the script creates or changes while it runs
rem                 (its own logs, reports, settings: .log .txt .json .csv .xml .ini) and
rem                 puts their contents in the report, with the lines that look like errors marked
rem COLLECT_DIRS    extra folders to look in, separated by semicolons (optional). The script's
rem                 own folder and folders it mentions (C:\Name, %SystemDrive%\Name...) are automatic
rem MODE            ASK = ask every time, RUN = execute, TEST = only analyze, execute NOTHING
set "ELEVATE=AUTO"
set "ECHO_ON=1"
set "SKIP_PAUSE=1"
set "OPEN_REPORT=1"
set "GENERATE_HTML=1"
set "LOG_PS1=1"
set "COLLECT_FILES=1"
set "COLLECT_DIRS="
set "MODE=ASK"

echo.
echo  [Debug-CMD] Starting...

if "%~1"=="" goto :no_file
if not exist "%~1" goto :no_file

set "DBG_TARGET=%~f1"
set "DBG_SELF=%~f0"
echo  Target script: "%DBG_TARGET%"

if not "%~2"=="" set "MODE=%~2"
set "DBG_MODE=%MODE%"
if /i not "%MODE%"=="ASK" goto :mode_ok
echo.
echo  What do you want to do?
echo    [E] Execute the script - it will REALLY run
echo    [T] Test only - analyze it WITHOUT running anything
choice /c ET /n /m " Choose E or T: "
if errorlevel 2 (set "DBG_MODE=TEST") else (set "DBG_MODE=RUN")
:mode_ok
if /i "%DBG_MODE%"=="TEST" goto :start_run

if /i not "%ELEVATE%"=="AUTO" goto :elevate_decided
findstr /i /c:"runas" /c:"fltmc" /c:"net session" /c:"requireAdministrator" /c:"IsInRole" /c:"openfiles" "%DBG_TARGET%" >nul 2>&1 && set "ELEVATE=1"
if "%ELEVATE%"=="1" echo  This script asks for administrator rights, so Debug-CMD will run as administrator to capture everything.
:elevate_decided

if not "%ELEVATE%"=="1" goto :start_run
fltmc >nul 2>&1 && goto :start_run
echo  Requesting administrator rights (UAC)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath $env:ComSpec -ArgumentList ('/k ' + [char]34 + [char]34 + $env:DBG_SELF + [char]34 + [char]32 + [char]34 + $env:DBG_TARGET + [char]34 + [char]32 + $env:DBG_MODE + [char]34) -Verb RunAs"
if errorlevel 1 goto :elevate_failed
echo.
echo  A new window with administrator rights was opened.
echo  The run continues in that window. You can close this one.
echo  That window stays open after the run so you can read any error.
echo  If the new window did not appear, set ELEVATE to 0 at the top of this file.
echo.
pause
exit /b

:elevate_failed
echo.
echo  Could not get administrator rights.
echo  Tip: set ELEVATE to 0 at the top of this file to run without administrator rights.
echo.
pause
exit /b 1

:start_run
set "DBG_PS1=%TEMP%\Debug-CMD_%RANDOM%.ps1"
echo  Preparing the PowerShell engine...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:DBG_SELF,[Text.Encoding]::UTF8); $i=$t.IndexOf('#PS'+'_BEGIN'); [IO.File]::WriteAllText($env:DBG_PS1,$t.Substring($i),(New-Object Text.UTF8Encoding $true))"
if errorlevel 1 goto :ps_failed
if not exist "%DBG_PS1%" goto :ps_failed
echo  Running...
powershell -NoProfile -ExecutionPolicy Bypass -File "%DBG_PS1%"
set "RC=%errorlevel%"
echo.
if "%RC%"=="0" del "%DBG_PS1%" >nul 2>&1
if not "%RC%"=="0" echo  Exit code: %RC%  (PowerShell engine kept at "%DBG_PS1%" for diagnostics)
echo.
pause
exit /b %RC%

:ps_failed
echo.
echo  Failed to prepare the PowerShell engine. See the error message above.
echo.
pause
exit /b 1

:no_file
echo.
echo  Drag a .cmd or .bat file onto this file.
echo.
pause
exit /b 1

#PS_BEGIN
$ErrorActionPreference = 'Stop'
$Alvo     = $env:DBG_TARGET
$EchoOn   = ($env:ECHO_ON -ne '0')
$IgnPause = ($env:SKIP_PAUSE -ne '0')
$AbrirLog = ($env:OPEN_REPORT -ne '0')
$LogPs1   = ($env:LOG_PS1 -ne '0')
$utf8bom  = New-Object System.Text.UTF8Encoding($true)

if (-not (Test-Path -LiteralPath $Alvo -PathType Leaf)) {
    Write-Host "File not found: $Alvo" -ForegroundColor Red
    exit 2
}

$pasta   = [IO.Path]::GetDirectoryName($Alvo)
$nome    = [IO.Path]::GetFileNameWithoutExtension($Alvo)
$ext     = [IO.Path]::GetExtension($Alvo)
$inicio  = Get-Date

# ---------- HTML report helpers ----------
function EscHtml([string]$s) { return [System.Net.WebUtility]::HtmlEncode($s) }

function Gravar-Html([string]$caminho, [string]$titulo, [string]$estado, [string]$classe, $cartoes, $info, [string]$corpo) {
$css = @'
:root{--bg:#fff;--fg:#1f2328;--mut:#656d76;--card:#f6f8fa;--bd:#d0d7de;--ok:#1a7f37;--bad:#cf222e;--warn:#9a6700;--acc:#0969da}
@media (prefers-color-scheme:dark){:root{--bg:#0d1117;--fg:#e6edf3;--mut:#8b949e;--card:#161b22;--bd:#30363d;--ok:#3fb950;--bad:#f85149;--warn:#d29922;--acc:#58a6ff}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.5 system-ui,"Segoe UI",sans-serif}
main{max-width:1100px;margin:0 auto;padding:24px 16px 64px}
header{display:flex;align-items:center;gap:12px;flex-wrap:wrap;margin-bottom:16px}
h1{font-size:22px;margin:0;word-break:break-all}
h2{font-size:17px;margin:32px 0 10px;padding-bottom:6px;border-bottom:1px solid var(--bd)}
.badge{padding:3px 12px;border-radius:999px;font-weight:600;font-size:13px;color:#fff}
.badge.ok{background:var(--ok)}.badge.bad{background:var(--bad)}.badge.warn{background:var(--warn)}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:10px;margin:12px 0}
.card{background:var(--card);border:1px solid var(--bd);border-radius:8px;padding:12px}
.card .v{font-size:24px;font-weight:600}.card .k{color:var(--mut);font-size:12px}
.v.ok{color:var(--ok)}.v.bad{color:var(--bad)}.v.warn{color:var(--warn)}
table{border-collapse:collapse;width:100%}
.info th{text-align:left;color:var(--mut);font-weight:500;padding:4px 12px 4px 0;white-space:nowrap;vertical-align:top}
.info td{padding:4px 0;word-break:break-all}
code,pre,#log td{font-family:ui-monospace,Consolas,monospace;font-size:12.5px}
details{background:var(--card);border:1px solid var(--bd);border-radius:8px;margin:8px 0}
details.fail{border-left:4px solid var(--bad)}
summary{cursor:pointer;padding:8px 12px;display:flex;flex-wrap:wrap;gap:4px 10px;align-items:baseline}
pre{margin:0;padding:8px 12px 12px;overflow-x:auto;white-space:pre-wrap;word-break:break-word}
.t{color:var(--mut);font-family:ui-monospace,Consolas,monospace;font-size:12px;white-space:nowrap;padding-right:10px}
.err{color:var(--bad);font-weight:600}
.none{color:var(--ok)}
.tools{display:flex;gap:6px;margin:8px 0}
.tools button{background:var(--card);color:var(--fg);border:1px solid var(--bd);border-radius:6px;padding:4px 12px;cursor:pointer}
.tools button.on{background:var(--acc);color:#fff;border-color:var(--acc)}
#log td{padding:1px 6px;vertical-align:top;white-space:pre-wrap;word-break:break-word}
#log tr.cmd td{color:var(--acc);font-weight:600;border-top:1px solid var(--bd)}
#log tr.err td:last-child{color:var(--bad);font-weight:600}
body[data-filter=cmd] #log tr:not(.cmd){display:none}
body[data-filter=err] #log tr:not(.err){display:none}
.lv{font-weight:700;font-size:11px;padding:1px 7px;border-radius:4px;color:#fff}
.lv.HIGH,.lv.ERROR{background:var(--bad)}.lv.MEDIUM{background:var(--warn)}.lv.LOW{background:var(--mut)}.lv.PS{background:var(--acc)}
.list td{padding:3px 8px 3px 0;vertical-align:top}
#log tr.ps td:last-child{color:var(--warn);font-style:italic}
.meta{color:var(--mut);font-size:12px;font-weight:400;overflow-wrap:anywhere}
.list code,summary code{overflow-wrap:anywhere}
.list td.t{white-space:normal;overflow-wrap:anywhere}
.sub{color:var(--mut);font-size:12px;word-break:break-all}
.src{margin:0 0 8px}
.src td{font-family:ui-monospace,Consolas,monospace;font-size:12.5px;padding:0 8px;vertical-align:top;white-space:pre-wrap;word-break:break-word}
.src td.n{color:var(--mut);text-align:right;user-select:none;width:1%;white-space:nowrap}
.src tr.e td{background:rgba(207,34,46,.14)}
.src tr.e td.n{color:var(--bad);font-weight:700}
.ver{color:var(--mut);font-size:12px;padding:8px 12px 4px}
'@
$js = @'
document.querySelectorAll('[data-f]').forEach(function(b){b.addEventListener('click',function(){document.body.setAttribute('data-filter',b.getAttribute('data-f'));document.querySelectorAll('[data-f]').forEach(function(x){x.classList.toggle('on',x===b)})})});
'@
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<!doctype html>')
    [void]$sb.AppendLine('<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">')
    [void]$sb.AppendLine('<title>' + (EscHtml $titulo) + '</title><style>' + $css + '</style></head><body data-filter="all"><main>')
    [void]$sb.AppendLine('<header><h1>' + (EscHtml $titulo) + '</h1><span class="badge ' + $classe + '">' + (EscHtml $estado) + '</span></header>')
    [void]$sb.AppendLine('<div class="cards">')
    foreach ($c in $cartoes) {
        [void]$sb.AppendLine('<div class="card"><div class="v ' + $c[2] + '">' + (EscHtml ([string]$c[1])) + '</div><div class="k">' + (EscHtml ([string]$c[0])) + '</div></div>')
    }
    [void]$sb.AppendLine('</div><table class="info">')
    foreach ($i2 in $info) {
        [void]$sb.AppendLine('<tr><th>' + (EscHtml ([string]$i2[0])) + '</th><td>' + (EscHtml ([string]$i2[1])) + '</td></tr>')
    }
    [void]$sb.AppendLine('</table>')
    [void]$sb.AppendLine($corpo)
    [void]$sb.AppendLine('</main><script>' + $js + '</script></body></html>')
    [IO.File]::WriteAllText($caminho, $sb.ToString(), $utf8bom)
}

# ---------- PowerShell helpers (both modes) ----------
# a PowerShell executable in a command: powershell, pwsh, "C:\...\powershell.exe"
$rxPsExe = '(?i)(?:^|[\s(''"&|=\\])(?:powershell|pwsh)(?:\.exe)?(?=["'']?(?:\s|$))'

function Ps-Curto([string]$s, [int]$max) {
    $s = ($s -replace '\s+', ' ').Trim()
    if ($s.Length -gt $max) { $s = $s.Substring(0, $max) + ' [...]' }
    return $s
}

function Ps-Normalizar([string]$s) {
    return ((($s -replace '["'']', '') -replace '\s+', ' ').Trim().ToLowerInvariant())
}

# decodes the -EncodedCommand of a PowerShell command line (Base64 of UTF-16LE text)
function Ps-Decodificar([string]$linha) {
    foreach ($m in [regex]::Matches($linha, '(?i)(?:^|\s)[-/](?<p>e\w*)\s+["'']?(?<b>[A-Za-z0-9+/]{8,}={0,2})')) {
        $p = $m.Groups['p'].Value.ToLowerInvariant()
        if (($p -ne 'ec') -and (-not 'encodedcommand'.StartsWith($p))) { continue }
        try { return [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($m.Groups['b'].Value)) } catch { }
    }
    return $null
}

# every .ps1 path mentioned in a command line (quoted or not)
function Ps-Ps1Tokens([string]$t) {
    $r = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($t, '(?i)"([^"]*?\.ps1)(?=["\s]|$)|''([^'']*?\.ps1)''|([^\s"''<>|&()=,;]+?\.ps1)(?![\w.])')) {
        $v = ($m.Groups[1].Value + $m.Groups[2].Value + $m.Groups[3].Value).Trim()
        $v = $v -replace '(?i)^-\w+:', ''
        if (($v.Length -gt 0) -and (-not $r.Contains($v))) { $r.Add($v) }
    }
    return ,$r
}

# the .ps1 files a PowerShell command line actually runs: -File x.ps1, & 'x.ps1', powershell x.ps1
function Ps-Ps1Corridos([string]$t) {
    $r = New-Object System.Collections.Generic.List[string]
    $rx = '(?i)(?:[-/]f(?:i(?:le?)?)?\s+|[-/]file:|&\s*|(?:powershell|pwsh)(?:\.exe)?["'']?\s+)("[^"]+?\.ps1"|''[^'']+?\.ps1''|[^\s"''<>|&()]+?\.ps1)(?![\w.])'
    foreach ($m in [regex]::Matches($t, $rx)) {
        $v = $m.Groups[1].Value.Trim().Trim('"', "'")
        if (($v.Length -gt 0) -and (-not $r.Contains($v))) { $r.Add($v) }
    }
    return ,$r
}

# full path of a .ps1 reference, or $null when it can't be known (unexpanded variables, wildcards)
function Ps-Resolver([string]$p, [string]$base) {
    $p = $p.Trim().Trim('"', "'")
    if (($p.Length -eq 0) -or ($p -match '[%!$*?]')) { return $null }
    try {
        if (-not [IO.Path]::IsPathRooted($p)) {
            if (-not $base) { return $null }
            $p = [IO.Path]::Combine($base, $p)
        }
        return [IO.Path]::GetFullPath($p)
    } catch { return $null }
}

# reads a .ps1 the way Windows PowerShell does (BOM, otherwise the ANSI code page), even while it's open
function Ps-Ler([string]$c) {
    try {
        $fi = New-Object IO.FileInfo($c)
        if (-not $fi.Exists) { return $null }
        if ($fi.Length -gt 2MB) { return ('[Debug-CMD] not logged: the file has ' + $fi.Length + ' bytes (limit 2 MB)') }
        $fs = New-Object IO.FileStream($c, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        try {
            $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::Default, $true)
            return $sr.ReadToEnd()
        } finally { $fs.Dispose() }
    } catch { return $null }
}

function Ps-Linhas([string]$t) {
    $a = @($t -split "\r?\n")
    if (($a.Count -gt 1) -and ($a[$a.Count - 1].Length -eq 0)) { $a = @($a[0..($a.Count - 2)]) }
    return ,$a
}

# PowerShell writes errors/warnings as CLIXML when its stderr is redirected: turn that back into text
function Ps-Clixml([string]$x) {
    $saida = New-Object System.Collections.Generic.List[string]
    $fluxo = $null
    $sb    = New-Object System.Text.StringBuilder
    $pref  = @{ warning = 'WARNING: '; verbose = 'VERBOSE: '; debug = 'DEBUG: ' }
    $despejar = {
        if ($null -eq $fluxo) { return }
        $txt = [regex]::Replace($sb.ToString(), '_x([0-9A-Fa-f]{4})_', { param($mm) [string][char][Convert]::ToInt32($mm.Groups[1].Value, 16) })
        $txt = [System.Net.WebUtility]::HtmlDecode($txt)
        $pf  = $(if ($pref.ContainsKey($fluxo)) { $pref[$fluxo] } else { '' })
        foreach ($ln in ($txt -split "\r?\n")) { if ($ln.Trim().Length -gt 0) { $saida.Add($pf + $ln.TrimEnd()) } }
    }
    foreach ($m in [regex]::Matches($x, '<S S="(?<s>[^"]+)">(?<v>[^<]*)</S>')) {
        $s = $m.Groups['s'].Value.ToLowerInvariant()
        if ($s -ne $fluxo) { . $despejar; $fluxo = $s; [void]$sb.Clear() }
        [void]$sb.Append($m.Groups['v'].Value)
    }
    . $despejar
    return ,$saida
}

# a .ps1 with line numbers; $erros = line numbers where PowerShell reported an error
function Texto-Fonte([string]$texto, $erros) {
    $out = New-Object System.Collections.Generic.List[string]
    $ls  = Ps-Linhas $texto
    $nl  = 0
    foreach ($tl in $ls) {
        $nl++
        if ($nl -gt 20000) { $out.Add('        ... (' + ($ls.Count - 20000) + ' more lines not shown)'); break }
        $mk = $(if (($null -ne $erros) -and $erros.ContainsKey($nl)) { '>>' } else { '  ' })
        $out.Add(('{0}{1,5} | {2}' -f $mk, $nl, $tl))
    }
    return ,$out
}

function Html-Fonte([string]$texto, $erros) {
    $sb2 = New-Object System.Text.StringBuilder
    [void]$sb2.AppendLine('<table class="src">')
    $ls = Ps-Linhas $texto
    $nl = 0
    foreach ($tl in $ls) {
        $nl++
        if ($nl -gt 20000) { [void]$sb2.AppendLine('<tr><td class="n"></td><td>... (' + ($ls.Count - 20000) + ' more lines not shown)</td></tr>'); break }
        $er = (($null -ne $erros) -and $erros.ContainsKey($nl))
        [void]$sb2.AppendLine('<tr' + $(if ($er) { ' class="e" title="PowerShell reported an error at this line"' } else { '' }) + '><td class="n">' + $nl + '</td><td>' + (EscHtml $tl) + '</td></tr>')
    }
    [void]$sb2.AppendLine('</table>')
    return $sb2.ToString()
}

# ---------- TEST mode: static analysis, NOTHING is executed ----------
if ($env:DBG_MODE -eq 'TEST') {
    $latin = [Text.Encoding]::GetEncoding(28591)
    $src   = [IO.File]::ReadAllText($Alvo, $latin) -split "\r?\n"
    $regras = @(
        @('HIGH',   '\b(del|erase)\b',                           'Deletes files'),
        @('HIGH',   '\b(rd|rmdir)\b',                            'Removes folders'),
        @('HIGH',   '\bformat(\.com)?\s+[a-z]:',                 'Formats a drive'),
        @('HIGH',   '\bdiskpart\b',                              'Disk partitioning tool'),
        @('HIGH',   '\bcipher\b.*\s/w',                          'Wipes free disk space'),
        @('HIGH',   '\breg\s+delete\b',                          'Deletes registry keys or values'),
        @('HIGH',   '\bbcdedit\b',                               'Changes the boot configuration'),
        @('HIGH',   '\b(shutdown|logoff)\b',                     'Shuts down or logs off'),
        @('HIGH',   '\bnet\s+user\b',                            'Changes user accounts'),
        @('HIGH',   '\bsc(\.exe)?\s+(delete|stop|config)\b',     'Changes or removes services'),
        @('HIGH',   '\brobocopy\b.*\s/(mir|purge)\b',            'Mirror/purge deletes files at the destination'),
        @('HIGH',   '\s-(enc|encodedcommand)\b',                 'Runs an encoded PowerShell command'),
        @('HIGH',   '\bRemove-Item(Property)?\b',                'PowerShell: deletes files, folders or registry values'),
        @('HIGH',   '\b(Format-Volume|Clear-Disk|Initialize-Disk|Remove-Partition)\b', 'PowerShell: erases or formats disks'),
        @('HIGH',   '\b(Remove-AppxPackage|Remove-AppxProvisionedPackage|Uninstall-Package)\b', 'PowerShell: removes apps'),
        @('HIGH',   '\b(Stop-Computer|Restart-Computer)\b',      'PowerShell: shuts down or restarts'),
        @('HIGH',   '\b(Set-MpPreference|Add-MpPreference)\b',   'PowerShell: changes Microsoft Defender settings'),
        @('HIGH',   '\b(Remove-LocalUser|Set-LocalUser|Disable-LocalUser|Add-LocalGroupMember)\b', 'PowerShell: changes user accounts'),
        @('MEDIUM', '\breg\s+(add|import)\b',                    'Changes the registry'),
        @('MEDIUM', '\b(Set-ItemProperty|New-ItemProperty|Rename-ItemProperty)\b', 'PowerShell: changes the registry'),
        @('MEDIUM', '\b(Stop-Service|Set-Service|Restart-Service|New-Service)\b', 'PowerShell: changes services'),
        @('MEDIUM', '\bStop-Process\b',                          'PowerShell: kills processes'),
        @('MEDIUM', '\b(Register|Unregister|Disable|Set)-ScheduledTask\b', 'PowerShell: changes scheduled tasks'),
        @('MEDIUM', '\b(New|Set|Remove)-NetFirewallRule\b|\b(Set-DnsClientServerAddress|Disable-NetAdapter)\b', 'PowerShell: changes network or firewall settings'),
        @('MEDIUM', '\b(Install-Package|Install-Module|Add-AppxPackage|Enable-WindowsOptionalFeature|Disable-WindowsOptionalFeature)\b', 'PowerShell: installs or removes software or features'),
        @('MEDIUM', '\bSet-ExecutionPolicy\b',                   'PowerShell: changes the script execution policy'),
        @('MEDIUM', '\b(Invoke-Expression|iex)\b',               'PowerShell: runs code built from text'),
        @('MEDIUM', '\b(Move-Item|Rename-Item|Copy-Item)\b',     'PowerShell: moves, renames or copies files'),
        @('MEDIUM', '\b(move|ren|rename)\b(?!-)',                'Moves or renames files'),
        @('MEDIUM', '\b(copy|xcopy|robocopy)\b(?!-)',            'Copies files (may overwrite)'),
        @('MEDIUM', '\btaskkill\b',                              'Kills processes'),
        @('MEDIUM', '\bnet\s+(stop|start|use)\b',                'Stops/starts services or maps network drives'),
        @('MEDIUM', '\bschtasks\b',                              'Creates or changes scheduled tasks'),
        @('MEDIUM', '\bsetx\b',                                  'Sets permanent environment variables'),
        @('MEDIUM', '\bnetsh\b',                                 'Changes network or firewall settings'),
        @('MEDIUM', '\b(winget|choco|scoop|msiexec)\b',          'Installs or removes software'),
        @('MEDIUM', '\b(curl|wget|bitsadmin|certutil|Invoke-WebRequest|iwr|DownloadFile|DownloadString)\b', 'Downloads from the internet'),
        @('MEDIUM', '\b(takeown|icacls|cacls)\b',                'Changes file ownership or permissions'),
        @('MEDIUM', '\b(dism|sfc)\b',                            'System repair/servicing tool'),
        @('MEDIUM', '\bwmic\b',                                  'Uses WMI (can change the system)'),
        @('MEDIUM', '\b(assoc|ftype)\b',                         'Changes file associations'),
        @('LOW',    '\b(powershell|pwsh)\b',                     'Runs PowerShell'),
        @('LOW',    '\b(Set-Content|Add-Content|Out-File)\b',    'PowerShell: writes files'),
        @('LOW',    '\bstart\b(?!-)',                            'Starts another program'),
        @('LOW',    '\battrib\b',                                'Changes file attributes'),
        @('LOW',    '\bmklink\b',                                'Creates links'),
        @('LOW',    '\bset\s+/p\b',                              'Waits for user input')
    )
    $rotulos   = @{}
    $saltos    = New-Object System.Collections.Generic.List[object]
    $achados   = New-Object System.Collections.Generic.List[string]
    $problemas = New-Object System.Collections.Generic.List[string]
    $cont      = @{ HIGH = 0; MEDIUM = 0; LOW = 0 }
    $achadosObj = New-Object System.Collections.Generic.List[object]
    $comandos  = 0
    $precisaAdmin = $false
    $psEscreve = New-Object System.Collections.Generic.List[object]   # lines that write a .ps1
    $psCorre   = New-Object System.Collections.Generic.List[object]   # lines that run PowerShell
    $psRefs    = @{}                                                   # .ps1 files mentioned
    $psOrdem   = New-Object System.Collections.Generic.List[string]

    function Verificar([string]$texto, [string]$onde) {
        $ex2 = $texto.Trim()
        if ($ex2.Length -gt 160) { $ex2 = $ex2.Substring(0, 160) + ' [...]' }
        $soDefine = (($texto.Trim() -match '(?i)^@?set\s') -or ($texto.Trim() -match '(?i)^if\s+(not\s+)?exist\s+("[^"]*"|\S+)\s+set\s'))
        foreach ($r in $regras) {
            if ($soDefine -and ($r[2] -eq 'Runs PowerShell')) { continue }
            if ($texto -match ('(?i)' + $r[1])) {
                $cont[$r[0]]++
                $achados.Add(('[{0}] {1}: {2}' -f $r[0], $onde, $r[2]))
                $achados.Add('           ' + $ex2)
                $achadosObj.Add(@($r[0], $onde, $r[2], $ex2))
            }
        }
    }
    # resolves %~dp0 and environment variables the way they would be at run time (best effort)
    function Ps-Referir([string]$bruto, [int]$linha) {
        $bruto = $bruto.Trim().Trim('"', "'")
        $exp = $bruto -ireplace '%~dp0', ($pasta.TrimEnd('\') + '\').Replace('$', '$$')
        $exp = [Environment]::ExpandEnvironmentVariables($exp)
        $c = Ps-Resolver $exp $pasta
        $k = $(if ($c) { $c } else { $bruto })
        if (-not $psRefs.ContainsKey($k)) {
            $psRefs[$k] = [pscustomobject]@{ Bruto = $bruto; Path = $c; Linhas = (New-Object System.Collections.Generic.List[int]); Texto = $null }
            $psOrdem.Add($k)
        }
        if (-not $psRefs[$k].Linhas.Contains($linha)) { $psRefs[$k].Linhas.Add($linha) }
    }
    function Ps-EstadoRef($rf) {
        $onde = $(if ($rf.Linhas.Count -gt 1) { 'lines ' } else { 'line ' }) + ($rf.Linhas -join ', ')
        if ($null -ne $rf.Texto) { $nlin = (Ps-Linhas $rf.Texto).Count; $est = 'found on disk, ' + $nlin + $(if ($nlin -eq 1) { ' line' } else { ' lines' }) + ', analyzed above' }
        elseif ($rf.Path) { $est = 'not found now (probably created when the script runs)' }
        else { $est = 'the path depends on run-time variables' }
        return ($est + '; mentioned at ' + $onde)
    }

    $emPs = $false   # true after a #PS-BEGIN style marker: the rest is PowerShell, not batch
    for ($n = 0; $n -lt $src.Count; $n++) {
        $t = $src[$n].Trim()
        if ($t.Length -eq 0) { continue }
        if ((-not $emPs) -and ($t -match '^#\s*PS[-_ ]?BEGIN\b')) { $emPs = $true; continue }
        if ($emPs) {
            # embedded PowerShell: only the risk rules apply (no labels, goto/call or batch command checks)
            if ($t.StartsWith('#')) { continue }
            Verificar $t ('line ' + ($n + 1))
            if ($t -match '(?i)\b(bcdedit|netsh|takeown|dism|sfc|schtasks|diskpart)\b') { $precisaAdmin = $true }
            continue
        }
        if ($t -match '^(@?rem(\s|$)|::)') { continue }
        $mr = [regex]::Match($t, '^:([^\s:]\S*)')
        if ($mr.Success) { $rotulos[$mr.Groups[1].Value.ToLower()] = $n + 1; continue }
        $comandos++
        $ex = $t
        if ($ex.Length -gt 160) { $ex = $ex.Substring(0, 160) + ' [...]' }

        Verificar $t ('line ' + ($n + 1))

        if ($LogPs1) {
            # writes a .ps1 (echo ... > x.ps1)
            foreach ($mw in [regex]::Matches($t, '(?i)>\s*("[^"]+?\.ps1"|[^\s"<>|&()]+?\.ps1)(?![\w.])')) {
                $psEscreve.Add(@(($n + 1), $mw.Groups[1].Value.Trim('"')))
                Ps-Referir $mw.Groups[1].Value ($n + 1)
            }
            # runs PowerShell
            if (($t -match $rxPsExe) -and ($t -notmatch '(?i)^@?(echo([\s.:(]|$)|set\s)') -and ($t -notmatch '(?i)^if\s+(not\s+)?exist\s+("[^"]*"|\S+)\s+set\s')) {
                $dec = Ps-Decodificar $t
                $psCorre.Add(@(($n + 1), $ex, $dec))
                if ($dec) {
                    $d = 0
                    foreach ($dl in (Ps-Linhas $dec)) { $d++; if ($dl.Trim().Length -gt 0) { Verificar $dl ('line ' + ($n + 1) + ' (decoded -EncodedCommand, line ' + $d + ')') } }
                }
                foreach ($tk in (Ps-Ps1Tokens ($t + ' ' + $dec))) { Ps-Referir $tk ($n + 1) }
            }
        }
        if ($t -match '(?i)\b(bcdedit|netsh|takeown|dism|sfc|schtasks|diskpart)\b|\bsc(\.exe)?\s|\breg\s+(add|delete|import)\s+"?hk(lm|ey_local_machine)') { $precisaAdmin = $true }

        foreach ($mg in [regex]::Matches($t, '(?i)\bgoto\s+:?([^\s&|)"%!]+)')) {
            $alvoSalto = $mg.Groups[1].Value.ToLower()
            if ($alvoSalto -ne 'eof') { $saltos.Add(@(($n + 1), $alvoSalto)) }
        }
        foreach ($mg in [regex]::Matches($t, '(?i)\bcall\s+:([^\s&|)"%!]+)')) {
            $saltos.Add(@(($n + 1), $mg.Groups[1].Value.ToLower()))
        }
        foreach ($mf in [regex]::Matches($t, '(?i)\bcall\s+"?([^\s"&|%!:][^"&|%!]*?\.(?:cmd|bat))\b')) {
            $fch  = $mf.Groups[1].Value
            $full = $(if ([IO.Path]::IsPathRooted($fch)) { $fch } else { Join-Path $pasta $fch })
            if (-not (Test-Path -LiteralPath $full)) {
                $problemas.Add(('[ERROR] line {0}: calls "{1}" but that file was not found' -f ($n + 1), $fch))
            }
        }
    }
    foreach ($s in $saltos) {
        if (-not $rotulos.ContainsKey($s[1])) {
            $problemas.Add(('[ERROR] line {0}: jumps to label ":{1}" which does not exist' -f $s[0], $s[1]))
        }
    }

    # .ps1 files the script mentions that are already on disk: analyze them with the same rules
    foreach ($k in $psOrdem) {
        $rf = $psRefs[$k]
        if (-not $rf.Path) { continue }
        $rf.Texto = Ps-Ler $rf.Path
        if ($null -eq $rf.Texto) { continue }
        $nomePs  = [IO.Path]::GetFileName($rf.Path)
        $emBloco = $false
        $nl = 0
        foreach ($pl in (Ps-Linhas $rf.Texto)) {
            $nl++
            $tp = $pl.Trim()
            if ($emBloco) { if ($tp.Contains('#>')) { $emBloco = $false }; continue }
            if ($tp.StartsWith('<#')) { if (-not $tp.Contains('#>')) { $emBloco = $true }; continue }
            if (($tp.Length -eq 0) -or $tp.StartsWith('#')) { continue }
            Verificar $tp ($nomePs + ' line ' + $nl)
        }
    }

    $veredito = $(if ($cont.HIGH -gt 0) { 'HIGH RISK: review the flagged lines before running this script' }
                  elseif (($cont.MEDIUM -gt 0) -or ($problemas.Count -gt 0)) { 'MODERATE: the script changes things; review the flagged lines' }
                  else { 'No risky commands recognized (this is a keyword scan, not a guarantee)' })

    $sepT = '=' * 78
    $rel  = New-Object System.Collections.Generic.List[string]
    $rel.Add($sepT); $rel.Add(' TEST MODE - STATIC ANALYSIS (NOTHING WAS EXECUTED)'); $rel.Add($sepT)
    $rel.Add("Script        : $Alvo")
    $rel.Add('Date          : ' + $inicio.ToString('yyyy-MM-dd HH:mm:ss'))
    $rel.Add("Size          : $($src.Count) lines, $comandos commands")
    $rel.Add("Verdict       : $veredito")
    $rel.Add("Findings      : $($cont.HIGH) high | $($cont.MEDIUM) medium | $($cont.LOW) low | $($problemas.Count) structural problems")
    if ($precisaAdmin) { $rel.Add('Note           : probably needs administrator rights.') }
    $rel.Add('')
    $rel.Add($sepT); $rel.Add(' STRUCTURAL PROBLEMS'); $rel.Add($sepT)
    if ($problemas.Count -eq 0) { $rel.Add('None found.') } else { foreach ($x in $problemas) { $rel.Add($x) } }
    $rel.Add('')
    $rel.Add($sepT); $rel.Add(' COMMANDS THAT CAN CHANGE THE SYSTEM'); $rel.Add($sepT)
    if ($achados.Count -eq 0) { $rel.Add('None recognized.') } else { foreach ($x in $achados) { $rel.Add($x) } }
    $psTextos = @($psOrdem | Where-Object { $null -ne $psRefs[$_].Texto })
    if ($LogPs1) {
        $rel.Add('')
        $rel.Add($sepT); $rel.Add(' POWERSHELL'); $rel.Add($sepT)
        if (($psEscreve.Count + $psCorre.Count + $psOrdem.Count) -eq 0) { $rel.Add('Not used: no PowerShell commands or .ps1 files found in the script text.') }
        foreach ($w in $psEscreve) { $rel.Add(('[WRITES] line {0}: {1}' -f $w[0], $w[1])) }
        foreach ($w in $psCorre) {
            $rel.Add(('[RUNS]   line {0}: {1}' -f $w[0], $w[1]))
            if ($w[2]) { $rel.Add('           > decoded -EncodedCommand: ' + (Ps-Curto $w[2] 300)) }
        }
        foreach ($k in $psOrdem) {
            $rf = $psRefs[$k]
            $rel.Add(('[PS1]    {0}' -f $(if ($rf.Path) { $rf.Path } else { $rf.Bruto })))
            $rel.Add('           > ' + (Ps-EstadoRef $rf))
        }
    }
    $rel.Add('')
    $rel.Add('Notes: nothing was run and no variable was expanded (except %~dp0 and environment variables, to find .ps1 files).')
    $rel.Add('Commands built from variables, scripts it calls, and anything decided at run time are not analyzed.')
    $rel.Add('Use RUN mode only if you trust the script.')
    if ($LogPs1 -and ($psOrdem.Count -gt 0)) { $rel.Add('RUN mode logs the .ps1 files the script writes and runs, with their full contents, even if it deletes them.') }

    # full contents of the .ps1 files found (in the file only, not on screen)
    $anexo = New-Object System.Collections.Generic.List[string]
    if ($LogPs1 -and ($psTextos.Count -gt 0)) {
        $anexo.Add('')
        $anexo.Add($sepT); $anexo.Add(' .PS1 FILES FOUND ON DISK - FULL CONTENTS'); $anexo.Add($sepT)
        foreach ($k in $psTextos) {
            $anexo.Add('')
            $anexo.Add('---- ' + $psRefs[$k].Path)
            foreach ($x in (Texto-Fonte $psRefs[$k].Texto $null)) { $anexo.Add($x) }
        }
    }

    $testLog = Join-Path $pasta ('{0}_test_{1}.log' -f $nome, $inicio.ToString('yyyy-MM-dd_HH-mm-ss'))
    $todoT   = [string[]](@($rel.ToArray()) + @($anexo.ToArray()))
    try { [IO.File]::WriteAllLines($testLog, $todoT, $utf8bom) }
    catch {
        $testLog = Join-Path $env:TEMP ([IO.Path]::GetFileName($testLog))
        [IO.File]::WriteAllLines($testLog, $todoT, $utf8bom)
    }

    $htmlTest = $null
    if ($env:GENERATE_HTML -ne '0') {
        try {
            $clsT = 'ok'
            if ($cont.HIGH -gt 0) { $clsT = 'bad' } elseif (($cont.MEDIUM -gt 0) -or ($problemas.Count -gt 0)) { $clsT = 'warn' }
            $txtT = $(if ($cont.HIGH -gt 0) { 'HIGH RISK' } elseif (($cont.MEDIUM -gt 0) -or ($problemas.Count -gt 0)) { 'MODERATE' } else { 'NO RISKS FOUND' })
            $cartT = New-Object System.Collections.Generic.List[object]
            $cartT.Add(@('High risk', $cont.HIGH, $(if ($cont.HIGH -gt 0) { 'bad' } else { 'ok' })))
            $cartT.Add(@('Medium', $cont.MEDIUM, $(if ($cont.MEDIUM -gt 0) { 'warn' } else { 'ok' })))
            $cartT.Add(@('Low', $cont.LOW, ''))
            $cartT.Add(@('Structural problems', $problemas.Count, $(if ($problemas.Count -gt 0) { 'bad' } else { 'ok' })))
            $cartT.Add(@('Commands', $comandos, ''))
            if ($LogPs1 -and (($psCorre.Count + $psOrdem.Count) -gt 0)) {
                $cartT.Add(@('PowerShell runs', $psCorre.Count, ''))
                $cartT.Add(@('.ps1 files', $psOrdem.Count, ''))
            }
            $infoT = New-Object System.Collections.Generic.List[object]
            $infoT.Add(@('Script', $Alvo))
            $infoT.Add(@('Mode', 'TEST - static analysis, nothing was executed'))
            $infoT.Add(@('Date', $inicio.ToString('yyyy-MM-dd HH:mm:ss')))
            $infoT.Add(@('Verdict', $veredito))
            if ($precisaAdmin) { $infoT.Add(@('Note', 'Probably needs administrator rights')) }
            $bT = New-Object System.Text.StringBuilder
            [void]$bT.AppendLine('<h2>Structural problems</h2>')
            if ($problemas.Count -eq 0) { [void]$bT.AppendLine('<p class="none">None found.</p>') } else {
                [void]$bT.AppendLine('<table class="list">')
                foreach ($x in $problemas) { [void]$bT.AppendLine('<tr><td><span class="lv ERROR">ERROR</span></td><td>' + (EscHtml ($x -replace '^\[ERROR\]\s*', '')) + '</td></tr>') }
                [void]$bT.AppendLine('</table>')
            }
            [void]$bT.AppendLine('<h2>Commands that can change the system</h2>')
            if ($achadosObj.Count -eq 0) { [void]$bT.AppendLine('<p class="none">None recognized.</p>') } else {
                [void]$bT.AppendLine('<table class="list">')
                foreach ($a in $achadosObj) {
                    [void]$bT.AppendLine('<tr><td><span class="lv ' + $a[0] + '">' + $a[0] + '</span></td><td class="t">' + (EscHtml ([string]$a[1])) + '</td><td>' + (EscHtml ([string]$a[2])) + '<br><code>' + (EscHtml ([string]$a[3])) + '</code></td></tr>')
                }
                [void]$bT.AppendLine('</table>')
            }
            if ($LogPs1) {
                [void]$bT.AppendLine('<h2>PowerShell</h2>')
                if (($psEscreve.Count + $psCorre.Count + $psOrdem.Count) -eq 0) {
                    [void]$bT.AppendLine('<p class="none">Not used: no PowerShell commands or .ps1 files found in the script text.</p>')
                } else {
                    [void]$bT.AppendLine('<table class="list">')
                    foreach ($w in $psEscreve) { [void]$bT.AppendLine('<tr><td><span class="lv PS">WRITES</span></td><td class="t">line ' + $w[0] + '</td><td><code>' + (EscHtml ([string]$w[1])) + '</code></td></tr>') }
                    foreach ($w in $psCorre) {
                        $dx = $(if ($w[2]) { '<div class="sub">decoded -EncodedCommand:</div><pre>' + (EscHtml ([string]$w[2])) + '</pre>' } else { '' })
                        [void]$bT.AppendLine('<tr><td><span class="lv PS">RUNS</span></td><td class="t">line ' + $w[0] + '</td><td><code>' + (EscHtml ([string]$w[1])) + '</code>' + $dx + '</td></tr>')
                    }
                    [void]$bT.AppendLine('</table>')
                    foreach ($k in $psOrdem) {
                        $rf = $psRefs[$k]
                        $titulo = $(if ($rf.Path) { $rf.Path } else { $rf.Bruto })
                        if ($null -ne $rf.Texto) {
                            [void]$bT.AppendLine('<details><summary><code>' + (EscHtml $titulo) + '</code><span class="meta">' + (EscHtml (Ps-EstadoRef $rf)) + '</span></summary>' + (Html-Fonte $rf.Texto $null) + '</details>')
                        } else {
                            [void]$bT.AppendLine('<p><code>' + (EscHtml $titulo) + '</code> <span class="meta">' + (EscHtml (Ps-EstadoRef $rf)) + '</span></p>')
                        }
                    }
                }
            }
            [void]$bT.AppendLine('<p class="k" style="color:var(--mut)">Nothing was run and no variable was expanded. Commands built from variables, scripts it calls, and anything decided at run time are not analyzed.' + $(if ($LogPs1 -and ($psOrdem.Count -gt 0)) { ' RUN mode logs the .ps1 files the script writes and runs, with their full contents.' } else { '' }) + '</p>')
            $htmlTest = [IO.Path]::ChangeExtension($testLog, '.html')
            Gravar-Html $htmlTest ('Test report: ' + [IO.Path]::GetFileName($Alvo)) $txtT $clsT $cartT $infoT $bT.ToString()
        } catch {
            $htmlTest = $null
            Write-Host ('Could not create the HTML report: ' + $_.Exception.Message) -ForegroundColor Yellow
        }
    }

    Write-Host ''
    foreach ($x in $rel) {
        $c = 'Gray'
        if ($x -match '^\[(HIGH|ERROR)\]') { $c = 'Red' }
        elseif ($x -match '^\[MEDIUM\]') { $c = 'Yellow' }
        elseif ($x -match '^\[LOW\]') { $c = 'DarkGray' }
        elseif ($x -match '^\[(RUNS|WRITES|PS1)\]') { $c = 'Cyan' }
        elseif ($x -match '^Verdict') { $c = 'Cyan' }
        Write-Host $x -ForegroundColor $c
    }
    Write-Host ''
    Write-Host "Report saved to: $testLog" -ForegroundColor Cyan
    if ($htmlTest) { Write-Host "HTML report: $htmlTest" -ForegroundColor Cyan }
    if ($AbrirLog) {
        if ($htmlTest) { Start-Process -FilePath $htmlTest } else { Start-Process notepad.exe -ArgumentList ('"' + $testLog + '"') }
    }
    exit 0
}
$logPath = Join-Path $pasta ('{0}_debug_{1}.log' -f $nome, $inicio.ToString('yyyy-MM-dd_HH-mm-ss'))
try {
    $sw = New-Object System.IO.StreamWriter($logPath, $false, $utf8bom)
} catch {
    # folder is not writable: use the temp folder
    $logPath = Join-Path $env:TEMP ([IO.Path]::GetFileName($logPath))
    $sw = New-Object System.IO.StreamWriter($logPath, $false, $utf8bom)
}
$sw.AutoFlush = $true

$linhas = New-Object System.Collections.Generic.List[string]
$horas  = New-Object System.Collections.Generic.List[string]
function Gravar-Linha([string]$texto) {
    if ($texto.Length -gt 600) { $texto = $texto.Substring(0, 600) + ' [...]' }
    $h = (Get-Date).ToString('HH:mm:ss.fff')
    $sw.WriteLine("[$h] $texto")
    $linhas.Add($texto)
    $horas.Add($h)
}
function Add-Linha([string]$texto) {
    $texto = ($texto -replace "`r", ' ').TrimEnd()
    $ix = $texto.IndexOf('#< CLIXML')
    if ($ix -ge 0) { $texto = ($texto.Substring(0, $ix) + $texto.Substring($ix + 9)).TrimEnd() }
    if ($texto.Length -eq 0) { return }
    $ix = $texto.IndexOf('<Objs Version=')
    if (($ix -ge 0) -and $texto.Contains('schemas.microsoft.com/powershell/2004/04')) {
        if ($texto.Substring(0, $ix).Trim().Length -gt 0) { Add-Linha $texto.Substring(0, $ix) }
        foreach ($x in (Ps-Clixml $texto.Substring($ix))) { Gravar-Linha $x; Ps-VerSeguro $x }
        return
    }
    Gravar-Linha $texto
    Ps-VerSeguro $texto
}
# Debug-CMD's own notes in the detailed log (never counted as errors)
function Add-Marca([string]$texto) { Gravar-Linha ('[Debug-CMD] ' + $texto) }

# ---------- PowerShell capture ----------
# Live part (C#): a file watcher reads every .ps1 the moment it is written (before the script can
# delete it) and a process watcher finds the PowerShell processes the script starts, even when
# their command is not echoed (@ lines, scripts started with call, start, for /f).
$csCaptura = @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Management;
using System.Text;
using System.Threading;

public class DbgPsCapture : IDisposable
{
    public class Snap { public string Path; public string Content; public string Kind; public DateTime Time; }
    public class Proc { public int Pid; public int ParentPid; public string CommandLine; public DateTime Time; }

    public readonly ConcurrentQueue<Snap> Files = new ConcurrentQueue<Snap>();
    public readonly ConcurrentQueue<Proc> Procs = new ConcurrentQueue<Proc>();
    public readonly ConcurrentQueue<string> Problems = new ConcurrentQueue<string>();
    public readonly List<string> Folders = new List<string>();
    public long MaxBytes = 2 * 1024 * 1024;

    private readonly List<FileSystemWatcher> watchers = new List<FileSystemWatcher>();
    private readonly List<string> recursive = new List<string>();
    private readonly object readLock = new object();
    private readonly Dictionary<int, bool> seen = new Dictionary<int, bool>();
    private readonly Dictionary<int, bool> tree = new Dictionary<int, bool>();
    private readonly string exclude;
    private Timer timer;
    private int busy;
    private int failures;
    private volatile bool disposed;

    public DbgPsCapture(string exclude) { this.exclude = exclude; }

    private bool Ignored(string p)
    {
        if (p == null || !p.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase)) return true;
        if (Path.GetFileName(p).StartsWith("__PSScriptPolicyTest_", StringComparison.OrdinalIgnoreCase)) return true;
        return exclude != null && string.Equals(p, exclude, StringComparison.OrdinalIgnoreCase);
    }

    public bool Watch(string dir, bool subfolders)
    {
        string full, key;
        try
        {
            if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir)) return false;
            full = Path.GetFullPath(dir);
            key = full.TrimEnd('\\', '/') + Path.DirectorySeparatorChar;
        }
        catch { return false; }
        lock (watchers)
        {
            if (disposed) return false;
            foreach (string w in Folders) if (string.Equals(w, key, StringComparison.OrdinalIgnoreCase)) return false;
            foreach (string w in recursive) if (key.StartsWith(w, StringComparison.OrdinalIgnoreCase)) return false;
            try
            {
                FileSystemWatcher fsw = new FileSystemWatcher(full, "*.ps1");
                fsw.IncludeSubdirectories = subfolders;
                fsw.NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.Size;
                fsw.InternalBufferSize = 65536;
                fsw.Created += OnChanged;
                fsw.Changed += OnChanged;
                fsw.Renamed += OnRenamed;
                fsw.Deleted += OnDeleted;
                fsw.Error += OnError;
                fsw.EnableRaisingEvents = true;
                watchers.Add(fsw);
                Folders.Add(key);
                if (subfolders) recursive.Add(key);
                return true;
            }
            catch (Exception ex) { Problems.Enqueue("cannot watch " + dir + ": " + ex.Message); return false; }
        }
    }

    // (an exception escaping a watcher thread would end the whole engine, so every handler catches everything)
    private void OnChanged(object s, FileSystemEventArgs e) { Capture(e.FullPath, "file"); }
    private void OnDeleted(object s, FileSystemEventArgs e)
    {
        try { if (!Ignored(e.FullPath)) Files.Enqueue(Make(e.FullPath, null, "gone")); } catch { }
    }
    private void OnError(object s, ErrorEventArgs e)
    {
        try { Problems.Enqueue("file watcher: " + e.GetException().Message); } catch { }
    }
    private void OnRenamed(object s, RenamedEventArgs e)
    {
        try { if (!Ignored(e.OldFullPath)) Files.Enqueue(Make(e.OldFullPath, null, "gone")); } catch { }
        Capture(e.FullPath, "file");
    }

    private static Snap Make(string path, string content, string kind)
    {
        Snap s = new Snap();
        s.Path = path; s.Content = content; s.Kind = kind; s.Time = DateTime.Now;
        return s;
    }

    // reads the file right away, before the script can delete it
    public void Capture(string path, string kind)
    {
        try { if (Ignored(path)) return; } catch { return; }
        lock (readLock)
        {
            for (int i = 0; i < 8; i++)
            {
                try
                {
                    FileInfo fi = new FileInfo(path);
                    if (!fi.Exists) return;
                    string text;
                    if (fi.Length > MaxBytes) text = "[Debug-CMD] not logged: the file has " + fi.Length + " bytes (limit 2 MB)";
                    else
                    {
                        using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                        using (StreamReader sr = new StreamReader(fs, Encoding.Default, true))
                            text = sr.ReadToEnd();
                    }
                    Files.Enqueue(Make(path, text, kind));
                    return;
                }
                catch (FileNotFoundException) { return; }
                catch (DirectoryNotFoundException) { return; }
                catch (UnauthorizedAccessException ex) { Problems.Enqueue("cannot read " + path + ": " + ex.Message); return; }
                catch (IOException) { Thread.Sleep(30); }
                catch (Exception ex) { Problems.Enqueue("cannot read " + path + ": " + ex.Message); return; }
            }
            Files.Enqueue(Make(path, null, "locked"));
        }
    }

    public void StartProcessWatch(int rootPid, int intervalMs)
    {
        lock (tree) tree[rootPid] = true;
        timer = new Timer(Poll, null, 0, intervalMs);
    }

    private void Poll(object state)
    {
        if (disposed || Interlocked.Exchange(ref busy, 1) == 1) return;
        try
        {
            using (ManagementObjectSearcher q = new ManagementObjectSearcher("SELECT ProcessId,ParentProcessId,CommandLine FROM Win32_Process WHERE Name='powershell.exe' OR Name='pwsh.exe'"))
            using (ManagementObjectCollection col = q.Get())
            {
                foreach (ManagementObject mo in col)
                {
                    using (mo)
                    {
                        int pid = Convert.ToInt32(mo["ProcessId"]);
                        lock (seen) { if (seen.ContainsKey(pid)) continue; seen[pid] = true; }
                        int ppid = Convert.ToInt32(mo["ParentProcessId"]);
                        if (!IsDescendant(ppid)) continue;
                        lock (tree) tree[pid] = true;
                        Proc p = new Proc();
                        p.Pid = pid; p.ParentPid = ppid; p.CommandLine = Convert.ToString(mo["CommandLine"]); p.Time = DateTime.Now;
                        Procs.Enqueue(p);
                    }
                }
            }
        }
        catch (Exception ex)
        {
            if (!disposed) Problems.Enqueue("process watcher: " + ex.Message);
            failures++;
            if (failures == 3)
            {
                try { Timer t = timer; if (t != null) t.Change(Timeout.Infinite, Timeout.Infinite); } catch { }
                Problems.Enqueue("process watcher stopped after repeated errors");
            }
        }
        finally { Interlocked.Exchange(ref busy, 0); }
    }

    // walks up the parent chain until it reaches the debugged script's process
    private bool IsDescendant(int pid)
    {
        List<int> chain = new List<int>();
        for (int depth = 0; depth < 16 && pid > 4; depth++)
        {
            lock (tree)
            {
                if (tree.ContainsKey(pid)) { foreach (int c in chain) tree[c] = true; return true; }
            }
            chain.Add(pid);
            int parent = ParentOf(pid);
            if (parent <= 0 || chain.Contains(parent)) break;
            pid = parent;
        }
        return false;
    }

    private static int ParentOf(int pid)
    {
        try
        {
            using (ManagementObjectSearcher q = new ManagementObjectSearcher("SELECT ParentProcessId FROM Win32_Process WHERE ProcessId=" + pid))
            using (ManagementObjectCollection col = q.Get())
            {
                foreach (ManagementObject mo in col) { using (mo) { return Convert.ToInt32(mo["ParentProcessId"]); } }
            }
        }
        catch { }
        return -1;
    }

    public void Dispose()
    {
        lock (watchers)
        {
            disposed = true;
            if (timer != null) { timer.Dispose(); timer = null; }
            foreach (FileSystemWatcher w in watchers) { try { w.EnableRaisingEvents = false; w.Dispose(); } catch { } }
            watchers.Clear();
        }
    }
}
'@

$psLista    = New-Object System.Collections.Generic.List[object]   # .ps1 files logged, in order of first sight
$psEmbLista = New-Object System.Collections.Generic.List[object]   # code run from memory (also listed in $psLista)
$psMapa     = @{}                                                   # path -> entry of $psLista
$psExec     = New-Object System.Collections.Generic.List[object]   # PowerShell runs
$psNotas    = New-Object System.Collections.Generic.List[string]   # notes about the capture itself
$psSeguidos = @{}                                                   # path -> .ps1 re-read whenever it changes
$psPendProc = New-Object System.Collections.Generic.List[object]   # PowerShell processes waiting for their echoed line
$psEstado   = @{ Pasta = $pasta; Tick = [DateTime]::MinValue; Modo = 'off'; Elevou = $false }
$psCap      = $null
$rxPromptD  = '^(?<d>(?:[A-Za-z]:\\|\\\\)[^>]*)>(?<c>.*)$'

function Ps-Nota([string]$m) {
    $m = Ps-Curto $m 300
    if (($psNotas.Count -lt 20) -and (-not $psNotas.Contains($m))) { $psNotas.Add($m) }
}

function Ps-Ignorar([string]$c) {
    if (-not $c.EndsWith('.ps1', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ([IO.Path]::GetFileName($c).StartsWith('__PSScriptPolicyTest_', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return ($PSCommandPath -and ($c -ieq $PSCommandPath))
}

# keeps every distinct version of a .ps1: a file that is still growing (echo >> x.ps1) is one version
function Ps-Guardar([string]$c, [string]$texto, [string]$origem) {
    if (($null -eq $texto) -or (Ps-Ignorar $c)) { return }
    $e = $psMapa[$c]
    if (-not $e) {
        $e = [pscustomobject]@{ Path = $c; Origem = $origem; Versoes = (New-Object System.Collections.Generic.List[object]); Corridas = 0; Apagado = $false }
        $psMapa[$c] = $e
        $psLista.Add($e)
        Add-Marca ($(if ($origem -eq 'written') { '.ps1 written: ' } else { '.ps1 logged: ' }) + $c)
    }
    $e.Apagado = $false
    $v = $e.Versoes
    if ($v.Count -gt 0) {
        $u = $v[$v.Count - 1]
        if ($u.Texto -ceq $texto) { return }
        if ($u.Texto.StartsWith($texto, [StringComparison]::Ordinal)) { return }   # shorter read while it is rewritten
        if ((-not $u.Correu) -and $texto.StartsWith($u.Texto, [StringComparison]::Ordinal)) {
            $u.Texto = $texto; $u.Hora = (Get-Date).ToString('HH:mm:ss.fff'); return
        }
        if ($v.Count -ge 20) { $v.RemoveAt($v.Count - 1) }
        Add-Marca ('.ps1 changed: ' + $c + ' (version ' + ($v.Count + 1) + ')')
    }
    $v.Add([pscustomobject]@{ Texto = $texto; Hora = (Get-Date).ToString('HH:mm:ss.fff'); Correu = $false })
}

function Ps-Apagado([string]$c) {
    $e = $psMapa[$c]
    if ($e -and (-not $e.Apagado)) { $e.Apagado = $true; Add-Marca ('.ps1 deleted: ' + $c) }
}

# a .ps1 to read again whenever it changes
function Ps-Seguir([string]$c) {
    if ((Ps-Ignorar $c) -or $psSeguidos.ContainsKey($c) -or ($psSeguidos.Count -ge 200)) { return }
    $psSeguidos[$c] = [pscustomobject]@{ Path = $c; Marca = '' }
    if ($psCap) { try { [void]$psCap.Watch([IO.Path]::GetDirectoryName($c), $false) } catch { } }
}

function Ps-Correu([string]$c) {
    if (Ps-Ignorar $c) { return }
    Ps-Seguir $c
    $t = Ps-Ler $c
    if ($null -eq $t) {
        if (-not $psMapa[$c]) { Ps-Nota ('PowerShell was told to run "' + $c + '" but the file could not be read') }
    } else { Ps-Guardar $c $t 'run' }
    $e = $psMapa[$c]
    if ($e) {
        $e.Corridas++
        if ($e.Versoes.Count -gt 0) { $e.Versoes[$e.Versoes.Count - 1].Correu = $true }
    }
}

# code that PowerShell reads from a file and runs from memory (iex / Invoke-Expression): there is no .ps1 on
# disk, so the code is cut out of that file the same way PowerShell does it and logged like a .ps1 file
function Ps-Embutido($ex) {
    $tudo = $ex.Cmd + ' ' + $ex.Decod
    if ($tudo -notmatch '(?i)\b(?:invoke-expression|iex)\b') { return }
    if ($tudo -notmatch '(?i)ReadAllText|ReadAllLines|Get-Content|\bgc\b|\$\{[^}]+\}') { return }
    # where the code starts: .IndexOf('#'+'MARKER') in the command, otherwise the whole file
    $marca = $null
    $mi = [regex]::Match($tudo, '(?i)IndexOf\(\s*(?<m>(?:''[^'']*''|"[^"]*")(?:\s*\+\s*(?:''[^'']*''|"[^"]*"))*)\s*[,)]')
    if ($mi.Success) {
        $marca = ''
        foreach ($mp in [regex]::Matches($mi.Groups['m'].Value, '''([^'']*)''|"([^"]*)"')) { $marca += $mp.Groups[1].Value + $mp.Groups[2].Value }
        if ($marca.Length -eq 0) { $marca = $null }
    }
    # the file: ${C:\x.cmd}, a path written in the command, or (for $env:NAME) the script being debugged
    $cands = New-Object System.Collections.Generic.List[string]
    foreach ($mc in [regex]::Matches($tudo, '(?i)(?:\$\{|["''(\s])(?<p>[A-Za-z]:\\[^"''|<>*?{}]*?\.(?:cmd|bat|ps1|psm1|txt))')) {
        $cp = Ps-Resolver $mc.Groups['p'].Value $psEstado.Pasta
        if ($cp -and (-not $cands.Contains($cp))) { $cands.Add($cp) }
    }
    foreach ($cp in @($aExecutar, $Alvo)) { if ($cp -and (-not $cands.Contains($cp))) { $cands.Add($cp) } }
    foreach ($cp in $cands) {
        $tx = Ps-Ler $cp
        if (($null -eq $tx) -or $tx.StartsWith('[Debug-CMD] not logged')) { continue }
        $trecho = $tx
        if ($marca) {
            $ix = $tx.IndexOf($marca, [StringComparison]::Ordinal)
            if ($ix -lt 0) { continue }
            $trecho = $tx.Substring($ix)
        }
        $rot = '[in memory] ' + $(if ($marca) { 'from "' + $marca + '" to the end of ' } else { 'whole file ' }) + $cp
        if ($psMapa.ContainsKey($rot)) { return }
        $en = [pscustomobject]@{ Path = $rot; Origem = 'memory'; Versoes = (New-Object System.Collections.Generic.List[object]); Corridas = 1; Apagado = $false; Arquivo = $null }
        $en.Versoes.Add([pscustomobject]@{ Texto = $trecho; Hora = (Get-Date).ToString('HH:mm:ss.fff'); Correu = $true })
        $psMapa[$rot] = $en
        $psLista.Add($en)
        $psEmbLista.Add($en)
        $ex.Ps1.Add($rot)
        Add-Marca ('PowerShell code run from memory (no .ps1 on disk): ' + $rot + ' (' + (Ps-Linhas $trecho).Count + ' lines)')
        return
    }
    Ps-Nota 'PowerShell reads code from a file and runs it from memory, but the file could not be identified, so that code is not logged'
}

function Ps-NovaExec([string]$fonte, [string]$cmd, $procId) {
    $agora = Get-Date
    if ([string]::IsNullOrWhiteSpace($cmd)) { $cmd = '(command line not available)' }
    elseif ($fonte -eq 'process') {
        # already seen as an echoed command? then only add the PID to it
        $resto = Ps-Normalizar ($cmd -replace '^\s*("[^"]*"|\S+)', '')
        for ($i = $psExec.Count - 1; $i -ge [Math]::Max(0, $psExec.Count - 30); $i--) {
            $x = $psExec[$i]
            if (($x.Fonte -eq 'echo') -and ($null -eq $x.Pid) -and (($agora - $x.Quando).TotalSeconds -lt 60) -and (($resto.Length -eq 0) -or $x.Chave.Contains($resto))) {
                $x.Pid = $procId
                return
            }
        }
    }
    $ex = [pscustomobject]@{ Quando = $agora; Hora = $agora.ToString('HH:mm:ss.fff'); Fonte = $fonte; Cmd = $cmd; Pid = $procId
                             Chave = (Ps-Normalizar $cmd); Ps1 = (New-Object System.Collections.Generic.List[string]); Decod = $null }
    $psExec.Add($ex)
    if ($fonte -eq 'process') { Add-Marca ('PowerShell started (PID ' + $procId + '), not shown by echo: ' + (Ps-Curto $cmd 400)) }
    $ex.Decod = Ps-Decodificar $cmd
    if ($ex.Decod) { Add-Marca ('-EncodedCommand decoded: ' + (Ps-Curto $ex.Decod 400)) }
    $tudo = $cmd + ' ' + $ex.Decod
    foreach ($tk in (Ps-Ps1Corridos $tudo)) {
        $c = Ps-Resolver $tk $psEstado.Pasta
        if ($c -and (-not $ex.Ps1.Contains($c))) { $ex.Ps1.Add($c); Ps-Correu $c }
    }
    foreach ($tk in (Ps-Ps1Tokens $tudo)) {
        $c = Ps-Resolver $tk $psEstado.Pasta
        if ($c -and (-not $ex.Ps1.Contains($c))) { Ps-Seguir $c }
    }
    try { Ps-Embutido $ex } catch { Ps-Nota ('code run from memory: ' + $_.Exception.Message) }
    if ((-not $admin) -and (-not $psEstado.Elevou) -and ($tudo -match '(?i)-Verb\s+RunAs')) {
        $psEstado.Elevou = $true
        Ps-Nota 'The script restarted itself with administrator rights in a new window, which Debug-CMD cannot follow. Run Debug-CMD as administrator (ELEVATE=1) to capture it. The temporary copy was kept.'
    }
}

# looks at each log line: echoed commands that run PowerShell, and redirects that write a .ps1
function Ps-VerLinha([string]$texto) {
    $cmd = $null
    $m = [regex]::Match($texto, $rxPromptD)
    if ($m.Success) { $psEstado.Pasta = $m.Groups['d'].Value; $cmd = $m.Groups['c'].Value.Trim() }
    $alvo   = $(if ($null -ne $cmd) { $cmd } else { $texto })
    $temPs1 = ($alvo.IndexOf('.ps1', [StringComparison]::OrdinalIgnoreCase) -ge 0)
    $ehPs   = (($null -ne $cmd) -and ($cmd -match $rxPsExe) -and ($cmd -notmatch '(?i)^(echo([\s.:(]|$)|rem(\s|$)|::|set\s)') -and ($cmd -notmatch '(?i)^if\s+(not\s+)?exist\s+("[^"]*"|\S+)\s+set\s'))
    if ($temPs1) {
        # (parenthesized blocks show their redirect on the last line, so every line is checked)
        foreach ($mw in [regex]::Matches($alvo, '(?i)>\s*("[^"]+?\.ps1"|[^\s"<>|&()]+?\.ps1)(?![\w.])')) {
            $c = Ps-Resolver $mw.Groups[1].Value $psEstado.Pasta
            if ($c) { Ps-Seguir $c }
        }
    }
    if ($ehPs) { Ps-NovaExec 'echo' $cmd $null }
}

function Ps-VerSeguro([string]$texto) {
    if (-not $LogPs1) { return }
    try { Ps-VerLinha $texto } catch { Ps-Nota ('line check: ' + $_.Exception.Message) }
}

# collects what the watchers found and re-reads the known .ps1 files that changed
function Ps-Tick([bool]$forcar) {
    $agora = Get-Date
    if ((-not $forcar) -and (($agora - $psEstado.Tick).TotalMilliseconds -lt 200)) { return }
    $psEstado.Tick = $agora
    if ($psCap) {
        $s = $null
        while ($psCap.Files.TryDequeue([ref]$s)) {
            if ($s.Kind -eq 'gone') { Ps-Apagado $s.Path }
            elseif ($s.Kind -eq 'locked') { Ps-Seguir $s.Path }
            else { Ps-Guardar $s.Path $s.Content 'written'; Ps-Seguir $s.Path }
        }
        $pr = $null
        while ($psCap.Procs.TryDequeue([ref]$pr)) { $psPendProc.Add($pr) }
        $msg = $null
        while ($psCap.Problems.TryDequeue([ref]$msg)) { Ps-Nota $msg }
    }
    # PowerShell processes: wait a moment so their echoed line (if any) is read first
    $i = 0
    while ($i -lt $psPendProc.Count) {
        $pr = $psPendProc[$i]
        if ($forcar -or (($agora - $pr.Time).TotalMilliseconds -ge 500)) {
            $psPendProc.RemoveAt($i)
            Ps-NovaExec 'process' $pr.CommandLine $pr.Pid
        } else { $i++ }
    }
    foreach ($f in @($psSeguidos.Values)) {
        $fi = New-Object IO.FileInfo($f.Path)
        if ($fi.Exists) {
            $marca = '' + $fi.LastWriteTimeUtc.Ticks + ':' + $fi.Length
            if ($marca -ne $f.Marca) {
                $f.Marca = $marca
                $t = Ps-Ler $f.Path
                if ($null -ne $t) { Ps-Guardar $f.Path $t 'written' }
            }
        } elseif ($f.Marca -ne 'gone') {
            $f.Marca = 'gone'
            Ps-Apagado $f.Path
        }
    }
}

function Ps-TickSeguro {
    if (-not $LogPs1) { return }
    try { Ps-Tick $false } catch { Ps-Nota ('capture: ' + $_.Exception.Message) }
}

function Ps-Fim {
    if (-not $LogPs1) { return }
    try {
        if ($psCap) { Start-Sleep -Milliseconds 150 }   # let the last file events arrive
        Ps-Tick $true
    } catch { Ps-Nota ('final check: ' + $_.Exception.Message) }
    if ($psCap) {
        try { $psCap.Dispose() } catch { }
        try { Ps-Tick $true } catch { }
    }
}

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
try { $so = (Get-CimInstance Win32_OperatingSystem).Caption } catch { $so = [Environment]::OSVersion.VersionString }

# ---------- temporary copy with echo on (and pause skipped) ----------
$aExecutar = $Alvo
$copia     = $null
$ajustes   = New-Object System.Collections.Generic.List[string]
if ($EchoOn -or $IgnPause) {
    try {
        $enc  = [Text.Encoding]::GetEncoding(28591)   # Latin-1: keeps the script's bytes exactly as they are
        $txt  = [IO.File]::ReadAllText($Alvo, $enc)
        $novo = $txt
        if ($EchoOn) {
            $novo = [regex]::Replace($novo, '(?im)^([ \t]*)@?echo[ \t]+off\b', '${1}@echo on')
            if ($novo -ne $txt) { $ajustes.Add('echo off -> echo on') }
        }
        if ($IgnPause) {
            $antes = $novo
            $novo  = [regex]::Replace($novo, '(?im)^([ \t]*)@?pause\b[^\r\n]*(?=\r?$)', '${1}echo [DEBUG] pause skipped')
            if ($novo -ne $antes) { $ajustes.Add('pause -> skipped') }
        }
        if ($novo -ne $txt) {
            $copia = Join-Path $pasta ('__dbg_' + $nome + $ext)
            [IO.File]::WriteAllText($copia, $novo, $enc)
            $aExecutar = $copia
        }
    } catch {
        $ajustes.Add('could not create the copy, running the original: ' + $_.Exception.Message)
        $copia = $null
        $aExecutar = $Alvo
    }
}

# ---------- start the PowerShell capture ----------
if ($LogPs1) {
    $psEstado.Modo = 'limited'
    try {
        Add-Type -AssemblyName System.Management -ErrorAction Stop
        Add-Type -TypeDefinition $csCaptura -ReferencedAssemblies ([System.Management.ManagementObjectSearcher].Assembly.Location) -ErrorAction Stop
        $psCap = [DbgPsCapture]::new($PSCommandPath)
        foreach ($d in @($pasta, $env:TEMP)) { if ($d) { [void]$psCap.Watch($d, $true) } }
        $psEstado.Modo = 'live'
    } catch {
        $psCap = $null
        Ps-Nota ('live capture is not available (' + $_.Exception.Message + '); .ps1 files are only logged when an echoed command runs them')
    }
}
$psDescModo = $(if (-not $LogPs1) { 'not logged (LOG_PS1=0)' }
                elseif ($psCap) { '.ps1 files written in ' + (($psCap.Folders | ForEach-Object { '"' + $_ + '"' }) -join ', ') + ' (and subfolders) or run by the script, and every PowerShell it starts' }
                else { 'only .ps1 files run by echoed commands (live capture not available)' })

# ---------- log header ----------
$sep = '=' * 78
$sw.WriteLine($sep)
$sw.WriteLine(' RUN INFORMATION')
$sw.WriteLine($sep)
$sw.WriteLine("Script        : $Alvo")
$sw.WriteLine('Started       : ' + $inicio.ToString('yyyy-MM-dd HH:mm:ss'))
$sw.WriteLine("User          : $env:USERDOMAIN\$env:USERNAME")
$sw.WriteLine("Windows       : $so")
$sw.WriteLine('Administrator : ' + $(if ($admin) { 'Yes' } else { 'No' }))
$sw.WriteLine('Ran as        : ' + $(if ($copia) { "temporary copy ($aExecutar)" } else { 'original file' }))
if ($ajustes.Count -gt 0) { $sw.WriteLine('Adjustments   : ' + ($ajustes -join '; ')) }
$sw.WriteLine('PowerShell    : ' + $psDescModo)
$sw.WriteLine($sep)
$sw.WriteLine(' DETAILED LOG   [time] script output (commands appear as C:\folder>command)')
$sw.WriteLine($sep)

Write-Host ''
Write-Host "Running   : $Alvo" -ForegroundColor Cyan
Write-Host "Log       : $logPath" -ForegroundColor DarkGray
Write-Host ('-' * 70) -ForegroundColor DarkGray

# files the script created or changed while it ran (its own logs, reports, settings)
function Coletar-Arquivos([string]$rxErroArq) {
    $res2 = [pscustomobject]@{ Lista = (New-Object System.Collections.Generic.List[object]); Dirs = (New-Object System.Collections.Generic.List[string]); Nota = $null }
    if ($env:COLLECT_FILES -eq '0') { return $res2 }
    try {
        $exts = @('.log', '.txt', '.json', '.csv', '.xml', '.ini')
        $ignorar = @('windows', 'program files', 'program files (x86)', 'users', 'temp', 'tmp', 'system volume information', '$recycle.bin', 'programdata', 'documents and settings')
        $dirs = $res2.Dirs
        $addDir = {
            param([string]$d)
            try {
                if ([string]::IsNullOrWhiteSpace($d)) { return }
                $d = $d.Trim().Trim('"').TrimEnd('\')
                if ($d.Length -lt 3) { return }
                if ((Test-Path -LiteralPath $d -PathType Container) -and (-not ($dirs -contains $d)) -and ($dirs.Count -lt 15)) { $dirs.Add($d) }
            } catch { }
        }
        & $addDir $pasta
        if ($env:COLLECT_DIRS) { foreach ($x in ($env:COLLECT_DIRS -split ';')) { & $addDir $x } }

        # folders the script mentions: %SystemDrive%\Name, $env:ProgramData 'Name', C:\Name ...
        $textos = New-Object System.Collections.Generic.List[string]
        try { $textos.Add([IO.File]::ReadAllText($Alvo)) } catch { }
        foreach ($pe in $psLista) { foreach ($v in $pe.Versoes) { $textos.Add([string]$v.Texto) } }
        $envs = 'SystemDrive|ProgramData|LOCALAPPDATA|APPDATA|USERPROFILE|PUBLIC'
        foreach ($tx in $textos) {
            if ($tx.Length -gt 3000000) { $tx = $tx.Substring(0, 3000000) }
            foreach ($rxp in @(('(?i)%(' + $envs + ')%\\([\w.\- ]+)'), ('(?i)\$env:(' + $envs + ')\b[^\r\n''"]{0,30}[''"]\\?([\w.\- ]+)[''"]'), ('(?i)\$env:(' + $envs + ')\\([\w.\-]+)'))) {
                foreach ($m in [regex]::Matches($tx, $rxp)) {
                    $base = [Environment]::GetEnvironmentVariable($m.Groups[1].Value)
                    $nm = $m.Groups[2].Value.Trim()
                    if ($base -and $nm -and ($ignorar -notcontains $nm.ToLower())) { & $addDir ($base.TrimEnd('\') + '\' + $nm) }
                }
            }
            foreach ($m in [regex]::Matches($tx, '(?i)\b([A-Za-z]):\\([\w.\-]+)')) {
                $nm = $m.Groups[2].Value
                if ($ignorar -notcontains $nm.ToLower()) { & $addDir ($m.Groups[1].Value + ':\' + $nm) }
            }
        }

        # files written since the run started (2 s of tolerance)
        $desde = $inicio.AddSeconds(-2)
        $ev = @($logPath, [IO.Path]::ChangeExtension($logPath, '.html'), $Alvo)
        $achados = New-Object System.Collections.Generic.List[object]
        $visitados = 0
        $vistos = @{}
        $varre = $null
        $varre = {
            param([string]$dir, [int]$prof)
            if ($script:colVisitados -gt 20000) { return }
            try {
                foreach ($f in [IO.Directory]::EnumerateFiles($dir)) {
                    $script:colVisitados++
                    $ext = [IO.Path]::GetExtension($f).ToLower()
                    if ($exts -notcontains $ext) { continue }
                    $bn = [IO.Path]::GetFileName($f)
                    if ($bn.StartsWith($nome + '_debug_', [StringComparison]::OrdinalIgnoreCase) -or $bn.StartsWith($nome + '_test_', [StringComparison]::OrdinalIgnoreCase) -or $bn.StartsWith('__dbg_', [StringComparison]::OrdinalIgnoreCase) -or $bn.StartsWith('Debug-CMD', [StringComparison]::OrdinalIgnoreCase)) { continue }
                    if ($ev -contains $f) { continue }
                    $fi = New-Object System.IO.FileInfo($f)
                    if ($fi.LastWriteTime -lt $desde) { continue }
                    if ($script:colVistos.ContainsKey($f.ToLower())) { continue }
                    $script:colVistos[$f.ToLower()] = $true
                    $script:colAchados.Add($fi)
                }
                if ($prof -lt 4) { foreach ($sd in [IO.Directory]::EnumerateDirectories($dir)) { & $script:colVarre $sd ($prof + 1) } }
            } catch { }
        }
        $script:colVisitados = 0; $script:colVistos = $vistos; $script:colAchados = $achados; $script:colVarre = $varre
        foreach ($d in @($dirs)) { & $varre $d 0 }

        $ordem = @($achados | Sort-Object LastWriteTime -Descending | Select-Object -First 40)
        $orcamento = 8388608
        foreach ($fi in $ordem) {
            $o = [pscustomobject]@{ Path = $fi.FullName; Tam = $fi.Length; Mod = $fi.LastWriteTime; Novo = ($fi.CreationTime -ge $desde); Texto = $null; Omitido = 0; Erros = @{}; NErros = 0; Falha = $null }
            try {
                $fs = [IO.File]::Open($fi.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
                try {
                    $max = 1048576
                    if ($fs.Length -gt $max) { $o.Omitido = $fs.Length - 204800; $fs.Seek($o.Omitido, [IO.SeekOrigin]::Begin) | Out-Null }
                    if ($orcamento -le 0) { $o.Falha = 'content omitted (size limit of the report reached)' }
                    else {
                        $sr = New-Object System.IO.StreamReader($fs, [Text.Encoding]::UTF8, $true)
                        $o.Texto = $sr.ReadToEnd()
                        $orcamento -= $o.Texto.Length
                        if ($o.Omitido -gt 0) { $i1 = $o.Texto.IndexOf("`n"); if ($i1 -ge 0) { $o.Texto = $o.Texto.Substring($i1 + 1) } }
                    }
                } finally { $fs.Dispose() }
            } catch { $o.Falha = 'could not be read: ' + $_.Exception.Message }
            if ($null -ne $o.Texto) {
                $nl = 0
                foreach ($tl in (Ps-Linhas $o.Texto)) { $nl++; if ($tl -match $rxErroArq) { $o.Erros[$nl] = $true } }
                $o.NErros = $o.Erros.Count
            }
            $res2.Lista.Add($o)
        }
        if ($achados.Count -gt $ordem.Count) { $res2.Nota = ('Only the 40 most recent of ' + $achados.Count + ' files are shown.') }
    } catch { $res2.Nota = 'Could not collect files: ' + $_.Exception.Message }
    return $res2
}

function Concluir {
$fim = Get-Date
$dur = $cronometro.Elapsed.ToString('hh\:mm\:ss\.fff')
$sw.WriteLine($sep)
$sw.WriteLine('Finished      : ' + $fim.ToString('yyyy-MM-dd HH:mm:ss') + "   (duration $dur)")
$sw.WriteLine("Exit code: $codigo")
if ($interrompido) { $sw.WriteLine('*** RUN INTERRUPTED (Ctrl+C): the script did not finish ***') }

# PowerShell: lines where it reported an error ("At C:\x.ps1:12 char:5"), then every .ps1 in full
$psErr = @{}
foreach ($l in $linhas) {
    if ($l.IndexOf('.ps1:', [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
    foreach ($mm in [regex]::Matches($l, '(?<p>(?:[A-Za-z]:\\|\\\\)[^:*?"<>|]*?\.ps1):(?<n>\d+)\s+\S+:\d+')) {
        $kp = $mm.Groups['p'].Value
        if (-not $psErr.ContainsKey($kp)) { $psErr[$kp] = @{} }
        $psErr[$kp][[int]$mm.Groups['n'].Value] = $true
    }
}
# code run from memory: "At line:N char:M" counts from the start of that code
if ($psEmbLista.Count -eq 1) {
    $kp = $psEmbLista[0].Path
    foreach ($l in $linhas) {
        foreach ($mm in [regex]::Matches($l, '(?i)\bAt line:(?<n>\d+) char:\d+')) {
            if (-not $psErr.ContainsKey($kp)) { $psErr[$kp] = @{} }
            $psErr[$kp][[int]$mm.Groups['n'].Value] = $true
        }
    }
}
function Ps-Descricao($pe) {
    $d = New-Object System.Collections.Generic.List[string]
    $d.Add($(if ($pe.Origem -eq 'written') { 'written during the run' } elseif ($pe.Origem -eq 'memory') { 'no file on disk: the script runs this code from memory' } else { 'captured when it ran' }))
    if (($pe.Origem -eq 'memory') -and $pe.Arquivo) { $d.Add('saved as ' + $pe.Arquivo) }
    $d.Add($(if ($pe.Corridas -gt 0) { 'ran ' + $pe.Corridas + 'x' } else { 'not seen running' }))
    if ($pe.Apagado) { $d.Add('deleted before the end') }
    $nlin = (Ps-Linhas $pe.Versoes[$pe.Versoes.Count - 1].Texto).Count
    $d.Add([string]$nlin + $(if ($nlin -eq 1) { ' line' } else { ' lines' }))
    if ($pe.Versoes.Count -gt 1) { $d.Add([string]$pe.Versoes.Count + ' versions') }
    $er = $psErr[$pe.Path]
    if ($er -and ($er.Count -gt 0)) { $d.Add('PowerShell error at line ' + ((@($er.Keys) | Sort-Object) -join ', ')) }
    return ($d -join ' | ')
}
# code run from memory is also saved as a real .ps1 next to the log (line numbers match PowerShell's "At line:N")
$ne = 0
foreach ($pe in $psEmbLista) {
    $ne++
    try {
        $pf = [IO.Path]::ChangeExtension($logPath, ('embedded' + $ne + '.ps1'))
        [IO.File]::WriteAllText($pf, $pe.Versoes[$pe.Versoes.Count - 1].Texto, $utf8bom)
        $pe.Arquivo = $pf
    } catch { }
}
if ($psLista.Count -gt 0) {
    $sw.WriteLine('')
    $sw.WriteLine($sep)
    $sw.WriteLine(' POWERSHELL SCRIPTS - FULL CONTENTS (.ps1 files and code run from memory)   (">>" = PowerShell reported an error at that line)')
    $sw.WriteLine($sep)
    $np = 0
    foreach ($pe in $psLista) {
        $np++
        $sw.WriteLine('')
        $sw.WriteLine(('---- [{0}] {1}' -f $np, $pe.Path))
        $sw.WriteLine('     ' + (Ps-Descricao $pe))
        $nv = 0
        foreach ($pv in $pe.Versoes) {
            $nv++
            if ($pe.Versoes.Count -gt 1) { $sw.WriteLine(('     -- version {0} of {1}, last change {2}{3}' -f $nv, $pe.Versoes.Count, $pv.Hora, $(if ($pv.Correu) { ', ran' } else { '' }))) }
            foreach ($x in (Texto-Fonte $pv.Texto $psErr[$pe.Path])) { $sw.WriteLine($x) }
        }
    }
}
$largos = @($psExec | Where-Object { $_.Cmd.Length -gt 220 })
if ($largos.Count -gt 0) {
    $sw.WriteLine('')
    $sw.WriteLine($sep)
    $sw.WriteLine(' POWERSHELL COMMAND LINES - FULL   (code passed on the command line is part of it)')
    $sw.WriteLine($sep)
    $np = 0
    foreach ($px in $largos) {
        $np++
        $sw.WriteLine('')
        $sw.WriteLine(('---- [{0}] {1}{2}' -f $np, $px.Hora, $(if ($px.Pid) { ' (PID ' + $px.Pid + ')' } else { '' })))
        $cl = $px.Cmd
        if ($cl.Length -gt 20000) { $cl = $cl.Substring(0, 20000) + ' [... cut at 20000 characters]' }
        $sw.WriteLine($cl)
    }
}
$sw.Close()

# ---------- analysis ----------
$rxPrompt = '^(?:[A-Za-z]:\\|\\\\)[^>]*>(?<c>.*)$'
$rxErro   = '\b(erro|erros|error|errors)\b|\bfalh|\bfail|\bfatal\b|exce[pç]|n[aã]o [eé] reconhecido|not recognized|n[aã]o foi poss[ií]vel|n[aã]o consegu|n[aã]o foi encontrad|n[aã]o existe|o sistema n[aã]o|cannot find|could not find|does not exist|access is denied|acesso negado|permission denied|negad[oa]\b|denied|invalid|inv[aá]lid|sintaxe|syntax|unable to|utilizado por outro processo|used by another process|timed out|esgotad|FullyQualifiedErrorId'
$triv     = '^(rem(\s|$)|::|:[^\s:]|@?echo\s+(on|off)\b)'

$entradas = New-Object System.Collections.Generic.List[object]
$atual = [pscustomobject]@{
    Cmd = '(output with no associated command)'; Hora = ''; Pseudo = $true
    Saida = (New-Object System.Collections.Generic.List[string])
    Problemas = (New-Object System.Collections.Generic.List[string])
}
$entradas.Add($atual)
for ($k = 0; $k -lt $linhas.Count; $k++) {
    $l = $linhas[$k]
    $m = [regex]::Match($l, $rxPrompt)
    if ($m.Success -and $m.Groups['c'].Value.Trim().Length -gt 0) {
        $ct = $m.Groups['c'].Value.Trim()
        if ($ct.Length -gt 220) { $ct = $ct.Substring(0, 220) + ' [...]' }
        $atual = [pscustomobject]@{
            Cmd = $ct; Hora = $horas[$k]; Pseudo = $false
            Saida = (New-Object System.Collections.Generic.List[string])
            Problemas = (New-Object System.Collections.Generic.List[string])
        }
        $entradas.Add($atual)
    } else {
        $atual.Saida.Add($l)
        if ((-not $l.StartsWith('[Debug-CMD] ')) -and ($l -match $rxErro)) { $atual.Problemas.Add($l) }
    }
}

$cmds     = @($entradas | Where-Object { (-not $_.Pseudo) -and ($_.Cmd -notmatch $triv) })
$comProb  = @($entradas | Where-Object { $_.Problemas.Count -gt 0 })
$bem      = @($cmds | Where-Object { $_.Problemas.Count -eq 0 })
$totalErr = 0
foreach ($e in $entradas) { $totalErr += $e.Problemas.Count }
$colh = Coletar-Arquivos $rxErro
$arqs = $colh.Lista
$arqsComErro = @($arqs | Where-Object { $_.NErros -gt 0 }).Count

$estado = $(if ($interrompido) { 'INTERRUPTED' } elseif (($codigo -ne 0) -or ($comProb.Count -gt 0)) { 'WITH PROBLEMS' } elseif ($psEstado.Elevou) { 'INCOMPLETE - RESTARTED AS ADMIN' } else { 'OK' })
$nota   = $(if ($interrompido) { '   (interrupted: the script did not finish)' } elseif ($codigo -ne 0) { '   (non-zero: the last command ended with an error)' } else { '' })

$res = New-Object System.Collections.Generic.List[string]
$res.Add($sep); $res.Add(' SUMMARY'); $res.Add($sep)
$res.Add("Script           : $Alvo")
$res.Add("Status           : $estado")
if ($interrompido) { $res.Add('Warning          : the run was interrupted before the script finished; the results below are partial.') }
$res.Add("Exit code        : $codigo$nota")
$res.Add("Duration         : $dur")
$res.Add("Commands         : $($cmds.Count) run | $($bem.Count) with no detected errors | $($comProb.Count) with problems")
$res.Add("Error lines      : $totalErr")
if ($LogPs1) { $res.Add(('PowerShell       : {0} run(s) | {1} .ps1 file(s) logged | {2} script(s) run from memory' -f $psExec.Count, ($psLista.Count - $psEmbLista.Count), $psEmbLista.Count)) }
if ($env:COLLECT_FILES -ne '0') { $res.Add(('Files collected  : {0} file(s) created or changed by the script | {1} with lines that look like errors' -f $arqs.Count, $arqsComErro)) }
if ((-not $admin) -and (@($comProb | ForEach-Object { $_.Problemas }) -match 'acesso negado|access is denied')) {
    $res.Add('Suggestion       : "access denied" occurred and the script ran WITHOUT administrator rights (see the ELEVATE option at the top of Debug-CMD.cmd).')
}

$res.Add('')
$res.Add($sep); $res.Add(' WHAT FAILED'); $res.Add($sep)
if ($comProb.Count -eq 0) {
    $res.Add('No errors detected.')
} else {
    $n = 0
    foreach ($e in $comProb) {
        $n++
        if ($n -gt 60) { $res.Add("... (+$($comProb.Count - 60) more commands with problems; see the detailed log)"); break }
        $res.Add(('[FAILED] [{0}] {1}' -f $e.Hora, $e.Cmd))
        foreach ($pl in ($e.Problemas | Select-Object -First 4)) { $res.Add("           > $pl") }
    }
}

if ($LogPs1 -and ($psExec.Count -gt 0) -and ($psLista.Count -eq 0)) { Ps-Nota 'No .ps1 file was written or run and no code read from a file was recognized: the PowerShell code was passed on the command line (see the full command lines at the end of the log) or is built at run time' }
$temPs = ($LogPs1 -and (($psExec.Count + $psLista.Count + $psNotas.Count) -gt 0))
if ($temPs) {
    $res.Add('')
    $res.Add($sep); $res.Add(' POWERSHELL' + $(if ($psLista.Count -gt 0) { '   (the full .ps1 contents are at the end of this log)' } else { '' })); $res.Add($sep)
    if ($psExec.Count -eq 0) { $res.Add('No PowerShell runs detected.') }
    $np = 0
    foreach ($px in $psExec) {
        $np++
        if ($np -gt 100) { $res.Add("... (+$($psExec.Count - 100) more runs; see the detailed log)"); break }
        $res.Add(('[RUN]    [{0}] {1}' -f $px.Hora, (Ps-Curto $px.Cmd 220)))
        if ($px.Fonte -eq 'process') { $res.Add('           > PID ' + $px.Pid + ', not shown by echo (found by watching processes)') }
        foreach ($f1 in $px.Ps1) { $res.Add('           > runs ' + $f1) }
        if ($px.Decod) { $res.Add('           > decoded -EncodedCommand: ' + (Ps-Curto $px.Decod 300)) }
    }
    $np = 0
    foreach ($pe in $psLista) {
        $np++
        $res.Add(('[PS1 {0}]  {1}' -f $np, $pe.Path))
        $res.Add('           > ' + (Ps-Descricao $pe))
    }
    foreach ($nt in $psNotas) { $res.Add('Note: ' + $nt) }
}

$res.Add('')
if ($arqs.Count -gt 0) {
    $res.Add($sep); $res.Add(' FILES CREATED OR CHANGED BY THE SCRIPT   (contents at the end of this log)'); $res.Add($sep)
    foreach ($a in $arqs) {
        $res.Add(('[{0}] {1}   ({2} KB, {3}{4})' -f $(if ($a.Novo) { 'NEW ' } else { 'EDIT' }), $a.Path, [Math]::Round($a.Tam / 1024, 1), $a.Mod.ToString('HH:mm:ss'), $(if ($a.NErros -gt 0) { ', ' + $a.NErros + ' line(s) that look like errors' } else { '' })))
    }
    if ($colh.Nota) { $res.Add('Note: ' + $colh.Nota) }
    $res.Add('Searched in: ' + ($colh.Dirs -join '; '))
    $res.Add('')
}
$res.Add($sep); $res.Add(' WHAT WORKED  (commands with no detected errors)'); $res.Add($sep)
if ($bem.Count -eq 0) {
    $res.Add('(no commands identified)')
} else {
    $n = 0
    foreach ($e in $bem) {
        $n++
        if ($n -gt 300) { $res.Add("... (+$($bem.Count - 300) omitted; see the detailed log)"); break }
        $res.Add(('[ OK ]   [{0}] {1}' -f $e.Hora, $e.Cmd))
    }
}
$res.Add('')
$res.Add('Note: "no detected errors" = no known error line in the command output. Commands using >nul 2>&1 hide their own errors.')
$res.Add('')

# summary at the top of the .log
$corpo = [IO.File]::ReadAllLines($logPath, $utf8bom)
$extra = New-Object System.Collections.Generic.List[string]
if ($arqs.Count -gt 0) {
    $extra.Add($sep); $extra.Add(' FILES CREATED OR CHANGED BY THE SCRIPT - CONTENTS   (>> marks lines that look like errors)'); $extra.Add($sep)
    $na = 0
    foreach ($a in $arqs) {
        $na++
        $extra.Add(''); $extra.Add(('---- [{0}] {1}' -f $na, $a.Path))
        if ($a.Falha) { $extra.Add('     (' + $a.Falha + ')') }
        if ($a.Omitido -gt 0) { $extra.Add('     (large file: the first ' + [Math]::Round($a.Omitido / 1024) + ' KB are omitted, only the end is shown; line numbers count from the shown part)') }
        if ($null -ne $a.Texto) { foreach ($x in (Texto-Fonte $a.Texto $a.Erros)) { $extra.Add($x) } }
    }
}
$final = [string[]](@($res.ToArray()) + @($corpo) + @($extra.ToArray()))
[IO.File]::WriteAllLines($logPath, $final, $utf8bom)

# ---------- HTML report ----------
$htmlPath = $null
if ($env:GENERATE_HTML -ne '0') {
    try {
        $clsEstado = 'ok'
        $txtEstado = 'OK'
        if ($estado -eq 'WITH PROBLEMS') { $clsEstado = 'bad'; $txtEstado = 'WITH PROBLEMS' } elseif ($estado -eq 'INTERRUPTED') { $clsEstado = 'warn'; $txtEstado = 'INTERRUPTED' } elseif ($estado -like 'INCOMPLETE*') { $clsEstado = 'warn'; $txtEstado = $estado }

        $cart = New-Object System.Collections.Generic.List[object]
        $cart.Add(@('Commands', $cmds.Count, ''))
        $cart.Add(@('Worked', $bem.Count, 'ok'))
        $cart.Add(@('With problems', $comProb.Count, $(if ($comProb.Count -gt 0) { 'bad' } else { 'ok' })))
        $cart.Add(@('Exit code', $codigo, $(if ($codigo -ne 0) { 'bad' } else { 'ok' })))
        $cart.Add(@('Duration', $dur, ''))
        if ($LogPs1 -and (($psExec.Count + $psLista.Count) -gt 0)) {
            $cart.Add(@('PowerShell runs', $psExec.Count, ''))
            $cart.Add(@('.ps1 files logged', ($psLista.Count - $psEmbLista.Count), ''))
            if ($psEmbLista.Count -gt 0) { $cart.Add(@('Run from memory', $psEmbLista.Count, '')) }
        }
        if ($env:COLLECT_FILES -ne '0') { $cart.Add(@('Files collected', $arqs.Count, $(if ($arqsComErro -gt 0) { 'warn' } else { '' }))) }

        $inf = New-Object System.Collections.Generic.List[object]
        $inf.Add(@('Script', $Alvo))
        $inf.Add(@('Started', $inicio.ToString('yyyy-MM-dd HH:mm:ss')))
        $inf.Add(@('User', "$env:USERDOMAIN\$env:USERNAME"))
        $inf.Add(@('Windows', "$so"))
        $inf.Add(@('Administrator', $(if ($admin) { 'Yes' } else { 'No' })))
        $inf.Add(@('Ran as', $(if ($copia) { 'temporary copy with echo on' } else { 'original file' })))
        if ($ajustes.Count -gt 0) { $inf.Add(@('Adjustments', ($ajustes -join '; '))) }
        if ($interrompido) { $inf.Add(@('Warning', 'The run was interrupted before the script finished; results are partial.')) }
        $inf.Add(@('PowerShell', $psDescModo))
        $inf.Add(@('Text log', $logPath))

        $b = New-Object System.Text.StringBuilder
        [void]$b.AppendLine('<h2>What failed</h2>')
        if ($comProb.Count -eq 0) {
            [void]$b.AppendLine('<p class="none">No errors detected.</p>')
        } else {
            foreach ($e in $comProb) {
                [void]$b.AppendLine('<details open class="fail"><summary><span class="t">' + (EscHtml $e.Hora) + '</span><code>' + (EscHtml $e.Cmd) + '</code></summary><pre>')
                $q = 0
                foreach ($sl in $e.Saida) {
                    $q++
                    if ($q -gt 200) { [void]$b.AppendLine('... (more lines in the full log)'); break }
                    if ((-not $sl.StartsWith('[Debug-CMD] ')) -and ($sl -match $rxErro)) { [void]$b.AppendLine('<span class="err">' + (EscHtml $sl) + '</span>') } else { [void]$b.AppendLine((EscHtml $sl)) }
                }
                [void]$b.AppendLine('</pre></details>')
            }
        }

        if ($temPs) {
            [void]$b.AppendLine('<h2>PowerShell</h2>')
            if ($psExec.Count -eq 0) { [void]$b.AppendLine('<p>No PowerShell runs detected.</p>') } else {
                [void]$b.AppendLine('<table class="list">')
                $q = 0
                foreach ($px in $psExec) {
                    $q++
                    if ($q -gt 300) { [void]$b.AppendLine('<tr><td></td><td>... (more in the full log)</td></tr>'); break }
                    $det = ''
                    if ($px.Fonte -eq 'process') { $det += '<div class="sub">PID ' + $px.Pid + ', not shown by echo (found by watching processes)</div>' }
                    foreach ($f1 in $px.Ps1) { $det += '<div class="sub">runs ' + (EscHtml $f1) + '</div>' }
                    if ($px.Decod) { $det += '<div class="sub">decoded -EncodedCommand:</div><pre>' + (EscHtml $px.Decod) + '</pre>' }
                    if ($px.Cmd.Length -gt 1000) { $det += '<div class="sub">full command line:</div><pre>' + (EscHtml $px.Cmd.Substring(0, [Math]::Min($px.Cmd.Length, 20000))) + '</pre>' }
                    [void]$b.AppendLine('<tr><td class="t">' + (EscHtml $px.Hora) + '</td><td><code>' + (EscHtml (Ps-Curto $px.Cmd 1000)) + '</code>' + $det + '</td></tr>')
                }
                [void]$b.AppendLine('</table>')
            }
            foreach ($pe in $psLista) {
                $er = $psErr[$pe.Path]
                $comErro = ($er -and ($er.Count -gt 0))
                [void]$b.AppendLine('<details' + $(if ($comErro) { ' open class="fail"' } else { '' }) + '><summary><code>' + (EscHtml $pe.Path) + '</code><span class="meta">' + (EscHtml (Ps-Descricao $pe)) + '</span></summary>')
                $nv = 0
                foreach ($pv in $pe.Versoes) {
                    $nv++
                    if ($pe.Versoes.Count -gt 1) { [void]$b.AppendLine('<div class="ver">version ' + $nv + ' of ' + $pe.Versoes.Count + ', last change ' + (EscHtml $pv.Hora) + $(if ($pv.Correu) { ', ran' } else { '' }) + '</div>') }
                    [void]$b.AppendLine((Html-Fonte $pv.Texto $er))
                }
                [void]$b.AppendLine('</details>')
            }
            foreach ($nt in $psNotas) { [void]$b.AppendLine('<p class="sub">Note: ' + (EscHtml $nt) + '</p>') }
        }

        if ($arqs.Count -gt 0) {
            [void]$b.AppendLine('<h2>Files created or changed by the script</h2>')
            [void]$b.AppendLine('<p class="sub">Searched in: ' + (EscHtml ($colh.Dirs -join '; ')) + '</p>')
            foreach ($a in $arqs) {
                $meta = $(if ($a.Novo) { 'new' } else { 'changed' }) + ', ' + [Math]::Round($a.Tam / 1024, 1) + ' KB, ' + $a.Mod.ToString('HH:mm:ss') + $(if ($a.NErros -gt 0) { ', ' + $a.NErros + ' line(s) that look like errors' } else { '' })
                [void]$b.AppendLine('<details' + $(if ($a.NErros -gt 0) { ' open class="fail"' } else { '' }) + '><summary><code>' + (EscHtml $a.Path) + '</code><span class="meta">' + (EscHtml $meta) + '</span></summary>')
                if ($a.Falha) { [void]$b.AppendLine('<div class="ver">' + (EscHtml $a.Falha) + '</div>') }
                if ($a.Omitido -gt 0) { [void]$b.AppendLine('<div class="ver">Large file: only the end is shown (the first ' + [Math]::Round($a.Omitido / 1024) + ' KB are omitted).</div>') }
                if ($null -ne $a.Texto) { [void]$b.AppendLine((Html-Fonte $a.Texto $a.Erros)) }
                [void]$b.AppendLine('</details>')
            }
            if ($colh.Nota) { [void]$b.AppendLine('<p class="sub">Note: ' + (EscHtml $colh.Nota) + '</p>') }
        }

        [void]$b.AppendLine('<h2>What worked</h2>')
        if ($bem.Count -eq 0) {
            [void]$b.AppendLine('<p>No commands identified.</p>')
        } else {
            [void]$b.AppendLine('<details><summary>' + $bem.Count + ' commands with no detected errors</summary><table class="list">')
            $q = 0
            foreach ($e in $bem) {
                $q++
                if ($q -gt 500) { [void]$b.AppendLine('<tr><td></td><td>... (more in the full log)</td></tr>'); break }
                [void]$b.AppendLine('<tr><td class="t">' + (EscHtml $e.Hora) + '</td><td><code>' + (EscHtml $e.Cmd) + '</code></td></tr>')
            }
            [void]$b.AppendLine('</table></details>')
        }

        [void]$b.AppendLine('<h2>Full log</h2>')
        [void]$b.AppendLine('<div class="tools"><button data-f="all" class="on">All</button><button data-f="cmd">Commands only</button><button data-f="err">Errors only</button></div>')
        [void]$b.AppendLine('<table id="log">')
        $limite = [Math]::Min($linhas.Count, 20000)
        for ($k = 0; $k -lt $limite; $k++) {
            $tx = $linhas[$k]
            $rc = ''
            if ([regex]::IsMatch($tx, $rxPrompt)) { $rc = 'cmd' } elseif ($tx.StartsWith('[Debug-CMD] ')) { $rc = 'ps' } elseif ($tx -match $rxErro) { $rc = 'err' }
            [void]$b.AppendLine('<tr class="' + $rc + '"><td class="t">' + (EscHtml $horas[$k]) + '</td><td>' + (EscHtml $tx) + '</td></tr>')
        }
        if ($linhas.Count -gt $limite) { [void]$b.AppendLine('<tr><td></td><td>... (' + ($linhas.Count - $limite) + ' more lines in the .log file)</td></tr>') }
        [void]$b.AppendLine('</table>')

        $htmlPath = [IO.Path]::ChangeExtension($logPath, '.html')
        Gravar-Html $htmlPath ('Debug report: ' + [IO.Path]::GetFileName($Alvo)) $txtEstado $clsEstado $cart $inf $b.ToString()
    } catch {
        $htmlPath = $null
        Write-Host ('Could not create the HTML report: ' + $_.Exception.Message) -ForegroundColor Yellow
    }
}

# summary on screen
$cor = $(if ($estado -eq 'OK') { 'Green' } else { 'Red' })
Write-Host ''
Write-Host $sep -ForegroundColor DarkGray
Write-Host " Status: $estado   |   Exit code: $codigo   |   Duration: $dur" -ForegroundColor $cor
Write-Host " Commands: $($cmds.Count) run, $($bem.Count) without errors, $($comProb.Count) with problems"
foreach ($e in ($comProb | Select-Object -First 10)) {
    Write-Host ('  [FAILED] ' + $e.Cmd) -ForegroundColor Yellow
    foreach ($pl in ($e.Problemas | Select-Object -First 2)) { Write-Host ('           > ' + $pl) -ForegroundColor DarkYellow }
}
if ($comProb.Count -gt 10) { Write-Host "  ... (+$($comProb.Count - 10) more in the log)" }
if ($temPs) {
    Write-Host (" PowerShell: $($psExec.Count) run(s), $($psLista.Count - $psEmbLista.Count) .ps1 file(s) logged, $($psEmbLista.Count) script(s) run from memory" + $(if ($psLista.Count -gt 0) { ' (full contents in the log)' } else { '' })) -ForegroundColor Cyan
}
foreach ($pe in $psEmbLista) { if ($pe.Arquivo) { Write-Host (' Code run from memory saved as: ' + $pe.Arquivo) -ForegroundColor Cyan } }
if ($psEstado.Elevou) {
    Write-Host ' WARNING: the script restarted itself with administrator rights in another window, which Debug-CMD cannot follow.' -ForegroundColor Yellow
    Write-Host ('          Run Debug-CMD as administrator (ELEVATE=1) to capture it. The temporary copy was kept: ' + $copia) -ForegroundColor Yellow
}
if ($arqs.Count -gt 0) { Write-Host (" Files created or changed by the script: $($arqs.Count)" + $(if ($arqsComErro -gt 0) { " ($arqsComErro with lines that look like errors)" } else { '' }) + ' (contents in the log)') -ForegroundColor Cyan }
Write-Host " Log: $logPath"
if ($htmlPath) { Write-Host " HTML: $htmlPath" }
Write-Host $sep -ForegroundColor DarkGray

if ($AbrirLog) {
    if ($htmlPath) { Start-Process -FilePath $htmlPath } else { Start-Process notepad.exe -ArgumentList ('"' + $logPath + '"') }
}
}

# ---------- execution ----------
$cronometro   = [Diagnostics.Stopwatch]::StartNew()
$codigo       = -1
$interrompido = $true      # becomes $false when the run ends without being interrupted
$p            = $null
try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $env:ComSpec
    $psi.Arguments              = '/d /c ""' + $aExecutar + '" 2>&1"'
    $psi.WorkingDirectory       = $pasta
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.StandardOutputEncoding = [Console]::OutputEncoding
    $psi.EnvironmentVariables['PROMPT'] = '$P$G'
    $p = [Diagnostics.Process]::Start($psi)
    if ($psCap) { try { $psCap.StartProcessWatch($p.Id, 500) } catch { Ps-Nota ('process watcher: ' + $_.Exception.Message) } }

    $reader      = $p.StandardOutput
    $buf         = New-Object 'char[]' 4096
    $pend        = ''
    $ociosos     = 0
    $ultimoAviso = [TimeSpan]::Zero
    $tarefa      = $reader.ReadAsync($buf, 0, $buf.Length)
    while ($true) {
        if ($tarefa.Wait(250)) {
            $n = $tarefa.Result
            if ($n -le 0) { break }
            $pedaco      = [string]::new($buf, 0, $n)
            $ociosos     = 0
            $ultimoAviso = $cronometro.Elapsed
            [Console]::Write($pedaco)      # the screen shows everything in real time, without waiting for end of line
            $pend += $pedaco
            while (($i = $pend.IndexOf("`n")) -ge 0) {
                Add-Linha ($pend.Substring(0, $i))
                $pend = $pend.Substring($i + 1)
            }
            $tarefa = $reader.ReadAsync($buf, 0, $buf.Length)
        } elseif ($p.HasExited) {
            # the script finished but left a background process holding the pipe open: don't wait for it
            $ociosos++
            if ($ociosos -ge 8) { break }
        } elseif (($cronometro.Elapsed - $ultimoAviso).TotalSeconds -ge 10) {
            # long, silent command: show that it is still alive
            $ultimoAviso = $cronometro.Elapsed
            Write-Host ('  [Debug-CMD] running for ' + $cronometro.Elapsed.ToString('mm\:ss') + ' (no new output; Ctrl+C interrupts and keeps the log)') -ForegroundColor DarkGray
        }
        Ps-TickSeguro      # .ps1 files and PowerShell processes found by the watchers
    }
    if ($pend.Length -gt 0) { Add-Linha $pend }
    $p.WaitForExit(5000) | Out-Null
    $codigo = $(if ($p.HasExited) { $p.ExitCode } else { -1 })
    $interrompido = $false
} catch {
    Add-Linha ('[DEBUG] Failed to run the script: ' + $_.Exception.Message)
    $interrompido = $false
} finally {
    # always runs, including on Ctrl+C: stops the process, deletes the copy and writes the summary
    $cronometro.Stop()
    if ($p -and (-not $p.HasExited)) {
        try { & $env:ComSpec /d /c "taskkill /PID $($p.Id) /T /F >nul 2>&1" } catch { }
        Start-Sleep -Milliseconds 300
    }
    if ($copia -and (-not $psEstado.Elevou) -and (Test-Path -LiteralPath $copia)) {
        Remove-Item -LiteralPath $copia -Force -ErrorAction SilentlyContinue
    }
    Ps-Fim
    try { Concluir } catch { Write-Host ('Error while building the summary: ' + $_.Exception.Message) -ForegroundColor Red }
}
exit $codigo
