# R21 · Restore world-data coherence and ground contact · attempt R21-Agy4-01

- **Issue:** #23 · **Area:** `directstorage`
- **Build:** `fxceless-f6a09d3b-cand5/target/release/victory.exe` sha256 `db827d457c47c607489dba29bcfe4a85d8e0bba3f149111bb911553f6bd7fbe9` · PDB GUID `12F63D85-3309-4446-9A11-A69A686708C8` age `1`; isolated patched release `r21-cand5-work/target/release/victory.exe` sha256 `0c6f8c7c4898c32f0f07b1f200fef2596809179a71e2464732f9f9bb747e231f` · PDB GUID `CF43EC56-436B-4BE3-9E7A-BA12465E4D14` age `1` (also compared `build-next-rea/dist/victory.exe` sha256 `77b6124fa673ebb0d32e9b92fadbb0691bc3d2d3c21ecf4186d8287df2edd9b8` · PDB GUID `14F11B44-E861-429C-850B-936ADEAF6A88` age `1`, `local_commit` `abb78b91c27bda894345516fdd8de9166768c897`)
- **Scene and checkpoints:** Static source audit, cross-log aggregate analysis (6 local logs), offline unit reproduction tests, and isolated release compilation; live GPU scene A/B capture blocked by active `R27-NVIDIA` GPU reservation (`REA-COORD/locks/gpu-capture.json`, PID `14064`).
- **Effective profile:** Baseline logs reviewed under Series S `1280x720` (`VICTORY_PAGE_WRITES=guards` / unset, `VICTORY_LEVELS_ON_DEMAND=1`, `VICTORY_ASK_ONCE=1` default, `VICTORY_TEXTURE_BACK` unset) · cache state varies per logged run (`cold`/`warm`, non-comparable across runs outside exclusive protocol `[observed]`)
- **Resolution, scale, graphics, cache:** `1280x720` (`Series S` profile logs) · offline tests deterministic without live game scene
- **Progress:** 75% (first divergent coherence paths proved in code, logs, and offline regression tests; isolated `r21-cand5-work` fix verified offline and compiled; live GPU A/B verification pending GPU lock release)

## One-line result

Proved and fixed `VICTORY_PAGE_WRITES` coherence gaps in `cand5` (dropping plain-address DirectStorage completions, leaving uploaded placed-texture slots stale across physical-page writes, and skipping standing `VICTORY_ASK_ONCE` invalidation), verified GPU->CPU `texback` fence ordering alongside its disabled default (`VICTORY_TEXTURE_BACK`), and pinpointed the separate `build-next-rea` `VICTORY_PARALLEL_REFRESH=1` vs `Step::Host(on_demand.uploaded)` race causing `utm = 0` (`1,051`–`1,162` blank on-demand textures).

## Findings

1. **DirectStorage physical-page and plain-address writes leave placed textures and `ask_once` snapshots stale under default/`guards` mode (`cand5` & `build-next-rea`)** `[observed]` — `crates/victory-gpu/src/watch.rs:1606-1666` (`page_writes`, `title_memory_written`), `crates/victory-hle/src/modules/dstorage.rs:1182-1221` (`into_destination_inner`), `crates/victory-gpu/src/descriptor/host.rs:1500-1534` (`texture_slots_page_written`, `slots_written_under`):
   - When `VICTORY_PAGE_WRITES` is unset or `guards`, `page_writes()` returns `1` (bit 0 only).
   - **Bit 2 disabled (`page_writes() & 2 == 0`):** `HostHeap::texture_slots_page_written` (`descriptor/host.rs:1505`) passes `due = false` to `slots_written_under`, leaving already-uploaded placed texture slots stale after `xmem::pages_written` (`dstorage.rs:1219`). In `cand5` (`v002-cand5-cena-preta-db827d45`), `6,367` of `8,923` touched slots were left `"as they were"`, triggering `212` warnings (`a texture picked by index changed after its upload`, up to `frames_after_upload=909`). Across the 6 inspected logs, `546`–`6,367` uploaded placed slots were left stale (`200`–`227` warnings per run).
   - **Bit 4 disabled (`!pages && mode & 4 == 0`):** `dstorage.rs:1187` opens guards and marks `descriptor::host::remapped` **before** slow `fill(out)` reads/decompresses (`p50 = 164,678–442,138 us`, `p95 = 508,104–3,605,148 us`, `max = 3,800,259 us` in `cand5` and `BuffersVRAM`), then calls `victory_gpu::title_memory_written(addr, len, false)` at completion (`dstorage.rs:1197`). Mode `1` discards every plain-address completion (`54,066`–`104,060` dropped per run as `"counted only"`), never re-invalidating placed textures or any alias views touched between `kernel_will_write` and `fill(out)` completion.
   - **Standing `VICTORY_ASK_ONCE=1` snapshot not notified:** Even when `mode` enables guards/all, `title_memory_written` never called `watch::wrote(at, len)` (`watch.rs:275-291`), so a concurrent `Shadow` refresh in the same submission short-circuiting on `j.ahead` (`watch.rs:435`) could observe pre-write data until the next submission.
   - **Isolated fix in `r21-cand5-work` (`cand5` baseline):** Added `parse_page_writes` defaulting unset `VICTORY_PAGE_WRITES` to `7` (`all`, while preserving explicit `guards` = `1` for A/B tests), extracted `note_written` to open guards, notify `watch::wrote` for standing `ask_once` snapshots, notify `descriptor::host::page_written`, and fan out `!pages` writes that overlap mapped views via `inplace::views_between` + `inplace::pages_of`. Note that profiles explicitly passing `VICTORY_PAGE_WRITES=guards` will retain mode `1` until removed or switched in A/B.

