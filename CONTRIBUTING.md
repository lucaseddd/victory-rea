# Contributing

This protocol carries the local `REA-COORD` board (atomic claims, status, journal, evidence and the GPU lock) over to GitHub. Read [POLITICA-DE-DADOS.md](POLITICA-DE-DADOS.md) (data policy) first.

## Equivalents

| Local `REA-COORD` board | GitHub |
|---|---|
| `TASKLIST.md` (R00–R15) | One Issue per task, using the **REA task** template |
| `claims\<ID>.json` (`File.Move` without overwrite) | Issue **assignee** + a `claim:` comment |
| `status\<ID>.md` | Issue body (Status section), updated only by the holder |
| `journal\<ID>\` | Issue comments, one per relevant step |
| `evidence\<ID>\<attempt>\` | A PR with `tentativas/<ID>/<attempt>/relatorio.md` (text only); raw data stays on the machine |
| `locks\gpu-capture.json` | Stays local. The pinned **GPU lock** Issue only mirrors the holder |
| `CONFLITOS.md` | `conflict` label + a comment on both tasks' Issues |
| `REA-INDICE.md` (edited only by R00) | `docs/indice.md`, edited only by R00 PRs |

## 1. Taking a task (claim)

1. Open the task's Issue. If it already has an assignee, **do not take it**. An old claim does not authorize taking over the work: only an explicit handover by the holder, or archiving confirmed by the user or by R00.
2. Assign the Issue to yourself and, in the same minute, comment:

   ```
   claim: R07-Vera-01
   build: <exe> sha256 <hash>
   scope: <one sentence>
   ```

3. Replace the `status:open` label with `status:in-progress`.

**Races.** GitHub has no atomic assignment like `File.Move`. If two AIs take the same Issue, the oldest `claim:` comment wins. The other one removes its own assignment and comments `claim withdrawn`.

**One account for several AIs.** If every AI uses the same GitHub account, the assignee only says the task is taken. Who holds it is in the `claim:` comment (AI name and attempt).

## 2. Working

- Stay in your label's area. Found something in another area? Comment on that area's Issue and do not edit its work.
- Record relevant steps as comments (the old `journal`).
- Keep the Status section of the Issue body current: status, progress, blocker, next step.
- Progress: 0% claimed · 25% artifacts checked · 50% first evidence interpreted · 75% analysis or capture done, verification pending · 100% verified and reproducible.

## 3. One PR per attempt

- Branch: `r07/vera-01` (task in lower case / name-attempt).
- File: `tentativas/R07/R07-Vera-01/relatorio.md`, starting from [tentativas/_modelo/relatorio.md](tentativas/_modelo/relatorio.md). You may add small CSVs **of aggregate numbers** and your own scripts (`.py`, `.ps1`).
- The PR uses the template and references the Issue with `Refs #<n>`. Use `Closes #<n>` only when the task reaches 100%.
- One attempt = one idea. For another hypothesis, open another attempt (`-02`).
- The `Test-RepoContent` check must pass.

## 4. Evidence tags

Every claim with a number carries one of these tags:

| Tag | Use |
|---|---|
| `[obs-local]` | Measured or checked by you on this machine, on this build (hash cited) |
| `[relatado]` (reported) | Comes from another report, PR or status. Cite the source |
| `[estimado]` (estimated) | Calculation, model or inference without direct measurement |

Missing evidence is written as **unavailable**. Do not fill it in with an estimate without the tag.

## 5. Comparable-results protocol

Every performance number states:

- build: exe and hash (SHA-256 or BLAKE3), and PDB GUID/age when available;
- scene and checkpoints (e.g. cutscene C1, first mission M1);
- effective profile (e.g. Controle or Candidato) and the variables that differ;
- resolution, scale, graphics preset and cache (cold or warm);
- metrics: rendered FPS, median, p95, % > 33.33 ms, hitches, typical and peak VRAM;
- a split of times when available: CPU preparation, waiting, GPU execution, readback, CPU wait, read and fence publication.

## 6. GPU

A capture needs the GPU to itself. The reservation is still `locks\gpu-capture.json` on the machine, with the same atomic `File.Move`, and only after confirming that the previous test has finished or the user has released the GPU. After reserving, comment on the **GPU lock** Issue (`reserved: R04-Davi-01`), and again on release (`released`). The Issue does not replace the local lock.

## 7. Consolidation

Only the consolidating AI (R00 or whoever the user designates) merges PRs into a build, runs the [automated test](harness/README.md) and publishes the score. See [docs/consolidacao.md](docs/consolidacao.md). An attempt that changes the runtime may run the same test and include the score in its PR, citing the SHA-256 of `Vigiar-Rodada.ps1`.

Changes to the test itself (launcher, watcher, score weights, patches) go in a separate PR with the `coordination` label.
