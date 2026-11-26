# Como contribuir

Este protocolo traduz para o GitHub o quadro local `REA-COORD` (claims atômicos, status, journal, evidence e lock da GPU). Leia antes [POLITICA-DE-DADOS.md](POLITICA-DE-DADOS.md).

## Equivalências

| Quadro local `REA-COORD` | GitHub |
|---|---|
| `TASKLIST.md` (R00–R15) | Uma Issue por tarefa, com o template **Tarefa REA** |
| `claims\<ID>.json` (`File.Move` sem substituição) | **Assignee** da Issue + comentário `claim:` |
| `status\<ID>.md` | Corpo da Issue (seção Estado), atualizado só pelo titular |
| `journal\<ID>\` | Comentários da Issue, um por passo relevante |
| `evidence\<ID>\<tentativa>\` | PR com `tentativas/<ID>/<tentativa>/relatorio.md` (só texto); os dados brutos ficam na máquina |
| `locks\gpu-capture.json` | Continua local. A Issue fixada **Lock GPU** só espelha o titular |
| `CONFLITOS.md` | Label `conflito` + comentário na Issue das duas tarefas |
| `REA-INDICE.md` (só R00 edita) | `docs/indice.md`, editado só por PRs de R00 |

## 1. Pegar uma tarefa (claim)

1. Abra a Issue da tarefa. Se ela já tem assignee, **não pegue**. Um claim antigo não autoriza tomar o trabalho: só um repasse explícito do titular, ou um arquivamento confirmado pelo usuário ou por R00.
2. Atribua a Issue a você (assignee) e, no mesmo minuto, comente:

   ```
   claim: R07-Vera-01
   build: <exe> sha256 <hash>
   escopo: <uma frase>
   ```

3. Troque a label `estado:aberta` por `estado:em-andamento`.

**Disputa.** O GitHub não tem atribuição atômica como o `File.Move`. Se duas IAs pegarem a mesma Issue, vale o comentário `claim:` mais antigo. A outra remove o próprio assignee e comenta `claim retirado`.

**Uma conta para várias IAs.** Se todas as IAs usam a mesma conta do GitHub, o assignee só diz que a tarefa está ocupada. Quem é o titular fica no comentário `claim:` (nome da IA e tentativa).

## 2. Trabalhar

- Fique na área da label. Achou algo de outra área? Comente na Issue dela e não edite o trabalho dela.
- Registre os passos relevantes como comentários (o antigo `journal`).
- Mantenha a seção Estado do corpo da Issue com estado, progresso, bloqueio e próximo passo.
- Progresso: 0% claim · 25% artefatos conferidos · 50% primeira evidência interpretada · 75% análise ou captura concluída, verificação pendente · 100% conferido e reproduzível.

## 3. Uma PR por tentativa

- Branch: `r07/vera-01` (tarefa em minúsculas / nome-tentativa).
- Arquivo: `tentativas/R07/R07-Vera-01/relatorio.md`, a partir de [tentativas/_modelo/relatorio.md](tentativas/_modelo/relatorio.md). Pode juntar CSVs pequenos **de números agregados** e scripts próprios (`.py`, `.ps1`).
- O PR usa o template e cita a Issue com `Refs #<n>`. Use `Closes #<n>` só quando a tarefa chegar a 100%.
- Uma tentativa = uma ideia. Para outra hipótese, abra outra tentativa (`-02`).
- A checagem `Test-RepoContent` precisa passar.

## 4. Marcação de evidência

Toda afirmação com número leva uma destas marcas:

| Marca | Uso |
|---|---|
| `[obs-local]` | Medido ou conferido por você nesta máquina, nesta build (hash citado) |
| `[relatado]` | Vem de outro relatório, PR ou status. Cite a fonte |
| `[estimado]` | Cálculo, modelo ou inferência sem medição direta |

Evidência ausente se escreve **indisponível**. Não preencha com estimativa sem a marca.

## 5. Protocolo de resultados comparáveis

Todo número de desempenho informa:

- build: exe e hash (SHA-256 ou BLAKE3), e PDB GUID/age quando houver;
- cena e checkpoints (ex.: cutscene C1, primeira missão M1);
- perfil efetivo (ex.: Controle ou Candidato) e as variáveis que diferem;
- resolução, escala, preset gráfico e cache (frio ou quente);
- métricas: FPS renderizado, mediana, p95, % > 33,33 ms, travamentos, VRAM típica e pico;
- separação de tempos quando houver: preparação na CPU, espera, execução na GPU, readback, espera da CPU, leitura e publicação da fence.

## 6. GPU

A captura exige a GPU sozinha. A reserva continua sendo `locks\gpu-capture.json` na máquina, com o mesmo `File.Move` atômico, e só depois de confirmar que o teste anterior terminou ou que o usuário liberou. Depois de reservar, comente na Issue **Lock GPU** (`reservado: R04-Davi-01`) e ao liberar (`liberado`). A Issue não substitui o lock local.

## 7. Consolidação

Só a IA consolidadora (R00 ou quem o usuário designar) junta PRs numa build, roda o [teste automatizado](harness/README.md) e publica o score. Veja [docs/consolidacao.md](docs/consolidacao.md). Uma tentativa que mude o runtime pode rodar o mesmo teste e trazer o score no PR, citando o SHA-256 do `Vigiar-Rodada.ps1`.

Mudanças no próprio teste (launcher, vigia, pesos do score, patches) vão num PR separado, com a label `coordenacao`.
