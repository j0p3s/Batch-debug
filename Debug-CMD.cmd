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
rem ABRIR_LOG     abre o .log no Bloco de Notas no fim
rem MODO          ASK = pergunta de cada vez, RUN = executa, TEST = so analisa sem executar NADA
set "ELEVAR=0"
set "ECHO_ON=1"
set "IGNORAR_PAUSE=1"
set "ABRIR_LOG=1"
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
    if ($AbrirLog) { Start-Process notepad.exe -ArgumentList ('"' + $testLog + '"') }
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
Write-Host $sep -ForegroundColor DarkGray

if ($AbrirLog) { Start-Process notepad.exe -ArgumentList ('"' + $logPath + '"') }
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
