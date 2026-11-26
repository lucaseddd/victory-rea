# R24 · Build correctness-gated automated scoring and regression runs · attempt R24-Agy-01

- **Issue:** #26 · **Area:** `baseline`
- **Build:** `victory.exe` sha256 `77b6124fa673ebb0d32e9b92fadbb0691bc3d2d3c21ecf4186d8287df2edd9b8` · PDB `victory.pdb` GUID `14F11B44E861429C850B936ADEAF6A88` age `1` (compared builds: cand4 `2ffd8cb5f3e66c16e6cec8005e778a76692a337fd1075cc3d3cd72991ff41973` PDB GUID `079087F6D20D457980A62BC749D33EE3` age `1`; cand5 `db827d457c47c607489dba29bcfe4a85d8e0bba3f149111bb911553f6bd7fbe9` PDB GUID `12F63D85330944469A11A69A686708C8` age `1`)
- **Scene and checkpoints:** Static/binary verification + offline `C1` (opening cutscene) log & capture comparison (GPU held by `R27-Nina-01`, no new capture launched)
- **Effective profile:** Series S `1280x720`, `VICTORY_QUEUE2=0`, `VICTORY_HEAP_WORKER=0`, `VICTORY_LEVELS_ON_DEMAND=1`, `VICTORY_TEXTURE_AUTO_VRAM=0`, `VICTORY_FRAME_LOG=1`, `cache=warm`
- **Progress:** 75% (schema v2.0.0 scorer, independent gates, 8 anti-gaming fixture tests, and local Cand4 vs Cand5 comparison complete; live C1/M1 GPU run and `harness/` integration via `coordination` PR pending)

## One-line result

Built and fixture-tested correctness-gated scorer v2.0.0 (`score_v2.py`, 8/8 anti-gaming tests passing), fixed three measurement defects in the existing watcher/scorer, and published a comparable local Cand4 vs Cand5 baseline showing `unavailable` visual/ground/facial gates still block release qualification.

## Findings

1. **R12 binary and counter semantics verified on current build** `[observed]` — Inspected `build-next-rea\dist\victory.exe` (`77b6124fa673ebb0d32e9b92fadbb0691bc3d2d3c21ecf4186d8287df2edd9b8`) with REA (`inspect_pe_resources` evidence `ev_9e75527a4fc36e459e344375e1b88fe6ee83f6b9d123fb3eed107e9405c4421f`; `inspect_rust_binary` evidence `ev_1de68e6670412ea59e3458dd8293b1c3d86511546fd795d3be36cc124ff0c332`) and confirmed PDB symbols `victory_gpu::queue::present`, `victory_gpu::host::Meter::frame`, `victory_gpu::framelog::frame`, `victory_gpu::framelog::kinds`, `victory_gpu::capture::probe`, `victory_gpu::capture::black`, and `victory_gpu::compose::Compose` (`victory.pdb` GUID `14F11B44E861429C850B936ADEAF6A88`, age `1`).
2. **Existing watcher shader-coverage formula bug** `[observed]` — In `host.rs` (`Meter::frame`), logged `draws/frame` equals executed `DRAWN` only (excluding `DROPPED`). `harness/Watch-Run.ps1` computed `dropped / draws` instead of `dropped / (draws + dropped)`, which overstates drop fraction and can turn negative when `dropped > draws`. `score_v2.py` uses `drawn / (drawn + dropped)`.
3. **Mixed-window contamination and window-averaged p95** `[observed]` — `Meter::frame` logs ~5 s window averages while `framelog::frame()` logs per-frame durations (`each:`) and classifies frames per window (`WORLD_SUBMISSIONS = 6.0`). Filtering to pure-world `framelog` windows (`world > 0 && menu == 0`) excludes `149` mixed transition frames in cand4 and `155` in cand5, revealing true per-frame medians/p95 (`321.0 / 1155.0 ms` for cand4 vs old `399.2 / 1831 ms`; `293.0 / 797.0 ms` for cand5).
4. **Premature autosave milestone detection** `[observed]` — Local cand5 milestone log recorded `autosave` at `18.8 s` before `Enter accepted` (`125.6 s`) and before `first_3d_scene`. `score_v2.py` gates post-world autosave detection on `t >= max(first_3d_scene_s, enter_accepted_s)`.
5. **Correctness gates and anti-gaming suite** `[observed]` — `score_v2.py` (schema `2.0.0`, self-hashed) adds four independent gates (`workload_and_render`, `image_and_geometry`, `ground_coverage_and_contact`, `facial_motion`) with explicit `unavailable` tracking so missing checks block `qualified_for_release`. `test_r24_scoring.py` verifies rejection of bright missing geometry, static mouths (including under rigid head/camera pan via 2D head-ROI registration), menu-only samples, reduced workload (`display_mode`, `render_scale`, `VICTORY_BVH_HOLD`, low draws, high shader drops), and repeated/generated frames (`frame_generation`, `present_multiplier`, `VICTORY_ASYNC_PRESENT`, zero-draw presents, identical consecutive captures).

