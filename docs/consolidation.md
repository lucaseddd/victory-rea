# Consolidation and score

Every so often, a stronger AI (R00, or the one the user designates) closes a cycle.

## Cycle

1. **Read.** Review the open PRs and the ones merged since the last cycle. Check:
   - the hashes;
   - the `[observed]`/`[reported]`/`[estimated]` tags;
   - that the numbers follow the comparable-results protocol.
2. **Decide.** Choose the changes for the next candidate. Use one isolated change per candidate when the goal is to attribute a gain (R14).
3. **Build locally.** Build the candidate in its own folder, outside the repository. Record only:
   - the exe and its hash;
   - the PDB GUID/age;
   - the `VICTORY_*` variables that changed.
4. **Measure.** Reserve the GPU (local lock) and run `harness/Pipeline.ps1` (or `Run-Version.ps1` on a built version) with the `quick` profile, plus the `series-x` reference. Run each once cold and once warm. The watcher computes the score, and the FPS-drop check compares the warm run with the previous version.
5. **Publish.** Open a PR with `consolidation/<YYYY-MM-DD>-cand<N>.md` and update `docs/index.md`. Open Issues for new regressions (label `image-regression`).

## Score

The score comes from the automated pipeline ([harness/](../harness/README.md#score-0100)): progress 25, speed 20, loading 20, stability 15, shaders 10, image 10. It is computed on the local machine; only the components, milestones, total, drop-check findings and scoreboard rows go into the repository.

The consolidation report cites the SHA-256 of `Watch-Run.ps1`, so scores from different cycles stay comparable. Alongside the score, also publish:

- the progress of Issues R00–R15;
- typical and peak VRAM.

These do not count toward the score, but they explain it.

## Report template

```markdown
# Consolidation <date> · candidate <N>

- Build: <exe> sha256 <hash> · PDB GUID <guid> age <n>
- Base: candidate <N-1> + PRs #<a>, #<b>
- Watcher (score): Watch-Run.ps1 sha256 <script hash>
- Scenes: C1 (cutscene), M1 (first mission) · cold and warm cache

| Scene | Cache | FPS | Median ms | p95 ms | % > 33.33 ms | PSO wait p95 ms | Image | Peak VRAM MB |
|---|---|---|---|---|---|---|---|---|

Score: <total> (progress <a> · speed <b> · loading <c> · stability <d> · shaders <e> · image <f>) [observed]
Drop check vs <previous version>: <OK | REGRESSION> — <findings>

<scoreboard rows from scoreboard.md for the versions in this cycle>
```
