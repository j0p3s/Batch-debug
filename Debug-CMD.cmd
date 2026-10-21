@echo off
setlocal EnableExtensions
title Debug-CMD
rem ======================================================================
rem  Debug-CMD.cmd
rem  Arrasta um ficheiro .cmd ou .bat para cima deste ficheiro.
rem  Ele executa o script com echo on, regista tudo num .log (ao lado do
rem  script) e gera um resumo do que correu bem e do que falhou.
rem  Nao precisa de instalar nada: usa o PowerShell que ja vem no Windows.
rem  A janela fica sempre aberta no fim (pause) para leres o resultado.
rem ======================================================================

rem ---- Opcoes (1 = sim, 0 = nao) ----
rem ELEVAR        pede permissoes de administrador (aparece o UAC uma vez)
rem ECHO_ON       forca echo on numa copia temporaria do script
rem IGNORAR_PAUSE troca os pause da copia por uma nota, para correr sem intervencao
rem ABRIR_LOG     abre o relatorio no fim (HTML no browser, ou o .log no Bloco de Notas)
rem GERAR_HTML    cria tambem um relatorio .html facil de ler (ao lado do .log)
rem MODO          ASK = pergunta de cada vez, RUN = executa, TEST = so analisa sem executar NADA
set "ELEVAR=0"
set "ECHO_ON=1"
set "IGNORAR_PAUSE=1"
set "ABRIR_LOG=1"
set "GERAR_HTML=1"
set "MODO=ASK"

echo.
echo  [Debug-CMD] A iniciar...

if "%~1"=="" goto :sem_ficheiro
if not exist "%~1" goto :sem_ficheiro

set "DBG_TARGET=%~f1"
set "DBG_SELF=%~f0"
echo  Script alvo: "%DBG_TARGET%"

if not "%~2"=="" set "MODO=%~2"
set "DBG_MODO=%MODO%"
if /i not "%MODO%"=="ASK" goto :modo_ok
echo.
echo  What do you want to do?
echo    [E] Execute the script - it will REALLY run
echo    [T] Test only - analyze it WITHOUT running anything
choice /c ET /n /m " Choose E or T: "
if errorlevel 2 (set "DBG_MODO=TEST") else (set "DBG_MODO=RUN")
:modo_ok
if /i "%DBG_MODO%"=="TEST" goto :executar

if not "%ELEVAR%"=="1" goto :executar
fltmc >nul 2>&1 && goto :executar
echo  A pedir permissoes de administrador (UAC)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath $env:DBG_SELF -ArgumentList ([char]34 + $env:DBG_TARGET + [char]34 + [char]32 + $env:DBG_MODO) -Verb RunAs"
if errorlevel 1 goto :falha_elevar
echo.
echo  Foi aberta uma nova janela com permissoes de administrador.
echo  A execucao continua nessa janela. Podes fechar esta.
echo  Se a nova janela nao apareceu, poe ELEVAR a 0 no topo deste ficheiro.
echo.
pause
exit /b

:falha_elevar
echo.
echo  Nao foi possivel obter permissoes de administrador.
echo  Dica: poe ELEVAR a 0 no topo deste ficheiro para correr sem administrador.
echo.
pause
exit /b 1

:executar
set "DBG_PS1=%TEMP%\Debug-CMD_%RANDOM%.ps1"
echo  A preparar o motor PowerShell...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:DBG_SELF,[Text.Encoding]::UTF8); $i=$t.IndexOf('#PS'+'_BEGIN'); [IO.File]::WriteAllText($env:DBG_PS1,$t.Substring($i),(New-Object Text.UTF8Encoding $true))"
if errorlevel 1 goto :falha_ps
if not exist "%DBG_PS1%" goto :falha_ps
echo  A executar...
powershell -NoProfile -ExecutionPolicy Bypass -File "%DBG_PS1%"
set "RC=%errorlevel%"
echo.
if "%RC%"=="0" del "%DBG_PS1%" >nul 2>&1
if not "%RC%"=="0" echo  Codigo de saida: %RC%  (motor PowerShell guardado em "%DBG_PS1%" para diagnostico)
echo.
pause
exit /b %RC%

:falha_ps
echo.
echo  Falha ao preparar o motor PowerShell. Ve a mensagem de erro acima.
echo.
pause
exit /b 1

:sem_ficheiro
echo.
echo  Arrasta um ficheiro .cmd ou .bat para cima deste ficheiro.
echo.
pause
exit /b 1

