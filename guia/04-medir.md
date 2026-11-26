# 4. Measuring

## The log's frame line

Every ~5 s the runtime writes an aggregate line to `stderr`, in this format:

```
<fps> fps, <ms> ms/frame (<x> preparing …; <y> on the GPU; <z> copying back <n> MB), <d> draws/frame[, dropped <k> without a host pipeline]
```

- **draws/frame separates the phases.** About 10 draws is a menu or a loading screen. Above 500–1,000 is a 3D scene (cutscene or world). The watcher uses 50 and 1,000 as thresholds.
- **A whole-run average misleads.** On candidate 1, the weighted total was 26.7 fps but the world ran at 1.15 fps [relatado, R04]. Always split by phase.
- **With `VICTORY_FRAME_LOG=1`** the per-frame time is logged too, which is needed for a real p95 and to attribute spikes.

## Useful counters

| Variable | What it adds to the log |
|---|---|
| `VICTORY_FRAME_LOG=1` | per-frame time, `PipelineWaitUs`, submissions per frame |
| `VICTORY_DSTORAGE_STATS=1` | requests per Submit, contiguity, latency, read/decode/destination time (patch 01) |
| `VICTORY_LOG=info` | own and shared VRAM, DXGI budget, live textures, effective floor |
| `diagnostics` build | black-frame detection (`a black frame after a frame that was not`) |

[Medir-Rodada.ps1](../harness/Medir-Rodada.ps1) summarizes all of this per run.

## Comparable protocol

Every number states:

- build (hash);
- scene and checkpoints;
- effective profile (the `VICTORY_*` in `.settings.txt`);
- resolution and console (`series-x`/`series-s`);
- cold or warm cache.

When comparing two configurations:

- change **one** variable at a time;
- alternate A/B/A/B rather than AAA/BBB;
- use the same save seed;
- report the median, p95, % of frames > 33.33 ms, hitches, and typical and peak VRAM.

## Exclusive GPU

One capture at a time. The reservation is the local file `locks\gpu-capture.json`, created with `[System.IO.File]::Move(temp, destination)`, which fails if the destination exists. Reserve only after confirming that no `victory` process is running or that the user has released the GPU. When done, move the lock to `locks\arquivo\`.

## External tools

- **PresentMon** needs administrator rights or membership in Performance Log Users. Without them it fails with "access denied".
- **RenderDoc/PIX** captures contain title assets. They stay on the machine and never go into the repository.
- **Image:** the comparison with the reference runs locally (`cutscene-lab/score.py`). Only the score comes out.
