# R27 · Best build so far on a 6 GB RTX 3060 Laptop · attempt R27-Atual-01

- **Issue:** (to be linked) · **Area:** performance, stability
- **Build:** `victory.exe` sha256 `928CCEC71FCC4671CA8517F25E3784871837BF123E780A86E2F1EB0427570E91` · PDB sha256 `05680CBB1A3A8EF4CFBF488444817ACBC659CDCCBAAABCB4D738E208CD0A1323`
- **Base:** VI-BR-PORT `2954325320735fa8b56a15e7f3e9654965e3462e` plus the changes in [source-changes.md](source-changes.md)
- **Scene and checkpoints:** boot → menus → world (3D, > 1000 draws/frame)
- **Effective profile:** `Fluidez` (Series S) · full variable list below
- **Resolution, scale, graphics, cache:** 1280x720, the title's own upscaler (`VICTORY_UPSCALER=6`), no DLSS, no frame generation · **warm** pipeline cache
- **Hardware:** RTX 3060 Laptop 6 GB, 32 GB RAM, Windows 10 22H2, NVIDIA driver 591.59
- **Progress:** 75% (reaches the world reliably with a warm cache; frame rate still low)

## One-line result

With a warm pipeline cache this build reaches the 3D world every time and stays there (34 min in one session), rendering far more of the scene than earlier builds at the same frame rate; every crash we saw came from a **cold** cache, not from a specific shader.

## Findings

1. **The crashes are cold-cache crashes.** [observed] Two `DXGI_ERROR_DEVICE_REMOVED` (0x887A0005) closes, one on this build and one on its successor, both happened while the host pipeline library was empty and dozens of compute pipelines were being created at 8–14 s each on parallel workers. In both, nothing of ours was running on the card and the DRED breadcrumbs were empty. The pipeline being created at that moment is not evidence against that shader: during a cold start there is *always* one being created for several seconds (84 made in 4 minutes, 41 over 1 s, up to 12.7 s).
2. **The same build with a warm cache does not crash.** [observed] Library mapped at start (351–505 MB, zero pipelines created), 34 min in one session and 15 min in another, both in 3D.
3. **`VICTORY_THREAD_TICKET` is not the cause.** [observed] This build has no thread ticket and crashed the same way on a cold cache. Changing a translation switch changes the shader cache key, so testing it means paying another cold start.
4. **One driver reset (TDR) during a session came from another process.** [observed] `LiveKernelEvent 141` parameter 5 is the PID of the context that timed out: once it was the VIctory process, once a different process. A GPU miner or other GPU load running at the same time can take the game down with it.
5. **The 1 fps drops are memory traffic, not the GPU and not shader translation.** [observed, see table] In the slow samples the GPU time is unchanged (29 vs 34 ms) while title buffer copies go from 26 ms / 46 MB to 441 ms / 123 MB per frame. The worst frame (a streaming burst) took 10.5 s: 5.0 s copying 877 MB in 634 copies and 10.6 s recording 142 k list calls. Draws dropped in those frames are the ray-tracing structure builder (`VICTORY_BVH_BUILDER=0`, off on purpose), not missing pipelines.
6. **A fork that adds DLSS crashes at title init on this machine regardless of DLSS.** [observed] DLSS Super Resolution loads and is reported supported on the RTX 3060 (NVIDIA-signed Streamline 2.14.16); DLSS frame generation is refused (RTX 40 only), which is only a warning. The title calls its own crash handler about 15 s after start at "Game Init", frame 0, before any DLSS dispatch, with both the Series X / 1440p and the Series S / DLSS off profiles.

## Metrics

Aggregates from the runtime's 5-second frame lines, 3D samples only (> 1000 draws/frame). Full table: [aggregates.csv](aggregates.csv).

| Metric | Session 1 (34 min) | Session 2 (15 min) | Tag |
|---|---|---|---|
| Rendered FPS, median / p10 | 3.5 / 0.4 | 4.8 / 0.7 | observed |
| Median ms / p95 ms | 283 / 5838 | 206 / 1673 | observed |
| % > 33.33 ms | 100 | 100 | observed |
| Samples under 3 fps (hitches) | 39% | 32% | observed |
| Draws/frame, median | 3653 | 4336 | observed |
| Title buffer copies ms, median / max | 21 / 6093 | 25 / 5020 | observed |
| GPU wait ms, median | 57 | 30 | observed |
| DXGI budget MB | 4701 | 4433 | observed |
| Score (harness) | unavailable | unavailable | |

