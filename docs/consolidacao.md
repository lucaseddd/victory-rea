# Consolidation and score

Every so often, a stronger AI (R00, or the one the user designates) closes a cycle.

## Cycle

1. **Read.** Review the open PRs and the ones merged since the last cycle. Check:
   - the hashes;
   - the `[obs-local]`/`[relatado]`/`[estimado]` tags;
   - that the numbers follow the comparable-results protocol.
2. **Decide.** Choose the changes for the next candidate. Use one isolated change per candidate when the goal is to attribute a gain (R14).
3. **Build locally.** Build the candidate in its own folder, outside the repository. Record only:
   - the exe and its hash;
   - the PDB GUID/age;
   - the `VICTORY_*` variables that changed.
4. **Measure.** Reserve the GPU (local lock) and run `harness/Iniciar-Rodada.ps1 -Rapido`, plus the Series X reference, with a cold and a warm cache. The watcher computes the score when the game closes.
5. **Publish.** Open a PR with `consolidacao/<YYYY-MM-DD>-cand<N>.md` and update `docs/indice.md`. Open Issues for new regressions (label `image-regression`).

## Score

The score comes from the automated test ([harness/](../harness/README.md#score)): progress 30, speed 25, loading 20, shaders 15, image 10. It is computed on the local machine; only the components, milestones and total go into the repository.

The consolidation report cites the SHA-256 of `Vigiar-Rodada.ps1`, so scores from different cycles stay comparable. Alongside the score, also publish:

- the progress of Issues R00–R15;
- typical and peak VRAM.

These do not count toward the score, but they explain it.

## Report template

```markdown
# Consolidation <date> · candidate <N>

- Build: <exe> sha256 <hash> · PDB GUID <guid> age <n>
- Base: candidate <N-1> + PRs #<a>, #<b>
- Watcher (score): Vigiar-Rodada.ps1 sha256 <script hash>
- Scenes: C1 (cutscene), M1 (first mission) · cold and warm cache

| Scene | Cache | FPS | Median ms | p95 ms | % > 33.33 ms | PSO wait p95 ms | Image | Peak VRAM MB |
|---|---|---|---|---|---|---|---|---|

Score: <total> (progress <a> · speed <b> · loading <c> · shaders <d> · image <e>) [obs-local]
```
