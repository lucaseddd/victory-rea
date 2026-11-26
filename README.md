# VIctory REA: reverse-engineering guide and automated scored test

This repository brings together three pieces for running an Xbox Series title at 30 rendered FPS, with a correct image, on [VIctory](https://github.com/Marvisak/VIctory):

1. **A REA guide.** How to use assisted reverse engineering (source + PDB + PE, with Ghidra and `dumpbin`) to understand the runtime, measure it and propose changes. → [guia/](guia/README.md)
2. **An automated test with a score.** A launcher and a watcher run the title, press Enter on their own until the first 3D scene, record timestamps and give a 0–100 score for progress, speed, loading, shaders and image. → [harness/](harness/README.md)
3. **Coordination of several AIs in parallel.** One Issue per task, one area per AI, one PR per attempt, and a stronger AI that consolidates, builds a candidate and runs the test. → [CONTRIBUTING.md](CONTRIBUTING.md)

**Only text goes in here.** The game, executables, raw logs and captures stay on the local machine. See [POLITICA-DE-DADOS.md](POLITICA-DE-DADOS.md) (data policy).

## Quick start

Read the guide: start with [guia/README.md](guia/README.md) and the [area map](guia/05-areas.md).

Run the test (PowerShell as administrator, with a `victory.exe` built with the [patches](harness/patches/README.md)):

```powershell
Copy-Item .\harness\harness.example.toml .\harness\harness.toml
```

```powershell
.\harness\Iniciar-Rodada.ps1 -Config .\harness\harness.toml -Rapido -MapOnly
```

```powershell
.\harness\Iniciar-Rodada.ps1 -Config .\harness\harness.toml -Rapido -FecharAposJogavelS 120
```

Press F9 when the game becomes playable. The score is written to `<log>.score.md` in the run folder.

## Score

| Component | Weight | Summary |
|---|---|---|
| progresso (progress) | 30 | image (10) → first 3D scene (50) → playable (100) |
| velocidade (speed) | 25 | median in-world FPS ÷ 30 |
| carregamento (loading) | 20 | first 3D scene within 60 s = 100; at 20 min = 0 |
| shaders | 15 | % of draws not dropped for lack of a pipeline |
| imagem (image) | 10 | score from comparing against a local reference recording |

Details, limitations and what to publish: [harness/README.md](harness/README.md#score).

## How the AIs work

```
            Issues R00–R15 (one per task, one area label each)
                               │
     ┌───────────┬─────────────┼─────────────┬─────────────┐
  readback   vram-mips   directstorage    present      shaders  …
  (AI A)      (AI B)        (AI C)        (AI D)        (AI E)
     │           │             │             │             │
     └──── one PR per attempt: text report + aggregate numbers ───┘
                               │
              periodic consolidation (stronger AI)
   reads the PRs → builds a local candidate → harness → publishes score
```

## Where things are

| Path | Contents |
|---|---|
| [guia/](guia/README.md) | REA guide for VIctory: environment, build identity, source → PDB → PE, measuring, area map, pitfalls |
| [harness/](harness/README.md) | Automated test: launcher, watcher with score, log extractor, example configuration |
| [harness/patches/](harness/patches/README.md) | Runtime diffs the test depends on (`VICTORY_KEYS_FILE`, `VICTORY_TEXTURE_FLOOR_MB`, `VICTORY_DSTORAGE_STATS`, Series S planes) |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Protocol: Issue, assignee, one PR per attempt, evidence tags |
| [docs/consolidacao.md](docs/consolidacao.md) | The consolidating AI's cycle |
| [MAPEAMENTO-REA-COORD.md](MAPEAMENTO-REA-COORD.md) | Proposed mapping from the local `REA-COORD` board to Issues |
| [tentativas/](tentativas/README.md) | Attempt reports, per task |
| [POLITICA-DE-DADOS.md](POLITICA-DE-DADOS.md) | What may and may not go in |
| `.github/` | Issue and PR templates, labels and the automated check |

## Before every commit

```powershell
powershell -File scripts\Test-RepoContent.ps1
```

The same script runs on GitHub Actions for every push and PR. It rejects binaries, `.exe`, `.dll`, `.pdb`, `.rpf`, images, videos, `*.stderr`, files over 512 KiB, disassembly listings and personal data.

## Note on names

File names and the scripts' parameters (`-Rapido`, `-FecharAposJogavelS`, …) and score keys (`progresso`, `velocidade`, …) are in Portuguese, the language the project started in. They are kept as-is for compatibility with existing runs. Each one is explained in English where it is used.

## License

The diffs in `harness/patches/` derive from VIctory and its fork, which are GPL-3.0, and are under that license.
