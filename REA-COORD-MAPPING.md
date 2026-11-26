# GitHub REA board

The [GitHub Issues](https://github.com/lucaseddd/victory-rea/issues) are the source of truth for task ownership, milestones, blockers, handoffs, and evidence links. The local board is historical for ownership. The local GPU lock remains authoritative for GPU use. See the [ranked research roadmap](docs/roadmap.md) and the [contribution protocol](CONTRIBUTING.md).

- **Start here** · [R00, coordination](https://github.com/lucaseddd/victory-rea/issues/1).
- **Find work** · [Open, unclaimed tasks](https://github.com/lucaseddd/victory-rea/issues?q=is%3Aissue%20is%3Aopen%20label%3Atask%20label%3Astatus%3Aopen). Read the Issue and its dependencies before claiming. A repository label named `claim:Rxx` reserves the task, even if the Issue has not yet been updated.
- **Capture** · [GPU reservation mirror](https://github.com/lucaseddd/victory-rea/issues/17). Get the local lock only after confirming that the previous test ended or the user released the GPU.
- **Resume** · Local attempts migrated by name. In-progress, blocked and review attempts were reserved on GitHub. Completed historical Issues were closed. Match your attempt name before posting updates. R00 handles ownership disputes and stale attempts.

| ID | Priority | Issue | Area |
|---|---|---|---|
| R00 | P0 | [Coordination, integration and results index](https://github.com/lucaseddd/victory-rea/issues/1) | `coordination` |
| R01 | P0 | [Submission and next-frame dependency map](https://github.com/lucaseddd/victory-rea/issues/2) | `submission` |
| R02 | P0 | [Readback and guest fence publication](https://github.com/lucaseddd/victory-rea/issues/3) | `readback` |
| R03 | P0 | [Correlated instrumentation and short scene trace](https://github.com/lucaseddd/victory-rea/issues/4) | `instrumentation` |
| R04 | P0 | [Reproducible cutscene and mission baseline](https://github.com/lucaseddd/victory-rea/issues/5) | `baseline` |
| R05 | P1 | [Isolated COPY queue comparison](https://github.com/lucaseddd/victory-rea/issues/6) | `readback` |
| R06 | P1 | [Graphics and compute pass map](https://github.com/lucaseddd/victory-rea/issues/7) | `gpu-exec` |
| R07 | P1 | [VRAM, mipmaps and residency baseline](https://github.com/lucaseddd/victory-rea/issues/8) | `vram-mips` |
| R08 | P1 | [Texture worker isolation and validation](https://github.com/lucaseddd/victory-rea/issues/9) | `textures` |
| R09 | P1 | [DirectStorage and storage throughput](https://github.com/lucaseddd/victory-rea/issues/10) | `directstorage` |
| R10 | P1 | [Guest/host waits, threads and synchronization map](https://github.com/lucaseddd/victory-rea/issues/11) | `threads-sync` |
| R11 | P0 | [Shader and pipeline-cache baseline](https://github.com/lucaseddd/victory-rea/issues/12) | `shaders` |
| R12 | P1 | [Present and frame-counter semantics](https://github.com/lucaseddd/victory-rea/issues/13) | `present` |
| R13 | P0 | [Black-cutscene regression and guardrail](https://github.com/lucaseddd/victory-rea/issues/14) | `image-regression` |
| R14 | P2 | [Fix the dominant measured frame blocker](https://github.com/lucaseddd/victory-rea/issues/15) | `optimization` |
| R15 | P2 | [Release qualification at 30 rendered FPS](https://github.com/lucaseddd/victory-rea/issues/16) | `validation` |
| R16 | P0 | [Restore terrain and missing geometry from culling to draw](https://github.com/lucaseddd/victory-rea/issues/18) | `geometry` |
| R17 | P0 | [Restore facial animation and audio/video synchronization](https://github.com/lucaseddd/victory-rea/issues/19) | `animation` |
| R18 | P0 | [Recover render-pass fidelity, depth, lighting and composition](https://github.com/lucaseddd/victory-rea/issues/20) | `image-regression` |
| R19 | P1 | [Reduce CPU preparation and submission bottlenecks](https://github.com/lucaseddd/victory-rea/issues/21) | `threads-sync` |
| R20 | P1 | [Fit textures, tiles and residency into the 6 GB working set](https://github.com/lucaseddd/victory-rea/issues/22) | `vram-mips` |
| R21 | P0 | [Restore world-data coherence and ground contact](https://github.com/lucaseddd/victory-rea/issues/23) | `directstorage` |
| R22 | P1 | [Recover shader coverage and remove first-use PSO stalls](https://github.com/lucaseddd/victory-rea/issues/24) | `shaders` |
| R23 | P1 | [Reduce GPU critical-pass cost without changing output](https://github.com/lucaseddd/victory-rea/issues/25) | `gpu-exec` |
| R24 | P0 | [Build correctness-gated automated scoring and regression runs](https://github.com/lucaseddd/victory-rea/issues/26) | `baseline` |
| R25 | P1 | [Eliminate device loss and qualify long sessions](https://github.com/lucaseddd/victory-rea/issues/27) | `validation` |
| R26 | P2 | [Stabilize displayed pacing and input once engine work is measured](https://github.com/lucaseddd/victory-rea/issues/28) | `present` |
| R27 | P1 | [Evaluate and integrate focused upstream changes](https://github.com/lucaseddd/victory-rea/issues/29) | `coordination` |
| R28 | P2 | [Extend qualification beyond the opening scene](https://github.com/lucaseddd/victory-rea/issues/30) | `validation` |

Issue numbers are permanent links, independent of task IDs. Raw logs, captures, game material, tool databases and local session identifiers stay on the machine. Publish only allowed evidence under the [data policy](DATA-POLICY.md).
