<!-- One PR per attempt. Text only: nothing from the game, no binary, raw log, capture or disassembly of the title. -->

## Attempt

- Issue: Refs #<n>  <!-- use Closes #<n> only when the task reaches 100% -->
- Task and attempt: R??-<Name>-<NN>
- Area (label): <readback | vram-mips | directstorage | present | shaders | image-regression | …>
- Report: `tentativas/R??/R??-<Name>-<NN>/relatorio.md`

## Build

- Executable and hash: <victory.exe sha256 …>
- PDB GUID/age: <{…} age n | unavailable>
- Build base: <fork commit, PRs and patches applied>

## Scene and profile

- Scene and checkpoints: <C1, M1 | static analysis>
- Effective profile: <Controle/Candidato> · variables that differ: <…>
- Resolution, scale, graphics, cache: <…> · <cold/warm>

## Metrics

| Metric | Before | After | Tag |
|---|---|---|---|
| Rendered FPS | | | |
| Median ms / p95 ms | | | |
| % > 33.33 ms | | | |
| Hitches | | | |
| Typical / peak VRAM MB | | | |
| Harness score (Vigiar-Rodada.ps1 sha256 …) | | | |

Write **unavailable** when there is no measurement.

## Checks

- [ ] Every number is tagged `[obs-local]`, `[relatado]` (reported) or `[estimado]` (estimated)
- [ ] The cited hashes were checked on this machine (`Get-FileHash`)
- [ ] `scripts/Test-RepoContent.ps1` passed locally
- [ ] Nothing from the game: no asset, executable, DLL, PDB, raw log, capture, video or disassembly of the title
- [ ] No personal data (real name, e-mail, path with a user name)
