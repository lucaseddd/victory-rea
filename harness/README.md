# Automated pipeline with a score

**build → version → run → score → FPS-drop check → scoreboard**, with no key presses.

The pipeline:

1. compiles the source;
2. gives it a version number;
3. pre-warms the disk from earlier runs' read lists, so the game's scattered reads hit a warm file cache;
4. runs the title unattended and presses Enter in the menus;
5. detects the first 3D scene, measures it for a fixed time, and captures 1 world frame in 64;
6. closes the game and computes the score;
7. compares the run with the previous version and flags FPS drops;
8. updates the scoreboard.

Everything runs on your machine. Only numbers (from `*.score.md`, the comparison and `scoreboard.md`) come back to the repository.

| Script | Role |
|---|---|
| [Build-Version.ps1](Build-Version.ps1) ("build version") | Release build (diagnostics + Agility exports), runs the `victory-gpu` and `victory-hle` tests, and creates `versions\vNNN-<name>-<sha8>\` with the exe, pdb, `D3D12\` and `manifest.json` |
| [Run-Version.ps1](Run-Version.ps1) ("run version") | Deploys the version to the fixed `runtime\` path and checks its hash. Then: restores `data\` from `seed-data\`, uses the shared cache, runs the title, calls the watcher, compares the result and updates the scoreboard |
| [Watch-Run.ps1](Watch-Run.ps1) ("watch run") | Follows the log, drives the menus, records milestones, closes the game and computes the score |
| [Compare-Runs.ps1](Compare-Runs.ps1) ("compare runs") | **FPS-drop checker** between two runs. Exit code 1 on regression |
| [Pipeline.ps1](Pipeline.ps1) | Build + run in one call |
| [Measure-Run.ps1](Measure-Run.ps1) ("measure run") | Extra extractor: summarizes `.stderr` logs (world, VRAM, mipmaps, COPY queue, worker, DirectStorage, black frames) |
| [Common.ps1](Common.ps1) | Shared helpers: reads `harness.toml`, refuses a `work_dir` inside the repository, checks firewall rules |
| [harness.example.toml](harness.example.toml) | Configuration template. Copy it to `harness.toml`, which Git ignores |
| [patches/](patches/README.md) | Runtime diffs the pipeline depends on |

**Origin.** These scripts are the local `victory-pipeline` of 2026-11-26, translated to English. Machine paths moved to `harness.toml`, firewall rules are found by program instead of by name, and `score.json` stores only the log's file name. Parameter names, score keys, manifest and scoreboard columns, and work-folder names stay in Portuguese, so existing versions and scoreboards remain compatible. The tables below explain each one.

## One-time setup

1. **Configuration.** Copy `harness.example.toml` to `harness.toml` and set:
   - `work_dir`: a folder outside the repository;
   - `title_exe`: the title's executable, from your own console's dump;
   - `agility_bin`: the Agility SDK 1.620.2 binaries;
   - `vcvars`: optional;
   - `rust_toolchain`.
2. **Starting save.** Put it in `<work_dir>\seed-data\`. Every run starts from a copy of it.
3. **VIctory source with the patches.** The source you build must have the [patches](patches/README.md) applied: `VICTORY_KEYS_FILE` drives the menus; patch 03 makes Series S show an image.
4. **Firewall.** One blocking outbound rule for the fixed runtime path and one for the title. The runtime always runs from `<work_dir>\runtime\victory.exe`, so **one rule covers every version**. In PowerShell **as administrator**:

   ```powershell
   New-NetFirewallRule -DisplayName 'VIctory pipeline runtime offline' -Direction Outbound -Action Block -Profile Any -Program '<work_dir>\runtime\victory.exe'
   ```

   ```powershell
   New-NetFirewallRule -DisplayName 'VIctory title offline' -Direction Outbound -Action Block -Profile Any -Program '<path to the title executable>'
   ```

The run step checks both rules before every run and refuses to run without them. That is why it must run in PowerShell **as administrator**: Windows does not let a normal shell read the rules.

## Usage

Build a version from a source tree and run everything:

```powershell
.\harness\Pipeline.ps1 -Source 'D:\victory\cand4' -Name 'my-change' -Notes 'what changed'
```

Run an already-built version again:

```powershell
.\harness\Run-Version.ps1 -Version v001-cand4-series-s-2ffd8cb5
```

Try a setting without rebuilding (`latest` = latest version):

```powershell
.\harness\Run-Version.ps1 -Version latest -Extra @{ VICTORY_QUEUE2 = '1' }
```

Check the mapping without running the title:

```powershell
.\harness\Run-Version.ps1 -Version latest -MapOnly
```

Compare any two runs:

```powershell
.\harness\Compare-Runs.ps1 -Current <new>.score.json -Previous <old>.score.json
```

### Parameters

| Script | Parameter | Meaning |
|---|---|---|
| all | `-Config` | `harness.toml` (default: next to the scripts) |
| Build-Version, Pipeline | `-Source` | VIctory source folder (with `Cargo.toml`) |
| | `-Name` | short label: lower case, digits, hyphens |
| | `-Notes` | what this version changes |
| | `-Base` | base commit (default: the source's `.victory-base` file) |
| | `-SkipTests` | skip the tests |
| Run-Version, Pipeline | `-Version` | version id, or `latest` (latest) |
| | `-Mode quick\|series-x` | `quick` (quick) = `--console series-s` + `VICTORY_DISPLAY_MODE=1280x720`; `series-x` = reference |
| | `-Extra @{...}` | extra `VICTORY_*` settings |
| Run-Version | `-DiskWorkers N` | `VICTORY_DSTORAGE_WORKERS` (patch 05) |
| | `-MeasureSceneS` | seconds of 3D scene measured before closing (240) |
| | `-MaxMinutes` | hard time limit (45) |
| | `-NoProgressMin` | close after this many minutes without a new milestone (12) |
| | `-MapOnly` | map without running |
| Compare-Runs | `-Current`, `-Previous` | new and reference `score.json` |
| | `-FpsDropPct`, `-P95WorsePct`, `-DropPoints`, `-ExtraHitches` | regression thresholds (10%, 15%, 5 points, 1) |

## What the watcher does

- **Automatic Enter** in the menus, only on light screens (up to 50 draws per frame) and before the 3D scene.
- **Enter accepted:** recorded when the screen changes (the draw count) 3–15 s after an Enter.
- **First 3D scene:** the first frame with more than 1,000 draws.
- **Autosave:** written early in the 3D scene, so it is only a milestone. The test does not end there.
- **End:** closes the game after the measured scene time, at 45 min, or after 12 min without a new milestone.
- **Outputs:**
  - `.milestones.log` (milestones);
  - `.samples.csv` (samples);
  - `.score.json`;
  - `.score.md`.

## Score (0–100)

| Component (key) | Weight | Computation |
|---|---|---|
| progress (`progress`) | 25 | 10 = image; 30 = Enter accepted; 50 = first 3D scene; 100 = 3D scene measured without losing the GPU |
| speed (`speed`) | 20 | median FPS in play (or in the cutscene, if play was not reached) ÷ 30 |
| loading (`loading`) | 20 | 100 with the first 3D scene at 60 s; 0 at 20 min; linear in between |
| stability (`stability`) | 15 | 100 − 2 per % of world windows with a drop (> 2× the median) − 5 per hitch > 1 s; 0 if the GPU is lost |
| shaders (`shaders`) | 10 | % of world draws not dropped for lack of a pipeline |
| image (`image`) | 10 | `cutscene-lab/score.py` score against a local reference recording, optional |

- **Total:** weighted average of the components that have data. A component without data drops out of the average; it does not count as zero.
- **Weights and limits:** conventions of this test, set in the scripts. If you change them, say so in the PR and cite the SHA-256 of `Watch-Run.ps1`, because scores from different watcher versions are not comparable.

## FPS-drop check

`Compare-Runs.ps1` flags a **REGRESSION** (exit code 1) if, against the previous version:

- median world FPS drops more than 10%;
- world p95 ms/frame gets more than 15% worse;
- windows with a drop (> 2× the median) rise more than 5 percentage points;
- there is more than 1 extra hitch > 1 s;
- the GPU is lost;
- the run gets less far (progress).

`Run-Version.ps1` runs the check automatically against the previous warm-cache run of the same profile. It writes the findings to `<run>.comparison.txt` and the verdict to the scoreboard. Cold-cache runs are scored but not compared.

## Outputs (in `work_dir`)

- `versions\<id>\manifest.json`: the version. It holds local paths (`source`, `build_log`), so do not paste it as-is.
- `runs\<id>-<profile>-<date>.*`: log, settings, milestones, samples, score and comparison.
- `scoreboard.csv` and `scoreboard.md` ("scoreboard"): every run, with the drop-check verdict.

### What to publish

- **Goes into the PR:**
  - from `.score.md`: total, components, milestones in seconds, FPS medians and p95, drops and hitches, shader counts;
  - the comparison findings;
  - the scoreboard rows for the versions involved.
- **Stays on the machine:** `.stderr`, `.stdout`, `.settings.txt`, `.milestones.log`, `.samples.csv`, the key file, manifests and the whole `work_dir`.

## Verified and not verified

- **Verified without opening the game:**
  - all scripts parse;
  - in the original pipeline, `Build-Version` produced `v001` with the same hash as candidate 4 (a reproducible build), with 213 + 108 tests passing and the old depth-bounds failure [reported];
  - this English copy of the watcher and the checker ran against a fake process and a synthetic log in the runtime's format. The score was produced, and a regression was flagged with exit code 1 (FPS −28.6%, p95 +1,400%, drops 0 → 30%, 3 hitches) [observed].
- **Not verified:**
  - a full `Run-Version` run, because reading the firewall rules requires administrator rights;
  - Enter and the save inside the real game;
  - the real duration of each phase.
