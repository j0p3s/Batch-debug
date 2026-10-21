# Debug-CMD

[English](README.md) | Português

Arrasta um `.cmd` ou `.bat` para cima do `Debug-CMD.cmd` e obtém um `.log` com tudo o que o script fez, mais um resumo do que correu bem e do que falhou.

Um único ficheiro, sem instalar nada: usa o PowerShell que já vem no Windows 10/11.

## Funcionalidades

- **Relatório HTML fácil de ler:** além do `.log`, geras uma página `.html` autónoma (não precisa de internet) com estado, cartões de resumo, comandos falhados expansíveis, lista do que correu bem e log completo filtrável. Acompanha o tema claro/escuro.
- **Modo de teste seguro:** escolhe `T` no início para só analisar o script. Nada é executado. Assinala comandos perigosos (apagar, formatar, registo, desligar, downloads...) e destinos de `goto`/`call` inexistentes.
- **Debug linha a linha:** executa uma cópia temporária do script com `echo on`, por isso o log mostra cada comando antes da respetiva saída.
- **Log com hora:** cada linha tem hora com milissegundos. O topo do log traz o utilizador, a versão do Windows e se correu como administrador.
- **Resumo no topo do log e no ecrã:**
  - estado final: `OK`, `COM PROBLEMAS` ou `INTERROMPIDO`;
  - código de saída e duração;
  - **O QUE FALHOU:** comandos com erro e as linhas de erro respetivas;
  - **O QUE CORREU BEM:** comandos sem erros detetados.
- **Sem intervenção:** os `pause` da cópia são ignorados, para o script correr até ao fim.
- **Robusto:** com Ctrl+C o log e o resumo ficam guardados, o processo é fechado e a cópia temporária é apagada.
- **Não parece bloqueado:** em comandos demorados e silenciosos aparece "a correr há mm:ss" a cada 10 segundos.
- **Original intocado:** o script que arrastas nunca é alterado.

## Utilização

1. Descarrega o `Debug-CMD.cmd`.
2. Arrasta o teu `.cmd` ou `.bat` para cima dele.
3. No fim, a janela fica aberta e o relatório HTML abre no browser.

O log é criado ao lado do script, com o nome `NomeDoScript_debug_AAAA-MM-DD_HH-MM-SS.log`. Se a pasta não permitir escrita, vai para a pasta temporária.

## Modos

Ao arrastar um script, és perguntado:

- **`E` - Executar:** corre o script a sério e faz o debug (log + resumo).
- **`T` - Só testar:** análise estática. O script só é lido, **nunca é executado**. Obténs um relatório `Nome_test_<data>.log` com o veredito de risco, as linhas que podem alterar o sistema (ALTO / MÉDIO / BAIXO) e problemas estruturais, como um `goto` para uma etiqueta que não existe ou um `call` para um ficheiro em falta.

Põe `MODO` a `RUN` ou `TEST` para não perguntar.

## Opções

Estão no topo do `Debug-CMD.cmd` (`1` = sim, `0` = não):

| Opção | Por defeito | O que faz |
|---|---|---|
| `ELEVAR` | `0` | Pede permissões de administrador (aparece o UAC uma vez) |
| `ECHO_ON` | `1` | Força `echo on` na cópia temporária |
| `IGNORAR_PAUSE` | `1` | Troca os `pause` da cópia por uma nota |
| `ABRIR_LOG` | `1` | Abre o relatório no fim (HTML no browser, ou o log no Bloco de Notas) |
| `GERAR_HTML` | `1` | Cria também o relatório `.html` ao lado do `.log` |
| `MODO` | `ASK` | `ASK` pergunta sempre, `RUN` executa sempre, `TEST` só analisa (não executa nada) |

## Exemplo de resumo

```
==============================================================================
 RESUMO
==============================================================================
Script           : C:\Scripts\exemplo.cmd
Estado           : COM PROBLEMAS
Código de saída  : 1   (diferente de 0: o último comando terminou com erro)
Duração          : 00:00:03.412
Comandos         : 6 executados | 5 sem erros detetados | 1 com problemas
Linhas de erro   : 1

==============================================================================
 O QUE FALHOU
==============================================================================
[FALHOU] [23:10:16.531] copy origem.txt destino\
           > O sistema não consegue localizar o ficheiro especificado.
```

## Como funciona

1. O `.cmd` extrai o PowerShell que traz embutido para um `.ps1` temporário e executa-o.
2. O PowerShell cria uma cópia do script alvo (`__dbg_<nome>`) com `echo off` → `echo on` e `pause` ignorado. A cópia preserva os bytes do original.
3. Corre a cópia com `cmd /c`, junta `stdout` e `stderr` pela ordem em que aparecem e regista cada linha com hora.
4. No fim, o log é analisado: as linhas que correspondem a padrões de erro (português e inglês) são associadas ao comando que as produziu.

## Limitações

- O modo de teste é uma análise por palavras-chave ao texto do script: não expande variáveis, não segue os scripts que ele chama e não vê comandos construídos em tempo de execução. Reduz o risco, não garante segurança.
- Um `cmd` não deixa ver o que se passa por dentro, por isso a deteção de erros é feita por **palavras-chave** na saída (por exemplo "não é reconhecido", "acesso negado", "failed"). Pode falhar erros em outros idiomas e pode dar falsos positivos, por exemplo num `echo` que escreva "erro".
- Não há código de erro por comando, só o do fim.
- Comandos com `>nul 2>&1` escondem os próprios erros.
- Só o script arrastado é forçado a `echo on`. Os scripts que ele chama com `call` mantêm o `echo off` deles.
- `%0`, `%~nx0` e semelhantes apontam para a cópia `__dbg_...`.
- Os `pause` ignorados e a cópia mudam ligeiramente o comportamento do script. Desativa com `IGNORAR_PAUSE=0` e `ECHO_ON=0` se isso for um problema.
- Se carregares Ctrl+C e aparecer "Terminate batch job (Y/N)?", responde `N` para ver o resumo.
- Não use o Ctrl+C para copiar texto da janela: nesta consola interrompe a execução.

## Requisitos

- Windows 10 ou 11 com o Windows PowerShell 5.1 (já incluído).

## Aviso

O script alvo é **executado a sério**. Se apaga ficheiros, instala programas ou muda definições, fará o mesmo durante o debug. Testa primeiro com cuidado.

## Licença

[MIT](LICENSE)
