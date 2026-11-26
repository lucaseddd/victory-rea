# 7. The automated pipeline

The REA cycle ends in a number. Every change, from a one-line patch to a new candidate, goes through the same pipeline, so results stay comparable across AIs and over time.

```
 source + patches
       │
       ▼
 ┌────────────┐   versions\vNNN-<name>-<sha8>\  (exe, pdb, D3D12\, manifest.json)
 │   build    │── release + diagnostics + Agility exports, victory-gpu / victory-hle tests
 └────────────┘
       │
       ▼
 ┌────────────┐   runtime\victory.exe (fixed path, one firewall rule), seed save, shared cache
 │    run     │── title runs offline, the watcher presses Enter until the first 3D scene
 └────────────┘
       │
       ▼
 ┌────────────┐   milestones: first frame → Enter accepted → first 3D scene → 3D scene measured
 │   score    │── progress 25 · speed 20 · loading 20 · stability 15 · shaders 10 · image 10
 └────────────┘
       │
       ▼
 ┌────────────┐   vs the previous warm-cache run of the same profile
 │ drop check │── REGRESSION (exit 1) on FPS −10%, p95 +15%, +5 pts drop windows, extra hitches, lost GPU, less progress
 └────────────┘
       │
       ▼
 ┌────────────┐
 │ scoreboard │── scoreboard.csv / scoreboard.md: every version, score and verdict
 └────────────┘
```

## Steps in practice

1. **Build** with `Build-Version.ps1 -Source <source> -Name <label> -Notes <what changed>`. The version id carries the first 8 hex digits of the exe's SHA-256, and the manifest keeps the full hashes, the shader-translator hash and the test results.
2. **Run** with `Run-Version.ps1 -Version <id>`. Nobody needs to touch the keyboard. Before the game opens, the pipeline pre-warms the disk from the read lists of the last two runs. The run ends by itself after 240 s of measured 3D scene, after 12 min without progress, or at 45 min.
3. **Score.** The watcher writes `.score.json` and `.score.md`. A component without data drops out of the average.
4. **Drop check.** It runs automatically when there is a previous warm-cache run of the same profile. You can also run `Compare-Runs.ps1` by hand on any two runs.
5. **Scoreboard.** `scoreboard.md` lists every run. That table, not a single run, is the history of the project.

`Pipeline.ps1` does steps 1–5 in one call.

## How the pipeline fits REA

- **One variable per version.** To attribute a gain to a change, build one version per change (R14). Use `-Extra @{ VICTORY_X = '1' }` to try a runtime setting without rebuilding.
- **Warm cache for comparisons.** The first run of a new shader translator fills the cache; compare the second one. The scoreboard marks cold runs as "not compared".
- **A regression is a finding.** If the check returns REGRESSION, open or update the area's Issue with the comparison findings and the two version ids.
- **Score and analysis go together.** The PR of an attempt carries the score and the REA explanation (symbols, RVAs, counters) of why it moved.
- **Same profile, same machine.** Scores from different machines or profiles (`quick` vs `series-x`) are not comparable.

Setup, parameters and outputs: [harness/README.md](../harness/README.md).
