# VIctory REA — Coordinated Reverse Engineering, Automated Tests, and Scoring

Coordinate reverse engineering (REA) on [VIctory](https://github.com/Marvisak/VIctory), test candidate builds automatically, and use a 0–100 score and a scoreboard to see how each build compares with the last. The target is 30 rendered FPS with correct 3D output.

1. **Coordinate investigations.** Assign one Issue per task, give each AI investigator a defined area, and submit one PR per attempt. A coordinator reviews evidence and selects changes for a candidate build. → [Contribution workflow](CONTRIBUTING.md)
2. **Investigate and verify.** Follow the REA guide to map behavior from source, PDB, and PE, record reproducible evidence, and propose changes. → [REA guide](guide/README.md)
3. **Test and score each candidate.** The harness builds and versions the candidate, pre-warms the file cache when prior read lists are available, drives the menus, and measures and samples a 3D scene unattended. It records progress, speed, loading, stability, shaders, and image in the scoreboard, and checks comparable runs for regressions. → [Test harness](harness/README.md)

**Only text goes in here.** The game, executables, raw logs and captures stay on the local machine. See [DATA-POLICY.md](DATA-POLICY.md) (data policy).

## Quick start

Read the guide: start with [guide/README.md](guide/README.md) and the [area map](guide/05-areas.md).

Run the pipeline in PowerShell as administrator, on a VIctory source tree with the [patches](harness/patches/README.md) applied, after the [one-time setup](harness/README.md#one-time-setup):

```powershell
Copy-Item .\harness\harness.example.toml .\harness\harness.toml
```

```powershell
.\harness\Pipeline.ps1 -Source 'D:\victory\cand4' -Name 'my-change' -Notes 'what changed'
```

Nothing to press: the run ends by itself. The score goes to `<work_dir>\runs\<run>.score.md`, and the history goes to `<work_dir>\scoreboard.md`.

## Score

| Component | Weight | Summary |
|---|---|---|
| progress (`progress`) | 25 | image (10) → Enter accepted (30) → first 3D scene (50) → 3D scene measured without losing the GPU (100) |
| speed (`speed`) | 20 | median FPS in play ÷ 30 |
| loading (`loading`) | 20 | first 3D scene within 60 s = 100; at 20 min = 0 |
| stability (`stability`) | 15 | 100 minus penalties for drop windows and hitches > 1 s; 0 if the GPU is lost |
| shaders | 10 | % of draws not dropped for lack of a pipeline |
| image (`image`) | 10 | share of captured 3D frames with mean brightness at least 8/255 |

The regression check compares warm-cache runs of the same profile. It flags slowdowns in the 3D scene, a lower image score, reduced progress, and stability regressions when they cross the configured thresholds. Details, limitations and what to publish: [harness/README.md](harness/README.md#score-0100).

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
   reads the PRs → build → run → score → drop check → scoreboard
```

## Where things are

| Path | Contents |
|---|---|
| [guide/](guide/README.md) | REA guide for VIctory: environment, build identity, source → PDB → PE, measuring, area map, pitfalls, the automated pipeline |
| [harness/](harness/README.md) | Automated pipeline: build a version, run it unattended, score it, check for FPS drops, scoreboard |
| [harness/patches/](harness/patches/README.md) | Runtime diffs the test depends on (`VICTORY_KEYS_FILE`, `VICTORY_TEXTURE_FLOOR_MB`, `VICTORY_DSTORAGE_STATS`, Series S planes) |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Protocol: Issue, assignee, one PR per attempt, evidence tags |
| [docs/consolidation.md](docs/consolidation.md) | The consolidating AI's cycle |
| [REA-COORD-MAPPING.md](REA-COORD-MAPPING.md) | Proposed mapping from the local `REA-COORD` board to Issues |
| [attempts/](attempts/README.md) | Attempt reports, per task |
| [DATA-POLICY.md](DATA-POLICY.md) | What may and may not go in |
| `.github/` | Issue and PR templates, labels and the automated check |

## Before every commit

```powershell
powershell -File scripts\Test-RepoContent.ps1
```

The same script runs on GitHub Actions for every push and PR. It rejects binaries, `.exe`, `.dll`, `.pdb`, `.rpf`, images, videos, `*.stderr`, files over 512 KiB, disassembly listings and personal data.

## Note on names

All file names, parameters, score keys, folders and manifest fields are in English. The local board's folder names (`arquivo`, `claims`, `locks`) are kept only where they name real folders on the author's machine.

## License

The diffs in `harness/patches/` derive from VIctory and its fork, which are GPL-3.0, and are under that license.
