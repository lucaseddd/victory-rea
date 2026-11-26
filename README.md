# VIctory REA · guia de engenharia reversa assistida e teste automatizado com score

Este repositório reúne três peças para levar um título de Xbox Series a 30 FPS renderizados, com imagem correta, no [VIctory](https://github.com/Marvisak/VIctory):

1. **Um guia de REA.** Como usar engenharia reversa assistida (fonte + PDB + PE, com Ghidra e `dumpbin`) para entender o runtime, medir e propor mudanças. → [guia/](guia/README.md)
2. **Um teste automatizado com score.** Um launcher e um vigia rodam o título, apertam Enter sozinhos até a primeira cena 3D, marcam os tempos e dão uma nota de 0 a 100 por progresso, velocidade, carregamento, shaders e imagem. → [harness/](harness/README.md)
3. **Coordenação de várias IAs em paralelo.** Uma Issue por tarefa, uma área por IA, um PR por tentativa, e uma IA mais forte que consolida, monta a build e roda o teste. → [CONTRIBUTING.md](CONTRIBUTING.md)

**Aqui só entra texto.** O jogo, os executáveis, os logs brutos e as capturas ficam na máquina local. Veja [POLITICA-DE-DADOS.md](POLITICA-DE-DADOS.md).

## Início rápido

Ler o guia: comece por [guia/README.md](guia/README.md) e pelo [mapa das áreas](guia/05-areas.md).

Rodar o teste (PowerShell como administrador, com um `victory.exe` compilado com os [patches](harness/patches/README.md)):

```powershell
Copy-Item .\harness\harness.example.toml .\harness\harness.toml
```

```powershell
.\harness\Iniciar-Rodada.ps1 -Config .\harness\harness.toml -Rapido -MapOnly
```

```powershell
.\harness\Iniciar-Rodada.ps1 -Config .\harness\harness.toml -Rapido -FecharAposJogavelS 120
```

Aperte F9 quando o jogo ficar jogável. O score sai em `<log>.score.md`, na pasta da rodada.

## Score

| Componente | Peso | Resumo |
|---|---|---|
| progresso | 30 | imagem (10) → primeira cena 3D (50) → jogável (100) |
| velocidade | 25 | FPS mediano no mundo ÷ 30 |
| carregamento | 20 | primeira cena 3D em 60 s = 100; em 20 min = 0 |
| shaders | 15 | % de draws não descartados por falta de pipeline |
| imagem | 10 | nota da comparação com uma gravação de referência local |

Detalhes, limitações e o que publicar: [harness/README.md](harness/README.md#score).

## Como as IAs trabalham

```
            Issues R00–R15 (uma por tarefa, label por área)
                               │
     ┌───────────┬─────────────┼─────────────┬─────────────┐
  readback   vram-mips   directstorage    present      shaders  …
  (IA A)      (IA B)        (IA C)        (IA D)        (IA E)
     │           │             │             │             │
     └── PR por tentativa: relatório em texto + números agregados ──┘
                               │
              consolidação periódica (IA mais forte)
     lê os PRs → monta candidata local → harness → score publicado
```

## Onde está cada coisa

| Caminho | Conteúdo |
|---|---|
| [guia/](guia/README.md) | Guia de REA no VIctory: ambiente, identidade da build, fonte → PDB → PE, medição, mapa das áreas, armadilhas |
| [harness/](harness/README.md) | Teste automatizado: launcher, vigia com score, extrator de log, exemplo de configuração |
| [harness/patches/](harness/patches/README.md) | Diffs de runtime de que o teste depende (`VICTORY_KEYS_FILE`, `VICTORY_TEXTURE_FLOOR_MB`, `VICTORY_DSTORAGE_STATS`, planos do Series S) |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Protocolo: Issue, assignee, PR por tentativa, marcação das evidências |
| [docs/consolidacao.md](docs/consolidacao.md) | Ciclo da IA consolidadora |
| [MAPEAMENTO-REA-COORD.md](MAPEAMENTO-REA-COORD.md) | Proposta de como o quadro local `REA-COORD` vira Issues |
| [tentativas/](tentativas/README.md) | Relatórios das tentativas, por tarefa |
| [POLITICA-DE-DADOS.md](POLITICA-DE-DADOS.md) | O que pode e o que não pode entrar |
| `.github/` | Templates de Issue e PR, labels e a checagem automática |

## Antes de cada commit

```powershell
powershell -File scripts\Test-RepoContent.ps1
```

O mesmo script roda no GitHub Actions em todo push e PR e recusa binários, `.exe`, `.dll`, `.pdb`, `.rpf`, imagens, vídeos, `*.stderr`, arquivos acima de 512 KiB, listagens de disassembly e dados pessoais.

## Licença

Os diffs em `harness/patches/` derivam do VIctory e do fork, que são GPL-3.0, e seguem essa licença.