2. **GPU-written texture readback (`texback`) preserves fence ordering when enabled, but defaults to off** `[observed]` — `crates/victory-gpu/src/texback.rs:30-59, 205-253`, `crates/victory-gpu/src/host.rs:6127-6139, 6576-6588, 6909-6915, 7701-7733`, `crates/victory-gpu/src/draw.rs:4662`:
   - In `relay_land`, `settle`, and synchronous `Host::submit`, `read_backs` (executing `texback::land`) always runs strictly **before** `Late::Signal -> crate::fence::set` (consistent with R02 findings).
   - However `texback::kinds()` returns empty unless `VICTORY_TEXTURE_BACK=1` (covering `256x256f41`, `256x256f16`, `64x64f16`, `128x128f36` water height/displacement targets) is set (`0` `texture readback landed` events in all 6 logs; also note `fxceless-f6a09d3b-cand5/README.md:158-165` `[reported]` kept it opt-in pending long-run stability verification against run 276 device loss).

3. **Separate `build-next-rea` regression: `VICTORY_PARALLEL_REFRESH=1` starves `on_demand.uploaded` (`utm = 0`) [cross-area note for R27]** `[observed]` — `build-next-rea/source/crates/victory-gpu/src/host.rs:8596-8648` (`run_deferred`) vs `crates/victory-gpu/src/texture.rs:820-830` (`upload`):
   - `texture::upload` queues `Step::Texture(staging)` immediately before `Step::Host(move || on_demand.uploaded(staging.detiled.load(Relaxed), ...))`.
   - Under `VICTORY_PARALLEL_REFRESH=1`, `Step::Texture` only pushes `staging` onto `batch.due_textures` without calling `staging.refresh()`, and `Step::Host(work)` executes `work()` **before** `batch.check_textures()`.
   - Consequently `on_demand.uploaded` receives `held = 0`, producing `0` tile mappings (`0` levels for `3` made initially, remaining `0` through `1,003` made objects in `BuffersVRAM` despite `TexHashed = 6.2 MB`), and leaving `1,051`–`1,162` placed texture slots reading zeros (`no level judged the title's at its last upload`) across all 4 `build-next-rea` logs (`BuffersVRAM`, `Integrado`, `r27_mouth`, `r27_perf`), compared to `1` (`cand4`) and `52` (`cand5_v002` where `4,774` made received `5,599` levels). `cand5` baseline does not include `VICTORY_PARALLEL_REFRESH`.

## Metrics

### Aggregate telemetry from local runs (`[observed]`, outside exclusive-GPU A/B protocol)

