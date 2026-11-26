# 6. Pitfalls

Mistakes that have happened, or nearly happened, in this project.

| Pitfall | How to avoid it |
|---|---|
| An address from one build applied to another | Hash and GUID/age on every claim; look the symbol up again |
| Whole-run average FPS | Split by draws/frame: menus ~10, 3D scenes > 1,000 |
| A historical log treated as a baseline | A run without an identified scene or exclusive GPU only gives orientation. Tag it `[relatado]` and say "outside the protocol" |
| An A/B that changes more than one thing | Read in the source what the variable enables. `QUEUE2=1` enables three mechanisms |
| A black cutscene taken as the "reference" | Compare against a reference recording; use black-frame detection |
| Slow loading blamed on the GPU | Enable `VICTORY_DSTORAGE_STATS`. On an HDD, the bottleneck was the disk |
| A smaller window to "speed things up" | It does not change disk reads. The real reduction comes from the Series S profile |
| `VICTORY_DISPLAY_MODE` to lower the resolution | The game ignores the reported mode (measured on the fork) |
| Series S with a black image | Patch 03 (two-plane composition) is missing |
| Launcher fails with "Access denied" | Reading firewall rules requires administrator rights. Run elevated; do not disable the check |
| PresentMon "access denied" | Administrator or the Performance Log Users group |
| Two chats on the same GPU | Local atomic lock; confirm no `victory` process is running |
| An "abandoned" old claim | Only an explicit handover by the holder or archiving confirmed by the user |
| An external drive that reports more capacity than it has | Do not store test data on it; writing past its real capacity corrupts data silently |
| A cold shader cache skewing FPS | Report cold/warm; reuse the cache only with an identical translator (hash) |
| Game material in a commit | Run `Test-RepoContent.ps1` before every PR. If something slips through, rewrite history |