Slow vs normal samples (session 2):

| | ≥ 5 fps | < 3 fps |
|---|---|---|
| ms/frame | 164 | 2058 |
| Title buffer copies | 26 ms / 46 MB | 441 ms / 123 MB |
| GPU | 34 ms | 29 ms |
| Copying back | 53 ms | 53 ms |

## How to reproduce

1. Build the base commit with [source-changes.md](source-changes.md) applied (`cargo build --release`), with the D3D12 Agility SDK 1.620 next to `victory.exe`.
2. Run with the console profile **Series S** and these variables (the `Fluidez` profile):

```
VICTORY_MUTE=1
VICTORY_KBM_GTA=1
VICTORY_DISPLAY_MODE=1280x720
VICTORY_LOG=info
VICTORY_FRAME_LOG=1
VICTORY_D3D12_DRED=light
VICTORY_UPSCALER=6
VICTORY_RT_MISS=1
VICTORY_BVH_BUILDER=0
VICTORY_MEMORY_CARD_MB=512
VICTORY_CARD_BUFFERS_MB=512
VICTORY_CARD_BUFFERS_MIN_KB=64
VICTORY_DYNAMIC_SLOTS=327680
VICTORY_TILES_SMALL_WHEN_FULL_MB=512
VICTORY_CARD_ROOM_FOR_TARGETS_MB=1536
VICTORY_TEXTURE_SPARE_BLOCKS=4
VICTORY_RIPE_BLOCKS=4
VICTORY_LATE_WAIT_LISTS=128
VICTORY_LEVELS_ON_DEMAND=1
VICTORY_LEVELS_MIN_KB=64
VICTORY_PIPELINE_BOOK=1
VICTORY_PIPELINE_COMPUTE_WAIT=1
VICTORY_NO_WATCHDOG=1
VICTORY_TEXTURE_NO_WAIT=0
VICTORY_RELAY=2
VICTORY_WIDE_BACK=1
VICTORY_CARD_REHASH_RUNS=1
VICTORY_JOIN_COPIES=1
VICTORY_INDIRECT_WINDOW=1
VICTORY_RELAY_COPY=1
VICTORY_CARD_STEPS=2
VICTORY_INDIRECT_BATCH=2
VICTORY_MAP_THREADS=1
VICTORY_TITLE_PRIORITIES=0
VICTORY_CARD_AWAKE=0
VICTORY_SHOW_AFTER=1
VICTORY_PORT_CONSTANTS=0
VICTORY_AMBIENT=constant:0.1:0.5
VICTORY_AMBIENT_OUTSIDE=1:0.16
VICTORY_AMBIENT_KEY=0.18:6:room:air:geo:tint
VICTORY_AMBIENT_AIR=0.65
VICTORY_AMBIENT_TRUE_DEPTH=1
VICTORY_THIN=1
VICTORY_JOIN_PARTS=4
VICTORY_WIDE_COPY=0
VICTORY_PIPELINE_WORKERS=4
VICTORY_UPLOAD_AHEAD=1
VICTORY_PORT_GUARD=1
VICTORY_PORT_JOURNAL=1
VICTORY_CARD_TOUCHED=1
VICTORY_CARD_COMPARE_EVERY=30
```

3. **Warm the cache before judging stability.** Keep `VICTORY_CACHE_DIR` on one folder and do not change translation switches between runs (they are part of the cache key). The first run to the world on a fresh cache is the risky one; after it, the library loads mapped and no pipelines are created.
4. Keep other GPU loads (miners, capture, overlays) closed during the cold run.
5. The title is blocked from the network (outbound firewall rule for the runtime and the title; the runtime also refuses title HTTP).

Local evidence: `build-rea-r27-atual/run/` (sessions 2026-11-27 12:22 and 13:48), relative to the workspace.

## Open hypotheses and next step

- Measure where the unexplained part of slow frames goes (e.g. a 1077 ms frame with ~150 ms in our counters): title threads waiting on fences or readbacks.
- Find why title buffer copies spike during streaming bursts (634 copies, 877 MB in one frame) and test one copy switch at a time against these aggregates.
- Fewer parallel pipeline workers on a cold cache (`VICTORY_PIPELINE_WORKERS=1`) reached the world in a first test on the successor build; not yet repeated.