| Run | On-demand first (`alive/made/lv/MB`) | On-demand last (`alive/made/lv/MB`) | Census ok / total | Blank on-demand (`no held`) | Phys writes (MB) / blocks opened | Plain reads (`action`) | Placed slots stale / touched (`action`) | `changed after upload` warns | `texback` landed | Tag |
|---|---|---|---|---|---|---|---|---|---|---|
| `cand4_HW0` | `3/3/3lv/0MB` | `1048/1493/1763lv/121MB` | `10022/15907` | `1` (`N/A`) | `32786` (`1222`) / `2440` | `54066` (`counted only`) | `546` / `938` (`left as they were`) | `200` | `0` | `[observed]` |
| `cand5_v002_HW0` | `3/3/3lv/0MB` | `1170/4774/5599lv/172MB` | `12782/17765` | `52` (`N/A`) | `102892` (`5319`) / `17695` | `104060` (`counted only`) | `6367` / `8923` (`left as they were`) | `212` | `0` | `[observed]` |
| `next_rea_BuffersVRAM` | `3/3/0lv/0MB` | `1202/3386/413lv/62MB` | `9942/11341` | `1162` (`1162`) | `63243` (`2612`) / `10321` | `86140` (`counted only`) | `3142` / `3721` (`left as they were`) | `209` | `0` | `[observed]` |
| `next_rea_Integrado` | `3/3/0lv/0MB` | `1069/3995/264lv/22MB` | `9895/13835` | `1051` (`1051`) | `92263` (`4554`) / `14080` | `90225` (`counted only`) | `6139` / `7937` (`left as they were`) | `227` | `0` | `[observed]` |
| `r27_mouth_Integrado` | `3/3/0lv/0MB` | `1192/2508/398lv/25MB` | `9784/11218` | `1153` (`1153`) | `61897` (`3366`) / `15417` | `75107` (`counted only`) | `3375` / `4002` (`left as they were`) | `211` | `0` | `[observed]` |
| `r27_perf_Fluidez` | `3/3/0lv/0MB` | `1305/1508/30lv/0MB` | `8107/13531` | `1094` (`1089`) | `30214` (`1044`) / `1462` | `54559` (`counted only`) | `800` / `921` (`left as they were`) | `201` | `0` | `[observed]` |

### Scene performance & verification gates (`r21-cand5-work`)

| Metric | Value | Tag |
|---|---|---|
| Rendered FPS | **unavailable** (GPU lock held by `R27-NVIDIA`, PID `14064`) | |
| Median ms / p95 ms | **unavailable** | |
| % > 33.33 ms | **unavailable** | |
| Hitches | **unavailable** | |
| Typical / peak VRAM MB | **unavailable** | |
| Score (if the harness was run) | **unavailable** | |
| Offline unit suite (`cargo test -p victory-gpu --offline`) | `216 passed; 1 failed` (pre-existing `pipeline::host::tests::depth_bounds_pipeline_loads_and_filters_draws` panicking at line `1418` `HRESULT(0x80070057)`); `6 ignored` | `[observed]` |
| Offline unit suite (`cargo test -p victory-hle --offline`) | `108 passed; 0 failed` lib + `1 passed; 0 failed` (`no_dll_planting`), `0 ignored` | `[observed]` |
| Offline `watch::tests` (`-- --test-threads=1`) | `21 passed; 0 failed; 1 ignored` (note: an earlier parallel run hit pre-existing `writes_in_partly_committed_view_blocks_are_reported` VA-reuse race after `kernel_reads_into_guarded_blocks_after_opening` unmaps before `title_memory_remapped`; serialized run passes 21/21 including new coherence tests) | `[observed]` |
| Offline `descriptor::host::tests` | `24 passed; 0 failed; 0 ignored` (including `default_page_writes_schedules_uploaded_placed_slots`) | `[observed]` |
| Release build (`cargo build --release -p victory --offline`) | Compiled in `1m 23s`; SHA-256 `0c6f8c7c4898c32f0f07b1f200fef2596809179a71e2464732f9f9bb747e231f` | `[observed]` |

## How to reproduce

1. Generate the local aggregate table (raw `.stderr` logs stay in the workspace):

```powershell
python -B attempts/R21/R21-Agy4-01/analyze_r21_coherence.py --workspace .. --out attempts/R21/R21-Agy4-01/coherence_summary.csv
powershell -ExecutionPolicy Bypass -File scripts/Test-RepoContent.ps1
```

2. Reproduce offline unit checks and release build in `r21-cand5-work` (after initializing MSVC `vcvars64.bat`):

