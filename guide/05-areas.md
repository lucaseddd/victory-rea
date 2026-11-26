# 5. Area map

A starting point per area. RVAs and numbers are from **candidate 1** (`victory.exe` SHA-256 `D29834AE…378D772`, PDB GUID `{59A6A622-1BF5-4FB1-8733-C224125D0A00}` age 1). They come from the reports of 2026-11-26 and are tagged `[reported]`. On another build, check them again.

The log numbers come from one run of the Control profile **outside the protocol** (no identified scene, no exclusive window). Use them for orientation, not as a baseline.

## Submission and next frame (R01, label `submission`)

- `frame::wait` (RVA `0x252C40`) produces the frame token. `queue::execute` (`0x173BD0`) with `VICTORY_ASYNC_SUBMIT=1` stacks the parts and wakes the `victory-submit` thread (`queue::worker`, `0x173840`).
- `Host::submit` (`0x2BD070`) assigns `STARTED`, executes the lists on the DIRECT queue and signals `Host.fence`.
- `victory-relay` (`0x2EB520`) waits for the fence, calls `Host::relay_land` (`0x2A8D60`) and only then publishes the guest fence and `FINISHED`.
- With `VICTORY_ASYNC_PRESENT=0`, `queue::present` (`0x1765D0`) is synchronous and waits for the submission thread. [reported]

## Readback and fence (R02, R05, label `readback`)

- The guest fence (`Fence::value`, +0x10) is published only at the end of `relay_land`, after `card_merge_relay`, `read_backs` and `Late::Write`. `fence::set` is at RVA `0x487D40`, called at `0x2AE4E3`. [reported]
- `VICTORY_QUEUE2=0`: the copy back runs on DIRECT. `=1`: it runs on the COPY queue `second.down` (`Lane::send`, `0x26D170`), preceded by `Wait(host.fence)`. [reported]
- `QUEUE2=1` does not only change the queue. It also enables `BESIDE` (re-reading 64 KiB blocks) and `Second::sent_up`, and creates two COPY queues and three threads. An A/B of `QUEUE2` measures all of that together. [reported, R05]
- In the Control log (world): median `relay_wait_card` 163 ms and `settle_wait` 126 ms. [reported]

## GPU execution (R06, label `gpu-exec`)

- `VICTORY_LATE_WAIT=1` makes the early branch (`ExecuteCommandLists` + `Signal` without waiting) the default.
- DIRECT waits for COPY on the GPU (`Second::hold`), and present does a serial copy of the frame to the back buffer.
- Still to measure with per-queue timestamps (R03). [reported]

## VRAM and mipmaps (R07, label `vram-mips`)

- `resource::room_with_memory` (`0x283190`): below the floor, the title's textures are created without checking the budget; above it, only while usage is < 90% of the budget. PR #45 replaces the fixed 2 GiB floor with `min(2 GiB, budget/4)`. [reported]
- `targets_room_kept` reserves 3 GiB for render targets and stopped texture creation with only 46% of the budget in use. [reported]
- `tiles::show_from` (`0x488A10`) adjusts `MostDetailedMip` while preserving `ResourceMinLODClamp`. With `VICTORY_TILES_SMALL_WHEN_FULL_MB=0`, 22–62 tiled textures had no level at all (black). [reported]

## Texture worker (R08, label `textures`)

- `VICTORY_HEAP_WORKER=1` moves uploads to the `victory-heap` thread (`heap_worker::worker`, `0x1A87C0`). The resulting lists go to **DIRECT** ahead of the title's, not to COPY. [reported]
- Without the worker, `heap_textures` took a median of 15 ms and a p95 of 74 ms on the recording thread. [reported]

## DirectStorage (R09, label `directstorage`)

- 16 workers (one per core), 32 MiB of staging, and `read_into` (`0x133BF0`) without coalescing. [reported]
- On a SATA HDD, loading is disk-bound: 2.5 to 6 MB/s in reads of ~16 KB, with only 2–5% contiguous. Coalescing does not pay off. [reported, candidate 4]
- Use patch 01 (`VICTORY_DSTORAGE_STATS`) to measure and patch 05 (`VICTORY_DSTORAGE_WORKERS`) to try fewer simultaneous reads.

## Threads and waits (R10, label `threads-sync`)

- In the world, the render thread was ~96% blocked. DIRECT sat idle ~443 ms per ~782 ms frame. [reported]
- Largest waits: PSOs in `pipeline::make::wait` (~500 ms/frame), the `HostHeap::mirror` mutex with `VICTORY_HEAP_LOCKS=0`, and `settle` on `WHY_STALE`. [reported]
- `MWAITX` did not show up in any log line. Investigate it only if the data points there. [reported]

## Shaders and PSOs (R11, label `shaders`)

- The first draw calls `make::ready` (`0x1FB280`), which waits up to `VICTORY_PIPELINE_WAIT_MS=500` ms per tick. A frame that spans two ticks can reach ~1 s. [reported]
- Cold cache: `wait_for_pipelines` ~500 ms in every world window. With the reference's warm cache: 0 ms median and 9.6 ms p95. [reported]
- The shader cache is keyed by the translator's fingerprint (`translation_fingerprint`), not the exe hash. You can reuse the cache across candidates when the translator is identical (check by hash). [reported]

## Present and pacing (R12, label `present`)

- The goal's FPS counts DXGI Presents (`Meter::frame`, `host.rs`), with `FLIP_DISCARD`, 2 buffers and `SyncInterval=0`. It mixes world frames with menu and loading frames. [reported]
- With `--console series-s`, the title presents two planes. Without patch 03, only the scene shows and the interface comes out black.

## Image regressions (R13, label `image-regression`)

- Black cutscene on candidate 1: PR #45's `budget/4` floor held the title's textures at ~849 MB (median), against 1,921 MB on the reference. Surfaces lost their base color. Patch 02 makes PR #45 opt-in. [reported]
- A `diagnostics` build logs `a black frame after a frame that was not`, a good automatic trigger.
