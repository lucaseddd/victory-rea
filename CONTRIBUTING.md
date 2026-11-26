# Contributing

This protocol carries the local `REA-COORD` board (atomic claims, status, journal, evidence and the GPU lock) over to GitHub. Read [DATA-POLICY.md](DATA-POLICY.md) (data policy) first.

## Equivalents

| Local `REA-COORD` board | GitHub |
|---|---|
| `TASKLIST.md` (R00–R15) | One long-running Issue per workstream on the [live board](REA-COORD-MAPPING.md) |
| `claims\<ID>.json` (`File.Move` without overwrite) | Create-only `claim:Rxx` repository label with the attempt in its description, plus an Issue comment |
| `status\<ID>.md` | Issue body (Status section), updated only by the holder |
| `journal\<ID>\` | Issue comments, one per relevant step |
| `evidence\<ID>\<attempt>\` | A PR with `attempts/<ID>/<attempt>/report.md` (text only); raw data stays on the machine |
| `locks\gpu-capture.json` | Stays local. The pinned [GPU reservation Issue](https://github.com/lucaseddd/victory-rea/issues/17) only mirrors the holder |
| `CONFLITOS.md` | `conflict` label + a comment on both tasks' Issues |
| `REA-INDEX.md` (edited only by R00) | `docs/index.md`, edited only by R00 PRs |

## 1. Taking a task (claim)

1. Open the [live board](REA-COORD-MAPPING.md). Pick the highest-priority available Issue whose dependencies allow meaningful work. Check the existing evidence and adjacent scopes. Keep one active workstream per investigator.
2. Choose an attempt ID unique to this session. Verify any overlap before claiming. Keep build and scope free of machine paths and game data.
3. Acquire the task with the script, substituting an available Issue, attempt, build and scope.

   ```powershell
   .\scripts\Claim-Task.ps1 -Issue 18 -Attempt R16-Ada-01 -Build '<runtime commit or SHA-256>' -Scope 'Restore missing terrain geometry and verify the causal fix'
   ```

The GitHub repository label `claim:R16` is the lock. GitHub accepts one label of that name. Always create it without `--force`. The script then attaches it to the Issue, sets `status:in-progress` and posts a claim comment. Use the label description for ownership when multiple IAs share an account. An Issue assignee is optional. Read the repository label if an Issue appears open after an interrupted claim. A process that did not acquire the label has no claim. [GitHub label API](https://docs.github.com/en/rest/issues/labels#create-a-label)

To claim manually with repository write access, create the same unique `claim:Rxx` label with your attempt and Issue number in its description. Attach it, replace `status:open` and leave a comment with the attempt, build, scope and time. If synchronization fails after creation, the label still holds the reservation. The winner or R00 can repair the Issue. Never delete or edit another claimant's label.

A claim can span multiple cycles. Report the verified milestone, next measurable experiment, and the blocker if one exists. A small isolated experiment is one milestone within the workstream. R00 archives or transfers a claim only after explicit handoff or confirmation by the user. For a verified handoff, close the ownership record in comments, update Issue status and delete the old label last if the task is reopening. Keep the old report and start the successor's new attempt. Claim labels on closed Issues may be retained as history; they must be archived before reopening.

## 2. Working

- Stay in your label's area. Found something in another area? Comment on that area's Issue and do not edit its work.
- Record relevant steps as comments (the old `journal`).
- Keep the Status section of the Issue body current: status, progress, blocker, next step.
- Progress: 0% claimed · 25% artifacts checked · 50% first evidence interpreted · 75% analysis or capture done, verification pending · 100% verified and reproducible.

## 3. One PR per attempt

- Branch: `r07/vera-01` (task in lower case / name-attempt).
- File: `attempts/R07/R07-Vera-01/report.md`, starting from [attempts/_template/report.md](attempts/_template/report.md). You may add small CSVs **of aggregate numbers** and your own scripts (`.py`, `.ps1`).
- The PR uses the template and references the Issue with `Refs #<n>`. Use `Closes #<n>` only when the task reaches 100%.
- One PR per substantive attempt. Record related experiments as milestones inside the same Issue. Keep each performance change isolated in its tested candidate.
- The `Test-RepoContent` check must pass.

## 4. Evidence tags

Every claim with a number carries one of these tags:

| Tag | Use |
|---|---|
| `[observed]` | Measured or checked by you on this machine, on this build (hash cited) |
| `[reported]` | Comes from another report, PR or status. Cite the source |
| `[estimated]` | Calculation, model or inference without direct measurement |

Missing evidence is written as **unavailable**. Do not fill it in with an estimate without the tag.

## 5. Comparable-results protocol

Every performance number states:

- build: exe and hash (SHA-256 or BLAKE3), and PDB GUID/age when available;
- scene and checkpoints (e.g. cutscene C1, first mission M1);
- effective profile (e.g. Control or Candidate) and the variables that differ;
- resolution, scale, graphics preset and cache (cold or warm);
- metrics: rendered FPS, median, p95, % > 33.33 ms, hitches, typical and peak VRAM;
- a split of times when available: CPU preparation, waiting, GPU execution, readback, CPU wait, read and fence publication.

## 6. GPU

A capture needs the GPU to itself. The reservation is still `locks\gpu-capture.json` on the machine, with the same atomic `File.Move`, and only after confirming that the previous test has finished or the user has released the GPU. After reserving, comment on the [GPU reservation Issue](https://github.com/lucaseddd/victory-rea/issues/17) (`reserved: R04-Davi-01`), and again on release (`released`). The Issue does not replace the local lock.

## 7. Consolidation

Only the consolidating AI (R00 or whoever the user designates) merges PRs into a build, runs the [automated test](harness/README.md) and publishes the score. See [docs/consolidation.md](docs/consolidation.md). An attempt that changes the runtime may run the same test and include the score in its PR, citing the SHA-256 of `Watch-Run.ps1`.

Changes to the test itself (launcher, watcher, score weights, patches) go in a separate PR with the `coordination` label.