```cmd
cargo test -p victory-hle --offline
cargo test -p victory-gpu --lib --offline descriptor::host::tests
cargo test -p victory-gpu --lib --offline watch::tests -- --test-threads=1
cargo build --release -p victory --offline
```

- Output table: [coherence_summary.csv](coherence_summary.csv) · Script: [analyze_r21_coherence.py](analyze_r21_coherence.py).

## Patch applied in isolated build (`r21-cand5-work`)

```diff
--- a/crates/victory-gpu/src/watch.rs
+++ b/crates/victory-gpu/src/watch.rs
@@ -1592,26 +1592,26 @@
-pub(crate) fn page_writes() -> u8 {
-    static MODE: std::sync::OnceLock<u8> = std::sync::OnceLock::new();
-    *MODE.get_or_init(|| match std::env::var("VICTORY_PAGE_WRITES").as_deref().map(str::trim) {
-        Ok("0") => 0,
-        Ok("1") => 3,
-        Ok("slots") => 2,
-        Ok("all") => 7,
-        _ => 1,
-    })
+pub(crate) fn page_writes() -> u8 {
+    static MODE: std::sync::OnceLock<u8> = std::sync::OnceLock::new();
+    *MODE.get_or_init(|| parse_page_writes(std::env::var("VICTORY_PAGE_WRITES").ok().as_deref()))
+}
+
+/// Parses `VICTORY_PAGE_WRITES` (`0`, `guards`, `slots`, `1`, `all`); unset defaults to all (`7`).
+fn parse_page_writes(value: Option<&str>) -> u8 {
+    match value.map(str::trim) {
+        Some("0") => 0,
+        Some("guards") => 1,
+        Some("slots") => 2,
+        Some("1") => 3,
+        _ => 7,
+    }
 }
 ...
 pub fn title_memory_written(at: usize, len: usize, pages: bool) {
+    note_written(at, len, pages, page_writes());
+}
+
+/// Applies a completed storage/view write under explicit `mode` bits (`page_writes`).
+fn note_written(at: usize, len: usize, pages: bool, mode: u8) {
 ...
+    let written_len = end.saturating_sub(at);
+    if mode & 1 != 0 {
+        // Keep any standing `VICTORY_ASK_ONCE=1` snapshot coherent with
+        // writes that finish while a submission is preparing.
+        wrote(at, written_len);
+    }
     // A placed texture there changed with no descriptor written.
-    crate::descriptor::host::page_written(at, len);
+    crate::descriptor::host::page_written(at, written_len);
+    if !pages {
+        for (base, bytes) in crate::inplace::views_between(at, end) {
+            let first = base.max(at) / BLOCK;
+            let last = base.saturating_add(bytes).min(end).div_ceil(BLOCK);
+            for block in first..last {
+                let lo = (block * BLOCK).max(at);
+                let hi = ((block + 1) * BLOCK).min(end);
+                let off = lo - block * BLOCK;
+                for alias in crate::inplace::pages_of(block * BLOCK) {
+                    if alias / BLOCK != block {
+                        crate::descriptor::host::page_written(alias + off, hi - lo);
+                    }
+                }
+            }
+        }
+    }
 }
```

## Open hypotheses and next step

- **Concrete GPU block:** `REA-COORD/locks/gpu-capture.json` is currently held by `R27-NVIDIA` (active `victory.exe` PID `14064`). Wait for GPU release + atomic reservation before executing live A/B runs.
- **Next A/B steps once GPU is free:**
  1. Compare baseline `cand5` (`db827d45` / `VICTORY_PAGE_WRITES=guards`) vs patched `r21-cand5-work` (`0c6f8c7c`, default `VICTORY_PAGE_WRITES=all` = `7`) on identical Series S scene, checkpoint, and warm cache, checking placed-slot stale counts (`changed after upload` warnings), frame times, and `R24` image/ground/contact checks.
  2. Test `VICTORY_TEXTURE_BACK=1` separately on `M1` water/boat physics stability (confirming whether `texback` runs without device loss under current driver/build).
  3. On `build-next-rea` (R27 coordination, Issue #29), move `on_demand.uploaded` execution in `host.rs::run_deferred` (`Step::Host` / `Step::AfterTextures`) strictly after `batch.check_textures()` before benchmarking `VICTORY_PARALLEL_REFRESH=1`.
