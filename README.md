# VIctory REA: reverse-engineering guide and automated scored test

This repository brings together three pieces for running an Xbox Series title at 30 rendered FPS, with a correct image, on [VIctory](https://github.com/Marvisak/VIctory):

1. **A REA guide.** How to use assisted reverse engineering (source + PDB + PE, with Ghidra and `dumpbin`) to understand the runtime, measure it and propose changes. → [guide/](guide/README.md)
2. **An automated test with a score.** A pipeline (build → version → run → score → FPS-drop check → scoreboard) runs with no key presses. It compiles a version, runs the title, presses Enter through the menus, pre-warms the disk from earlier runs, detects the first 3D scene, measures it for a fixed time, captures world frames and closes the game. Each run gets a 0–100 score for progress, speed, loading, stability, shaders and image, and is compared with the previous version to flag FPS regressions. → [harness/](harness/README.md)
3. **Coordination of several AIs in parallel.** One Issue per task, one area per AI, one PR per attempt, and a stronger AI that consolidates, builds a candidate and runs the test. → [CONTRIBUTING.md](CONTRIBUTING.md)

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
| image (`image`) | 10 | score from comparing against a local reference recording |

The FPS-drop check flags a REGRESSION (exit code 1) when a new version loses more than 10% FPS, gets 15% worse at p95, or adds drops, hitches or a lost GPU. Details, limitations and what to publish: [harness/README.md](harness/README.md#score-0100).

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
