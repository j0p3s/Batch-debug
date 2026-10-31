# Debug-CMD

[English](README.md) | Português

Arrasta um `.cmd` ou `.bat` para cima do `Debug-CMD_v1.4.0.cmd` e obtém um `.log` com tudo o que o script fez, mais um resumo do que correu bem e do que falhou.

Um único ficheiro, sem instalar nada: usa o PowerShell que já vem no Windows 10/11.

## Funcionalidades

- **Relatório HTML fácil de ler:** além do `.log`, geras uma página `.html` autónoma (não precisa de internet) com estado, cartões de resumo, comandos falhados expansíveis, lista do que correu bem e log completo filtrável. Acompanha o tema claro/escuro.
- **PowerShell também fica no log:** se o script escreve ficheiros `.ps1` ou corre PowerShell, o log guarda o conteúdo completo de cada `.ps1` que ele escreve ou corre (mesmo os temporários que o script apaga logo a seguir), cada PowerShell que ele arranca (mesmo quando o comando não aparece com o echo), o `-EncodedCommand` descodificado e a linha do `.ps1` onde o PowerShell deu erro.
- **Ferramentas de um só `.cmd` também:** muitas ferramentas trazem o PowerShell dentro do `.cmd` e correm-no a partir da memória (`Invoke-Expression`), por isso nunca existe um `.ps1` no disco. O Debug-CMD recorta esse código do ficheiro tal como o PowerShell faz, regista-o com números de linha e guarda-o ao lado do log como `<nome>_debug_<data>.embedded1.ps1`, para os `At line:N` do PowerShell coincidirem com esse ficheiro.
- **Os ficheiros que o script cria são recolhidos:** muitas ferramentas escrevem o seu próprio log, relatório ou definições enquanto correm (`.log`, `.txt`, `.json`, `.csv`, `.xml`, `.ini`). O Debug-CMD encontra os que foram criados ou alterados durante a execução, na pasta do script e em pastas que o script menciona (como `C:\Nome` ou `%SystemDrive%\Nome`), e põe o conteúdo no relatório com as linhas que parecem erros marcadas. Podes juntar mais pastas com `COLLECT_DIRS`.
- **Scripts que pedem administrador:** com `ELEVATE=AUTO` (o valor por defeito), o Debug-CMD corre como administrador quando o script contém `runas`, `fltmc`, `net session` e semelhantes. Se não o fizer, o script reinicia-se numa janela nova que não se consegue seguir.
- **Modo de teste seguro:** escolhe `T` no início para só analisar o script. Nada é executado. Assinala comandos perigosos (apagar, formatar, registo, desligar, downloads...) no script, no PowerShell embutido ou codificado e nos `.ps1` que ele usa e que já existem no disco, além de destinos de `goto`/`call` inexistentes. Nas ferramentas de um só ficheiro, as verificações de batch (`goto`, `call`, etiquetas) param no marcador `#PS-BEGIN` e só as regras de risco são aplicadas ao PowerShell embutido.
- **Debug linha a linha:** executa uma cópia temporária do script com `echo on`, por isso o log mostra cada comando antes da respetiva saída.
- **Log com hora:** cada linha tem hora com milissegundos. O topo do log traz o utilizador, a versão do Windows e se correu como administrador.
- **Resumo no topo do log e no ecrã:**
  - estado final: `OK`, `WITH PROBLEMS` ou `INTERRUPTED`;
  - código de saída e duração;
  - **WHAT FAILED:** comandos com erro e as linhas de erro respetivas;
  - **WHAT WORKED:** comandos sem erros detetados.
- **Sem intervenção:** os `pause` da cópia são ignorados, para o script correr até ao fim.
- **Robusto:** com Ctrl+C o log e o resumo ficam guardados, o processo é fechado e a cópia temporária é apagada.
- **Não parece bloqueado:** em comandos demorados e silenciosos aparece "a correr há mm:ss" a cada 10 segundos.
- **Original intocado:** o script que arrastas nunca é alterado.

## Utilização

1. Descarrega o `Debug-CMD_v1.4.0.cmd`.
2. Arrasta o teu `.cmd` ou `.bat` para cima dele.
3. No fim, a janela fica aberta e o relatório HTML abre no browser.

O log é criado ao lado do script, com o nome `NomeDoScript_debug_AAAA-MM-DD_HH-MM-SS.log`. Se a pasta não permitir escrita, vai para a pasta temporária.

## Modos

Ao arrastar um script, és perguntado:

- **`E` - Executar:** corre o script a sério e faz o debug (log + resumo).
- **`T` - Só testar:** análise estática. O script só é lido, **nunca é executado**. Obténs um relatório `Nome_test_<data>.log` com o veredito de risco, as linhas que podem alterar o sistema (ALTO / MÉDIO / BAIXO), problemas estruturais, como um `goto` para uma etiqueta que não existe ou um `call` para um ficheiro em falta, e uma secção de PowerShell com as linhas que escrevem ficheiros `.ps1` ou correm PowerShell.

Põe `MODE` a `RUN` ou `TEST` para não perguntar.

## Opções

Estão no topo do `Debug-CMD_v1.4.0.cmd` (`1` = sim, `0` = não; `ELEVATE` e `MODE` usam palavras):

