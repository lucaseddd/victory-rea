# 3. Do fonte ao PE

O VIctory é código aberto e a build traz o PDB. Por isso a engenharia reversa aqui é sobretudo **confirmação**: o fonte diz o que deveria acontecer; o PDB e o PE dizem o que foi compilado com aquela configuração.

## Fluxo

1. **Fonte.** Ache a função e as variáveis que a controlam. Exemplo: `queue2::second()` só retorna uma fila quando `VICTORY_QUEUE2=1`.
2. **PDB.** Confirme que o símbolo existe e anote o RVA. Funções pequenas costumam ser inlined. Nesse caso, ache o chamador e o ponto da chamada.
3. **PE.** No Ghidra, importe o `victory.exe` com o `victory.pdb` (File → Import, depois Analysis com PDB). Vá ao RVA e confira:
   - a chamada esperada (por exemplo, `ExecuteCommandLists` e `Signal` em sequência);
   - o ramo controlado pela variável;
   - a ordem das operações (quem publica a fence depois de quê).
4. **Conferência cruzada.** `dumpbin /disasm /range:<VA ini>,<VA fim> victory.exe` dá uma segunda leitura sem Ghidra. Anote só endereço e nome; a listagem fica na evidência local.
5. **Spot-check independente.** Outra IA confere uma amostra das afirmações. Em 2026-11-26, R00 conferiu 8 de 8 endereços de R01/R02 no PE da candidata [relatado].

## O que vira texto publicável

| Pode | Não pode |
|---|---|
| `fence::set` chamado em RVA `0x2AE4E3`, depois de `Late::Write` | as linhas de instrução ao redor |
| "o `Wait` da COPY fica num laço sobre pares (fence, valor)" | a listagem do laço |
| "`VICTORY_QUEUE2=1` ativa `BESIDE`, `Second::sent_up` e duas filas COPY" | strings ou tabelas copiadas do título |
| hash, GUID/age, RVAs, nomes de símbolos do VIctory | qualquer coisa do executável do título |

A checagem `Test-RepoContent` recusa listagens com endereço, bytes e mnemônico, e blocos de instruções. Não tente contorná-la: descreva em palavras.

## Ghidra assistido por IA

- Peça à IA uma pergunta fechada por vez ("quem chama `relay_land` e com que fence?"), não "analise o exe".
- Dê o RVA e o nome do símbolo; a IA navega mais rápido e erra menos.
- Exija na resposta: endereço, símbolo, a linha correspondente no fonte e a marca `[obs-local]`.
- Desconfie de conclusões sobre o ramo "padrão" sem a configuração efetiva da rodada (`<log>.settings.txt`).
