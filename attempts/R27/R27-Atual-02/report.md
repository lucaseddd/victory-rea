# R27 · From 5.8 to 9.4 fps on a 6 GB RTX 3060 Laptop, game on a hard drive · attempt R27-Atual-02

- **Issue:** Marvisak/VIctory#3552 · **Area:** performance, VRAM, rendering
- **Build:** the same as [R27-Atual-01](../R27-Atual-01/report.md) (`victory.exe` sha256 `928CCEC71FCC4671CA8517F25E3784871837BF123E780A86E2F1EB0427570E91`). No code change, only switches and the launch scripts.
- **Scene and checkpoints:** boot → menus → prologue (prison), first 36 samples with more than 1000 draws/frame
- **Effective profile:** `Fluidez` (Series S) of R27-Atual-01, plus the changes below
- **Resolution, scale, graphics, cache:** 1280x720, the title's own upscaler, no DLSS, no frame generation · warm pipeline cache
- **Hardware:** RTX 3060 Laptop 6 GB, Ryzen 7 5700X, 32 GB RAM, game package on a 5400 rpm SATA hard drive, a SATA SSD free
- **Progress:** 75%

## One-line result

Three findings, no code: the 6 GB card was holding **3 GB of fragmented, empty texture-pool space** (VRAM at 169% of budget, so new textures were refused), the submission was stopping on a **128-list limit** about once a frame for ~25 ms, and the cache on the same hard drive as the game slowed loading. Fixed by switches: median 5.8 → 9.4 fps, the worst 10% 0.6 → 5.7 fps, time to the world 744 → 482 s, and 1.7–2.2x more textures drawn.

## Findings

1. **The main frame thread is waiting on the GPU, not working.** [observed] Sampling the instruction pointer of the title's busiest thread: 97% of its samples in its own code fall in ~50 bytes, a `monitorx`/`mwaitx` loop on a 64-bit fence value in title memory. The CPU time Windows shows for it is that wait. On the PC the value lands only after our preparation (~100 ms), the GPU (~35 ms) and the copy-back (~50 ms), in series. The GPU itself is ~20% of a frame, so DLSS/FSR or lower graphics would not move the frame rate much here.
2. **VRAM over budget from texture-pool fragmentation.** [observed] The runtime's own line: "7558 MB in use of a budget of 4323 MB … **3029 MB of texture blocks free**; room for new textures: no". The pool cuts textures from 64 MiB blocks; a block is only given back when it is completely empty, so blocks with a few live textures keep the rest committed. Admission subtracts that free space, but the memory is still committed, so Windows pages the card's memory to system RAM, and 11,800 title textures had no host copy (walls and floors that never arrive). `VICTORY_TEXTURE_POOL=0` (one allocation per texture): 0 MB of free blocks, VRAM 86–89% of budget, 10,061–13,083 textures alive against 5,889.
3. **`VICTORY_LATE_WAIT_LISTS=128` stalls the submission.** [observed] With 128, "128 lists in the air" settled the flights 0.9 times a frame with ~25 ms of waiting each time. The runtime's own doc calls 128 the old value (256 is the default). With 256: 0.0 stalls, and "tables asked, 0 refused" (no descriptor-slot shortage).
4. **Other programs take the card's budget.** [observed] The D3D12 budget was 4.1–4.9 GB of the 6 GB card while browsers and chat apps were open. Closing them is free VRAM.
5. **The menu auto-advance script never fired.** [observed] Its pattern expected ISO timestamps; the runtime logs `dd/MM/yyyy HH:mm:ss` local time. Fixed version: [Avancar-Menu.ps1](Avancar-Menu.ps1).
6. **`VICTORY_MEMORY_CARD_MB` does not matter with ray tracing off.** [observed] It caps only the by-address copies of the ray-tracing structures, which were ~0 MB here (`VICTORY_RT_MISS=1`, `VICTORY_BVH_BUILDER=0`). `VICTORY_CARD_BUFFERS_MB` is the cap that was full (540 of 512 MB), but raising it would push the card further over budget on 6 GB.

## Metrics

Full table: [aggregates.csv](aggregates.csv). Single runs on one machine, the same save, the first 36 world samples (5 s each).

| Run | Change | To world | fps median / p10 | under 3 fps | VRAM / budget |
|---|---|---|---|---|---|
| H0 | cache on the HDD (menu by hand) | 744 s | 5.8 / 0.6 | 19% | 118% |
| T0 | cache and saves on an SSD | 693 s | 9.0 / 5.0 | 8% | 169% |
| T1 | + `VICTORY_TEXTURE_POOL=0` | 527 s | 9.2 / 3.0 | 9% | 86% |
| **T2** | **+ `VICTORY_LATE_WAIT_LISTS=256`** | **482 s** | **9.4 / 5.7** | **6%** | **89%** |

T0 also lowered `VICTORY_AMBIENT_AIR` from 0.65 to 0.3 (the brown haze), which is part of every run after H0.

## How to reproduce

Start from R27-Atual-01's variable list and change:

```
VICTORY_CACHE_DIR=<a folder on an SSD>      # with VICTORY_DATA_DIR there too
VICTORY_DATA_DIR=<a folder on an SSD>
VICTORY_AMBIENT_AIR=0.3
VICTORY_TEXTURE_POOL=0
VICTORY_LATE_WAIT_LISTS=256
```

1. Copy an existing warm cache folder to the SSD rather than starting a new one: translation switches are part of the cache key, these are not, so the copy stays warm.
2. Close browsers, chat and overlay apps before starting: they take VRAM budget.
3. The game package can stay on the hard drive.

## Open hypotheses and next step

- The remaining frame is the preparation (~100 ms) and copy-back (~50 ms) in series before the title's fence lands: overlapping the copy-back with the next frame's preparation is where the next large gain is.
- The texture pool could give back blocks that fall under a share of use (compaction) instead of only empty ones, keeping its allocation speed without the fragmentation.