| Opção | Por defeito | O que faz |
|---|---|---|
| `ELEVATE` | `AUTO` | `0` nunca, `1` sempre, `AUTO` só quando o script pede administrador (aparece o UAC uma vez) |
| `ECHO_ON` | `1` | Força `echo on` na cópia temporária |
| `SKIP_PAUSE` | `1` | Troca os `pause` da cópia por uma nota |
| `OPEN_REPORT` | `1` | Abre o relatório no fim (HTML no browser, ou o log no Bloco de Notas) |
| `GENERATE_HTML` | `1` | Cria também o relatório `.html` ao lado do `.log` |
| `LOG_PS1` | `1` | Regista também o PowerShell: os `.ps1` que o script escreve ou corre (conteúdo completo), os processos PowerShell que ele arranca e o `-EncodedCommand` descodificado |
| `COLLECT_FILES` | `1` | Recolhe também os ficheiros de texto que o script cria ou altera enquanto corre (logs, relatórios, definições) e mostra-os no relatório |
| `COLLECT_DIRS` | *(vazio)* | Pastas extra onde procurar, separadas por ponto e vírgula (a pasta do script e as pastas que ele menciona são automáticas) |
| `MODE` | `ASK` | `ASK` pergunta sempre, `RUN` executa sempre, `TEST` só analisa (não executa nada) |

## Exemplo de resumo (o relatório está em inglês)

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
[RUN]    [23:10:17.002] powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\Eu\AppData\Local\Temp\fix.ps1"
           > runs C:\Users\Eu\AppData\Local\Temp\fix.ps1
[PS1 1]  C:\Users\Eu\AppData\Local\Temp\fix.ps1
           > written during the run | ran 1x | deleted before the end | 12 lines
```

## Como funciona

1. O `.cmd` extrai o PowerShell que traz embutido para um `.ps1` temporário e executa-o.
2. O PowerShell cria uma cópia do script alvo (`__dbg_<nome>`) com `echo off` → `echo on` e `pause` ignorado. A cópia preserva os bytes do original.
3. Corre a cópia com `cmd /c`, junta `stdout` e `stderr` pela ordem em que aparecem e regista cada linha com hora.
4. Durante a execução, um vigilante de ficheiros na pasta do script e no `%TEMP%` (incluindo subpastas) lê cada `.ps1` no momento em que é escrito, e um vigilante de processos deteta cada PowerShell que o script arranca. Os `.ps1` indicados em comandos `powershell` que aparecem no echo também são lidos, estejam onde estiverem. O CLIXML que o PowerShell escreve quando a saída é redirecionada volta a ser texto legível.
5. Quando um comando PowerShell lê código de um ficheiro e o corre com `Invoke-Expression` / `iex` (por exemplo `$t.Substring($t.IndexOf('#PS-BEGIN'))` ou `iex (${ficheiro.cmd} | out-string)`), o mesmo código é recortado desse ficheiro, registado como "run from memory" e guardado como um `.ps1` verdadeiro ao lado do log.
6. No fim, o log é analisado: as linhas que correspondem a padrões de erro (português e inglês) são associadas ao comando que as produziu, e cada `.ps1` capturado é acrescentado ao log com números de linha.

## Limitações

- O modo de teste é uma análise por palavras-chave ao texto do script: não expande variáveis, não segue os scripts que ele chama e não vê comandos construídos em tempo de execução. Reduz o risco, não garante segurança.
- Um `cmd` não deixa ver o que se passa por dentro, por isso a deteção de erros é feita por **palavras-chave** na saída (por exemplo "não é reconhecido", "acesso negado", "failed"). Pode falhar erros em outros idiomas e pode dar falsos positivos, por exemplo num `echo` que escreva "erro".
- Não há código de erro por comando, só o do fim.
- Comandos com `>nul 2>&1` escondem os próprios erros.
- Só o script arrastado é forçado a `echo on`. Os scripts que ele chama com `call` mantêm o `echo off` deles.
- `%0`, `%~nx0` e semelhantes apontam para a cópia `__dbg_...`.
- O código PowerShell construído ou descarregado em tempo de execução (por exemplo `iex (irm https://...)`, ou um texto montado em memória) não se consegue recortar de um ficheiro. A linha de comandos fica no log por inteiro, mas o código não.
- Um script que se reinicia como administrador noutra janela (`Start-Process -Verb RunAs`) só se consegue seguir se o próprio Debug-CMD correr como administrador. O log avisa disso e guarda a cópia temporária.
- Um `.ps1` escrito fora da pasta do script e do `%TEMP%` só fica no log se for visto um comando PowerShell que o corra. Um PowerShell que não aparece no echo e termina em menos de cerca de meio segundo pode escapar ao vigilante de processos.
- Se a captura em direto não puder arrancar (por exemplo, uma política que bloqueie a compilação), só ficam no log os `.ps1` corridos por comandos que aparecem no echo. O log indica-o.
- Os `pause` ignorados e a cópia mudam ligeiramente o comportamento do script. Desativa com `SKIP_PAUSE=0` e `ECHO_ON=0` se isso for um problema.
- Se carregares Ctrl+C e aparecer "Terminate batch job (Y/N)?", responde `N` para ver o resumo.
- Não use o Ctrl+C para copiar texto da janela: nesta consola interrompe a execução.

## Requisitos

- Windows 10 ou 11 com o Windows PowerShell 5.1 (já incluído).

## Aviso

O script alvo é **executado a sério**. Se apaga ficheiros, instala programas ou muda definições, fará o mesmo durante o debug. Testa primeiro com cuidado.

## Licença

[MIT](LICENSE)
