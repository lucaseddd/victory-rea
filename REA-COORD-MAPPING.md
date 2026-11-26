# Mapping REA-COORD to Issues (proposal)

This is only a proposal. **Nothing has been created on GitHub.** The states below come from the local `status\*.md` files read on 2026-11-26 around 07:48 (UTC-3), and they change quickly. Re-read the local board before creating the Issues.

## Creation order

Created in this order in an empty repository, Issue #1 is R00 and #16 is R15, so each Issue number is the task number plus 1. #17 is the **GPU lock** (pinned).

## Tasks R00–R15

| Issue | Task | Labels | Local state → label | Progress | Holder (`claim:` comment) | Dependencies |
|---|---|---|---|---|---|---|
| #1 | R00 · Coordination and index | `coordination` `P0` | in progress (cycle 1 closed) → `status:in-progress` | 100% of cycle 1 | `R00-Lia-01` | — |
| #2 | R01 · Submission and start of the next frame | `submission` `P0` | done → closed | 100% | `R01-Caio-01` | — |
| #3 | R02 · Readback and fence publication | `readback` `P0` | done → closed | 100% | `R02-Beto-01` | — |
| #4 | R03 · Instrumentation and short capture | `instrumentation` `P0` `needs-gpu` | blocked → `status:blocked` | 75% | `R03-Nina-01` | R01, R02, GPU lock |
| #5 | R04 · Baseline and visual regression | `baseline` `image-regression` `P0` `needs-gpu` | blocked (needs an elevated PowerShell) → `status:blocked` | 50% | `R04-Davi-01` (holds the GPU lock) | R03, GPU lock |
| #6 | R05 · Isolated COPY-queue comparison | `readback` `P0` `needs-gpu` | blocked → `status:blocked` | 50% | `R05-Teo-01` | R03, R04, GPU lock |
| #7 | R06 · Graphics and compute execution | `gpu-exec` `P1` | in progress → `status:in-progress` | 50% | `R06-Iris-01` | R03 to attribute time |
| #8 | R07 · VRAM, residency and mipmaps | `vram-mips` `P1` | done → closed | 100% | `R07-Vera-01` | — |
| #9 | R08 · Texture worker | `textures` `P1` `needs-gpu` | blocked → `status:blocked` | 75% | `R08-Ciro-01` | R05 |
| #10 | R09 · DirectStorage and HDD streaming | `directstorage` `P1` `needs-gpu` | blocked → `status:blocked` | 75% | `R09-Teo-01` | GPU lock |
| #11 | R10 · Threads, waits and guest/host sync | `threads-sync` `P1` | done → closed | 100% | `R10-Gael-01` | R01, R02 |
| #12 | R11 · Shaders, PSOs and cache | `shaders` `P1` `needs-gpu` | blocked → `status:blocked` | 75% | `R11-Mila-01` | GPU lock, elevation |
| #13 | R12 · Present, pacing and rendered frames | `present` `P1` | in review → `status:in-review` | 75% | `R12-Rui-01` | — |
| #14 | R13 · Isolate image regressions | `image-regression` `P2` `needs-gpu` | fix built, verification pending → `status:in-review` | 75% | `R13-Otto-01` | R04/R05, GPU lock |
| #15 | R14 · Optimize the largest measured blocker | `optimization` `P2` | unclaimed → `status:open` | 0% | — | R03–R05 + area report |
| #16 | R15 · Validate the final candidate | `validation` `P2` | unclaimed → `status:open` | 0% | — | R14, or a baseline that meets the goal |
| #17 | GPU lock (pinned) | `needs-gpu` | mirror of `locks\gpu-capture.json` | — | latest `reserved:`/`released` comment | — |

Note: R05 and R09 show the same AI name (Teo) in different sessions. On the Issue, the attempt (`R05-Teo-01`, `R09-Teo-01`) identifies the holder.

## Other board items

| Local | Proposal |
|---|---|
| `TASKLIST.md` | Becomes Issues #1–#16. The board's rules are already in `CONTRIBUTING.md` |
| `status\R??.md` | One-line summary in the Issue's **Status** field: state, progress, blocker, next step |
| `journal\R??\` | Do not migrate the history. From now on, one comment per relevant step |
| `evidence\R??\<attempt>\` | **Stays local.** Each attempt becomes a PR with `attempts/R??/<attempt>/report.md`, rewritten with only hashes, offsets/RVAs, VIctory symbol names and aggregate numbers |
| `claims\R??.json` | Assignee + a `claim: <attempt>` comment |
| `claims\arquivo\` (local archive folder; OCUP-01, OCUP-02) | Do not become Issues. A comment on #1 records that they were closed at 07:30 |
| `CONFLITOS.md` | Already resolved. A comment on #1 summarizes it; from now on, the `conflict` label |
| `locks\gpu-capture.json` | Stays local and atomic. #17 only mirrors it |
| `REA-INDEX.md` | `docs/index.md`, edited only by R00 PRs |

## Care when migrating existing attempts

- **Disassembly.** The local reports for R00, R08 and other tasks quote `dumpbin /disasm` and Ghidra output. Only the address and the symbol name go into a PR, never instruction lines.
- **CSVs.** Check log-sample CSVs before they go in: only aggregate numeric columns, no lines copied from the raw log.
- **Recordings.** R13's status cites a video recording in a user-profile folder. In the PR, write "local recording of the cutscene" and give only the numbers.
- **Session IDs.** Do not migrate the AIs' session IDs: the attempt name is enough.
- **Check.** Run `scripts/Test-RepoContent.ps1` before every PR.