## Metrics (Cand4 vs Cand5 · Series S 1280x720 · warm cache · C1)

| Metric | Cand4 (`2ffd8cb5`) | Cand5 (`db827d45`) | Tag |
|---|---|---|---|
| Pure-world frames (mixed frames) | 126 (149) | 1592 (155) | `[observed]` |
| Rendered FPS (from pure-world median) | 3.12 | 3.41 | `[observed]` |
| Median ms / p95 ms (per-frame) | 321.0 / 1155.0 | 293.0 / 797.0 | `[observed]` |
| % > 33.33 ms | 100.0% | 100.0% | `[observed]` |
| Hitches > 1 s (rate) | 8 (6.35%) | 44 (2.76%) | `[observed]` |
| Typical / peak VRAM MB (shared peak) | 1097.0 / 3887 (3818) | 3720.0 / 4295 (4511) | `[observed]` |
| Shader draw coverage | 97.99% | 93.73% | `[observed]` |
| Workload gate | `pass` | `pass` | `[observed]` |
| Image / Ground / Facial gates | `unavailable` / `unavailable` / `unavailable` | `unavailable` / `unavailable` / `unavailable` | `[observed]` |
| Release qualification (`qualified_for_release`) | `false` | `false` | `[observed]` |
| Score total (diagnostic v2.0.0) | 43.2 | 42.5 | `[observed]` |

- **Local capture slice check (3 frames from local `cutscene-lab`):** `image_and_geometry` = `fail` (`1/3` dark frame `< 8/255` luma, score `66.7`), `ground_coverage_and_contact` = `unavailable` (visual ground `pass` with median luma `113.46`, std `67.89`, grad `3.61`, edge fraction `0.079`; physics `contact_status = unavailable`), `facial_motion` = `unavailable` `[observed]`.
- **Time split (`Meter` world median, prepare / GPU wait / copy-back):** **unavailable** in `candidate_comparison.csv` (recorded in `score_v2.py` JSON output when invoked directly).

## How to reproduce

Run offline fixture tests, local aggregate comparison, and repository content check (raw logs/PNGs stay local outside the repo):

```powershell
python -B attempts/R24/R24-Agy-01/test_r24_scoring.py
python -B attempts/R24/R24-Agy-01/evaluate_local_comparison.py
powershell -ExecutionPolicy Bypass -File scripts/Test-RepoContent.ps1
```

- Local raw log sources (not committed): `fxceless-f6a09d3b-cand4-run` and `victory-pipeline/rodadas` in the local workspace.
- Output aggregate table: [candidate_comparison.csv](candidate_comparison.csv).

## Open hypotheses and next step

- Once the GPU lock is free and C1/M1 checkpoints + contact probes + spoken/silent face ROI captures are established (R04/R16/R17), run `score_v2.py` on matched cold/warm C1 and M1 pairs to eliminate `unavailable` gates.
- Wire `score_v2.py` schema `2.0.0` and comparability checks into `harness/Watch-Run.ps1` and `harness/Compare-Runs.ps1` via a separate `coordination` PR.