#PS_BEGIN
$ErrorActionPreference = 'Stop'
$Alvo     = $env:DBG_TARGET
$EchoOn   = ($env:ECHO_ON -ne '0')
$IgnPause = ($env:IGNORAR_PAUSE -ne '0')
$AbrirLog = ($env:ABRIR_LOG -ne '0')
$utf8bom  = New-Object System.Text.UTF8Encoding($true)

if (-not (Test-Path -LiteralPath $Alvo -PathType Leaf)) {
    Write-Host "Ficheiro não encontrado: $Alvo" -ForegroundColor Red
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
summary{cursor:pointer;padding:8px 12px;display:flex;gap:10px;align-items:baseline}
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
.lv.HIGH,.lv.ERROR{background:var(--bad)}.lv.MEDIUM{background:var(--warn)}.lv.LOW{background:var(--mut)}
.list td{padding:3px 8px 3px 0;vertical-align:top}
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

# ---------- TEST mode: static analysis, NOTHING is executed ----------
if ($env:DBG_MODO -eq 'TEST') {
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
        @('MEDIUM', '\breg\s+(add|import)\b',                    'Changes the registry'),
        @('MEDIUM', '\b(move|ren|rename)\b',                     'Moves or renames files'),
        @('MEDIUM', '\b(copy|xcopy|robocopy)\b',                 'Copies files (may overwrite)'),
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
        @('LOW',    '\bstart\b',                                 'Starts another program'),
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

    for ($n = 0; $n -lt $src.Count; $n++) {
        $t = $src[$n].Trim()
        if ($t.Length -eq 0) { continue }
        if ($t -match '^(@?rem(\s|$)|::)') { continue }
        $mr = [regex]::Match($t, '^:([^\s:]\S*)')
        if ($mr.Success) { $rotulos[$mr.Groups[1].Value.ToLower()] = $n + 1; continue }
        $comandos++
        $ex = $t
        if ($ex.Length -gt 160) { $ex = $ex.Substring(0, 160) + ' [...]' }

        foreach ($r in $regras) {
            if ($t -match ('(?i)' + $r[1])) {
                $cont[$r[0]]++
                $achados.Add(('[{0}] line {1}: {2}' -f $r[0], ($n + 1), $r[2]))
                $achados.Add('           ' + $ex)
                $achadosObj.Add(@($r[0], ($n + 1), $r[2], $ex))
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
    $rel.Add('')
    $rel.Add('Notes: nothing was run and no variable was expanded. Commands built from variables, scripts it calls, and')
    $rel.Add('anything decided at run time are not analyzed. Use RUN mode only if you trust the script.')

    $testLog = Join-Path $pasta ('{0}_test_{1}.log' -f $nome, $inicio.ToString('yyyy-MM-dd_HH-mm-ss'))
    try { [IO.File]::WriteAllLines($testLog, [string[]]$rel.ToArray(), $utf8bom) }
    catch {
        $testLog = Join-Path $env:TEMP ([IO.Path]::GetFileName($testLog))
        [IO.File]::WriteAllLines($testLog, [string[]]$rel.ToArray(), $utf8bom)
    }

    $htmlTest = $null
    if ($env:GERAR_HTML -ne '0') {
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
                    [void]$bT.AppendLine('<tr><td><span class="lv ' + $a[0] + '">' + $a[0] + '</span></td><td class="t">line ' + $a[1] + '</td><td>' + (EscHtml ([string]$a[2])) + '<br><code>' + (EscHtml ([string]$a[3])) + '</code></td></tr>')
                }
                [void]$bT.AppendLine('</table>')
            }
            [void]$bT.AppendLine('<p class="k" style="color:var(--mut)">Nothing was run and no variable was expanded. Commands built from variables, scripts it calls, and anything decided at run time are not analyzed.</p>')
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
    # pasta sem permissão de escrita: usa a pasta temporária
    $logPath = Join-Path $env:TEMP ([IO.Path]::GetFileName($logPath))
    $sw = New-Object System.IO.StreamWriter($logPath, $false, $utf8bom)
}
$sw.AutoFlush = $true

$linhas = New-Object System.Collections.Generic.List[string]
$horas  = New-Object System.Collections.Generic.List[string]
function Add-Linha([string]$texto) {
    $texto = ($texto -replace "`r", ' ').TrimEnd()
    if ($texto.Length -eq 0) { return }
    if ($texto.Length -gt 600) { $texto = $texto.Substring(0, 600) + ' [...]' }
    $h = (Get-Date).ToString('HH:mm:ss.fff')
    $sw.WriteLine("[$h] $texto")
    $linhas.Add($texto)
    $horas.Add($h)
}

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
try { $so = (Get-CimInstance Win32_OperatingSystem).Caption } catch { $so = [Environment]::OSVersion.VersionString }

# ---------- cópia temporária com echo on (e pause ignorado) ----------
$aExecutar = $Alvo
$copia     = $null
$ajustes   = New-Object System.Collections.Generic.List[string]
if ($EchoOn -or $IgnPause) {
    try {
        $enc  = [Text.Encoding]::GetEncoding(28591)   # Latin-1: preserva os bytes do script tal e qual
        $txt  = [IO.File]::ReadAllText($Alvo, $enc)
        $novo = $txt
        if ($EchoOn) {
            $novo = [regex]::Replace($novo, '(?im)^([ \t]*)@?echo[ \t]+off\b', '${1}@echo on')
            if ($novo -ne $txt) { $ajustes.Add('echo off -> echo on') }
        }
        if ($IgnPause) {
            $antes = $novo
            $novo  = [regex]::Replace($novo, '(?im)^([ \t]*)@?pause\b[^\r\n]*(?=\r?$)', '${1}echo [DEBUG] pause ignorado')
            if ($novo -ne $antes) { $ajustes.Add('pause -> ignorado') }
        }
        if ($novo -ne $txt) {
            $copia = Join-Path $pasta ('__dbg_' + $nome + $ext)
            [IO.File]::WriteAllText($copia, $novo, $enc)
            $aExecutar = $copia
        }
    } catch {
        $ajustes.Add('não foi possível criar a cópia, a correr o original: ' + $_.Exception.Message)
        $copia = $null
        $aExecutar = $Alvo
    }
}

# ---------- cabeçalho do log ----------
$sep = '=' * 78
$sw.WriteLine($sep)
$sw.WriteLine(' INFORMAÇÃO DA EXECUÇÃO')
$sw.WriteLine($sep)
$sw.WriteLine("Script        : $Alvo")
$sw.WriteLine('Início        : ' + $inicio.ToString('yyyy-MM-dd HH:mm:ss'))
$sw.WriteLine("Utilizador    : $env:USERDOMAIN\$env:USERNAME")
$sw.WriteLine("Windows       : $so")
$sw.WriteLine('Administrador : ' + $(if ($admin) { 'Sim' } else { 'Não' }))
$sw.WriteLine('Executado     : ' + $(if ($copia) { "cópia temporária ($aExecutar)" } else { 'ficheiro original' }))
if ($ajustes.Count -gt 0) { $sw.WriteLine('Ajustes       : ' + ($ajustes -join '; ')) }
$sw.WriteLine($sep)
$sw.WriteLine(' LOG DETALHADO   [hora] saída do script (os comandos aparecem como C:\pasta>comando)')
$sw.WriteLine($sep)

Write-Host ''
Write-Host "A executar: $Alvo" -ForegroundColor Cyan
Write-Host "Log       : $logPath" -ForegroundColor DarkGray
Write-Host ('-' * 70) -ForegroundColor DarkGray

function Concluir {
$fim = Get-Date
$dur = $cronometro.Elapsed.ToString('hh\:mm\:ss\.fff')
$sw.WriteLine($sep)
$sw.WriteLine('Fim           : ' + $fim.ToString('yyyy-MM-dd HH:mm:ss') + "   (duração $dur)")
$sw.WriteLine("Código de saída: $codigo")
if ($interrompido) { $sw.WriteLine('*** EXECUÇÃO INTERROMPIDA (Ctrl+C): o script não chegou ao fim ***') }
$sw.Close()

# ---------- análise ----------
$rxPrompt = '^(?:[A-Za-z]:\\|\\\\)[^>]*>(?<c>.*)$'
$rxErro   = '\b(erro|erros|error|errors)\b|\bfalh|\bfail|\bfatal\b|exce[pç]|n[aã]o [eé] reconhecido|not recognized|n[aã]o foi poss[ií]vel|n[aã]o consegu|n[aã]o foi encontrad|n[aã]o existe|o sistema n[aã]o|cannot find|could not find|does not exist|access is denied|acesso negado|permission denied|negad[oa]\b|denied|invalid|inv[aá]lid|sintaxe|syntax|unable to|utilizado por outro processo|used by another process|timed out|esgotad'
$triv     = '^(rem(\s|$)|::|:[^\s:]|@?echo\s+(on|off)\b)'

$entradas = New-Object System.Collections.Generic.List[object]
$atual = [pscustomobject]@{
    Cmd = '(saída sem comando associado)'; Hora = ''; Pseudo = $true
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
        if ($l -match $rxErro) { $atual.Problemas.Add($l) }
    }
}

$cmds     = @($entradas | Where-Object { (-not $_.Pseudo) -and ($_.Cmd -notmatch $triv) })
$comProb  = @($entradas | Where-Object { $_.Problemas.Count -gt 0 })
$bem      = @($cmds | Where-Object { $_.Problemas.Count -eq 0 })
$totalErr = 0
foreach ($e in $entradas) { $totalErr += $e.Problemas.Count }

$estado = $(if ($interrompido) { 'INTERROMPIDO' } elseif (($codigo -ne 0) -or ($comProb.Count -gt 0)) { 'COM PROBLEMAS' } else { 'OK' })
$nota   = $(if ($interrompido) { '   (interrompido: o script não chegou ao fim)' } elseif ($codigo -ne 0) { '   (diferente de 0: o último comando terminou com erro)' } else { '' })

$res = New-Object System.Collections.Generic.List[string]
$res.Add($sep); $res.Add(' RESUMO'); $res.Add($sep)
$res.Add("Script           : $Alvo")
$res.Add("Estado           : $estado")
if ($interrompido) { $res.Add('Aviso            : a execução foi interrompida antes de o script terminar; o resultado abaixo é parcial.') }
$res.Add("Código de saída  : $codigo$nota")
$res.Add("Duração          : $dur")
$res.Add("Comandos         : $($cmds.Count) executados | $($bem.Count) sem erros detetados | $($comProb.Count) com problemas")
$res.Add("Linhas de erro   : $totalErr")
if ((-not $admin) -and (@($comProb | ForEach-Object { $_.Problemas }) -match 'acesso negado|access is denied')) {
    $res.Add('Sugestão         : houve "acesso negado" e o script correu SEM administrador (ver opção ELEVAR no topo do Debug-CMD.cmd).')
}

$res.Add('')
$res.Add($sep); $res.Add(' O QUE FALHOU'); $res.Add($sep)
if ($comProb.Count -eq 0) {
    $res.Add('Nenhum erro detetado.')
} else {
    $n = 0
    foreach ($e in $comProb) {
        $n++
        if ($n -gt 60) { $res.Add("... (+$($comProb.Count - 60) comandos com problemas; ver o log detalhado)"); break }
        $res.Add(('[FALHOU] [{0}] {1}' -f $e.Hora, $e.Cmd))
        foreach ($pl in ($e.Problemas | Select-Object -First 4)) { $res.Add("           > $pl") }
    }
}

$res.Add('')
$res.Add($sep); $res.Add(' O QUE CORREU BEM  (comandos sem erros detetados)'); $res.Add($sep)
if ($bem.Count -eq 0) {
    $res.Add('(nenhum comando identificado)')
} else {
    $n = 0
    foreach ($e in $bem) {
        $n++
        if ($n -gt 300) { $res.Add("... (+$($bem.Count - 300) omitidos; ver o log detalhado)"); break }
        $res.Add(('[ OK ]   [{0}] {1}' -f $e.Hora, $e.Cmd))
    }
}
$res.Add('')
$res.Add('Nota: "sem erros detetados" = nenhuma linha de erro conhecida na saída do comando. Comandos com >nul 2>&1 escondem os erros.')
$res.Add('')

# resumo no topo do .log
$corpo = [IO.File]::ReadAllLines($logPath, $utf8bom)
$final = [string[]](@($res.ToArray()) + @($corpo))
[IO.File]::WriteAllLines($logPath, $final, $utf8bom)

# ---------- HTML report ----------
$htmlPath = $null
if ($env:GERAR_HTML -ne '0') {
    try {
        $clsEstado = 'ok'
        $txtEstado = 'OK'
        if ($estado -eq 'COM PROBLEMAS') { $clsEstado = 'bad'; $txtEstado = 'WITH PROBLEMS' } elseif ($estado -eq 'INTERROMPIDO') { $clsEstado = 'warn'; $txtEstado = 'INTERRUPTED' }

        $cart = New-Object System.Collections.Generic.List[object]
        $cart.Add(@('Commands', $cmds.Count, ''))
        $cart.Add(@('Worked', $bem.Count, 'ok'))
        $cart.Add(@('With problems', $comProb.Count, $(if ($comProb.Count -gt 0) { 'bad' } else { 'ok' })))
        $cart.Add(@('Exit code', $codigo, $(if ($codigo -ne 0) { 'bad' } else { 'ok' })))
        $cart.Add(@('Duration', $dur, ''))

        $inf = New-Object System.Collections.Generic.List[object]
        $inf.Add(@('Script', $Alvo))
        $inf.Add(@('Started', $inicio.ToString('yyyy-MM-dd HH:mm:ss')))
        $inf.Add(@('User', "$env:USERDOMAIN\$env:USERNAME"))
        $inf.Add(@('Windows', "$so"))
        $inf.Add(@('Administrator', $(if ($admin) { 'Yes' } else { 'No' })))
        $inf.Add(@('Ran as', $(if ($copia) { 'temporary copy with echo on' } else { 'original file' })))
        if ($ajustes.Count -gt 0) { $inf.Add(@('Adjustments', ($ajustes -join '; '))) }
        if ($interrompido) { $inf.Add(@('Warning', 'The run was interrupted before the script finished; results are partial.')) }
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
                    if ($sl -match $rxErro) { [void]$b.AppendLine('<span class="err">' + (EscHtml $sl) + '</span>') } else { [void]$b.AppendLine((EscHtml $sl)) }
                }
                [void]$b.AppendLine('</pre></details>')
            }
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
            if ([regex]::IsMatch($tx, $rxPrompt)) { $rc = 'cmd' } elseif ($tx -match $rxErro) { $rc = 'err' }
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

# resumo no ecrã
$cor = $(if ($estado -eq 'OK') { 'Green' } else { 'Red' })
Write-Host ''
Write-Host $sep -ForegroundColor DarkGray
Write-Host " Estado: $estado   |   Código de saída: $codigo   |   Duração: $dur" -ForegroundColor $cor
Write-Host " Comandos: $($cmds.Count) executados, $($bem.Count) sem erros, $($comProb.Count) com problemas"
foreach ($e in ($comProb | Select-Object -First 10)) {
    Write-Host ('  [FALHOU] ' + $e.Cmd) -ForegroundColor Yellow
    foreach ($pl in ($e.Problemas | Select-Object -First 2)) { Write-Host ('           > ' + $pl) -ForegroundColor DarkYellow }
}
if ($comProb.Count -gt 10) { Write-Host "  ... (+$($comProb.Count - 10) no log)" }
Write-Host " Log: $logPath"
if ($htmlPath) { Write-Host " HTML: $htmlPath" }
Write-Host $sep -ForegroundColor DarkGray

if ($AbrirLog) {
    if ($htmlPath) { Start-Process -FilePath $htmlPath } else { Start-Process notepad.exe -ArgumentList ('"' + $logPath + '"') }
}
}

# ---------- execução ----------
$cronometro   = [Diagnostics.Stopwatch]::StartNew()
$codigo       = -1
$interrompido = $true      # passa a $false quando a execução termina sem ser interrompida
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
            [Console]::Write($pedaco)      # o ecrã mostra tudo em tempo real, sem esperar por fim de linha
            $pend += $pedaco
            while (($i = $pend.IndexOf("`n")) -ge 0) {
                Add-Linha ($pend.Substring(0, $i))
                $pend = $pend.Substring($i + 1)
            }
            $tarefa = $reader.ReadAsync($buf, 0, $buf.Length)
        } elseif ($p.HasExited) {
            # o script terminou mas deixou um processo em segundo plano com o pipe aberto: não ficar à espera
            $ociosos++
            if ($ociosos -ge 8) { break }
        } elseif (($cronometro.Elapsed - $ultimoAviso).TotalSeconds -ge 10) {
            # comando demorado e silencioso: avisa que continua vivo
            $ultimoAviso = $cronometro.Elapsed
            Write-Host ('  [Debug-CMD] a correr há ' + $cronometro.Elapsed.ToString('mm\:ss') + ' (sem saída nova; Ctrl+C interrompe e guarda o log)') -ForegroundColor DarkGray
        }
    }
    if ($pend.Length -gt 0) { Add-Linha $pend }
    $p.WaitForExit(5000) | Out-Null
    $codigo = $(if ($p.HasExited) { $p.ExitCode } else { -1 })
    $interrompido = $false
} catch {
    Add-Linha ('[DEBUG] Falha ao executar o script: ' + $_.Exception.Message)
    $interrompido = $false
} finally {
    # corre sempre, também quando o utilizador carrega Ctrl+C: fecha o processo, apaga a cópia e escreve o resumo
    $cronometro.Stop()
    if ($p -and (-not $p.HasExited)) {
        try { & $env:ComSpec /d /c "taskkill /PID $($p.Id) /T /F >nul 2>&1" } catch { }
        Start-Sleep -Milliseconds 300
    }
    if ($copia -and (Test-Path -LiteralPath $copia)) {
        Remove-Item -LiteralPath $copia -Force -ErrorAction SilentlyContinue
    }
    try { Concluir } catch { Write-Host ('Erro ao gerar o resumo: ' + $_.Exception.Message) -ForegroundColor Red }
}
exit $codigo
