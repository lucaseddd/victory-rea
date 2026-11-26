# Mapeamento de REA-COORD para Issues (proposta)

Proposta apenas. **Nada foi criado no GitHub.** Os estados abaixo são os dos `status\*.md` locais lidos em 2026-11-26, por volta das 07:48 (-03:00), e mudam depressa. Antes de criar as Issues, releia o quadro local.

## Ordem de criação

Criando na ordem abaixo num repositório vazio, a Issue #1 fica sendo R00 e a #16, R15. Assim o número da Issue é o número da tarefa mais 1. A #17 é o **Lock GPU** (fixada).

## Tarefas R00–R15

| Issue | Tarefa | Labels | Estado local → label | Progresso | Titular (comentário `claim:`) | Dependências |
|---|---|---|---|---|---|---|
| #1 | R00 · Coordenação e índice | `coordenacao` `P0` | em andamento (ciclo 1 fechado) → `estado:em-andamento` | 100% do ciclo 1 | `R00-Lia-01` | — |
| #2 | R01 · Submissão e início do próximo quadro | `submissao` `P0` | concluída → fechada | 100% | `R01-Caio-01` | — |
| #3 | R02 · Readback e publicação da fence | `readback` `P0` | concluída → fechada | 100% | `R02-Beto-01` | — |
| #4 | R03 · Instrumentação e captura curta | `instrumentacao` `P0` `precisa-gpu` | bloqueada → `estado:bloqueada` | 75% | `R03-Nina-01` | R01, R02, lock GPU |
| #5 | R04 · Baseline e regressão visual | `baseline` `image-regression` `P0` `precisa-gpu` | bloqueada (precisa de PowerShell elevado) → `estado:bloqueada` | 50% | `R04-Davi-01` (está com o lock GPU) | R03, lock GPU |
| #6 | R05 · Comparação isolada da fila COPY | `readback` `P0` `precisa-gpu` | bloqueada → `estado:bloqueada` | 50% | `R05-Teo-01` | R03, R04, lock GPU |
| #7 | R06 · Execução gráfica e compute | `gpu-exec` `P1` | em andamento → `estado:em-andamento` | 50% | `R06-Iris-01` | R03 para atribuir tempo |
| #8 | R07 · VRAM, residência e mipmaps | `vram-mips` `P1` | concluída → fechada | 100% | `R07-Vera-01` | — |
| #9 | R08 · Worker de texturas | `texturas` `P1` `precisa-gpu` | bloqueada → `estado:bloqueada` | 75% | `R08-Ciro-01` | R05 |
| #10 | R09 · DirectStorage e streaming no HD | `directstorage` `P1` `precisa-gpu` | bloqueada → `estado:bloqueada` | 75% | `R09-Teo-01` | lock GPU |
| #11 | R10 · Threads, esperas e sincronização guest/host | `threads-sync` `P1` | concluída → fechada | 100% | `R10-Gael-01` | R01, R02 |
| #12 | R11 · Shaders, PSOs e cache | `shaders` `P1` `precisa-gpu` | bloqueada → `estado:bloqueada` | 75% | `R11-Mila-01` | lock GPU, elevação |
| #13 | R12 · Present, pacing e quadros renderizados | `present` `P1` | em revisão → `estado:em-revisao` | 75% | `R12-Rui-01` | — |
| #14 | R13 · Isolar regressões de imagem | `image-regression` `P2` `precisa-gpu` | correção compilada, verificação pendente → `estado:em-revisao` | 75% | `R13-Otto-01` | R04/R05, lock GPU |
| #15 | R14 · Otimizar o maior bloqueio medido | `otimizacao` `P2` | sem claim → `estado:aberta` | 0% | — | R03–R05 + relatório da área |
| #16 | R15 · Validar a candidata final | `validacao` `P2` | sem claim → `estado:aberta` | 0% | — | R14 ou baseline que atinja a meta |
| #17 | Lock GPU (fixada) | `precisa-gpu` | espelho de `locks\gpu-capture.json` | — | último comentário `reservado:`/`liberado` | — |

Observação: R05 e R09 aparecem com o mesmo nome de IA (Teo) em sessões diferentes. Na Issue, o que identifica o titular é a tentativa (`R05-Teo-01`, `R09-Teo-01`).

## Demais itens do quadro

| Local | Proposta |
|---|---|
| `TASKLIST.md` | Vira as Issues #1–#16. As regras do quadro já estão em `CONTRIBUTING.md` |
| `status\R??.md` | Resumo de uma linha no campo **Estado** da Issue: estado, progresso, bloqueio, próximo passo |
| `journal\R??\` | Não migrar o histórico. Daqui em diante, um comentário por passo relevante |
| `evidence\R??\<tentativa>\` | **Fica local.** Cada tentativa vira um PR com `tentativas/R??/<tentativa>/relatorio.md`, reescrito só com hashes, offsets/RVAs, nomes de símbolos do VIctory e números agregados |
| `claims\R??.json` | Assignee + comentário `claim: <tentativa>` |
| `claims\arquivo\` (OCUP-01, OCUP-02) | Não viram Issues. Um comentário na #1 registra que foram encerradas às 07:30 |
| `CONFLITOS.md` | Já resolvido. Um comentário na #1 com o resumo; daqui em diante, label `conflito` |
| `locks\gpu-capture.json` | Continua local e atômico. A #17 só espelha |
| `REA-INDICE.md` | `docs/indice.md`, editado só por PRs de R00 |

## Cuidados na migração das tentativas já feitas

- Os relatórios locais de R00, R08 e outras tarefas citam saídas de `dumpbin /disasm` e do Ghidra. No PR entram só o endereço e o nome do símbolo, nunca as linhas de instrução.
- Os CSVs de amostras de log precisam ser conferidos antes de entrar: só colunas numéricas agregadas, sem linhas copiadas do log bruto.
- O status de R13 cita uma gravação de vídeo numa pasta do perfil do usuário. No PR, escreva "gravação local da cutscene" e informe só os números.
- Não migre IDs de sessão das IAs: o nome da tentativa basta.
- Rode `scripts/Test-RepoContent.ps1` antes de cada PR.
