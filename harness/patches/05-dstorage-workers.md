# VICTORY_DSTORAGE_WORKERS: simultaneous disk reads

Candidate 4. `VICTORY_DSTORAGE_WORKERS=1-64` sets how many DirectStorage reads run at once. The default is still one worker per core. Run-Version.ps1's `-DiskWorkers` uses this patch. Optional for the score.

- **Apply in order**, on top of `fxceless/victory-fork` at commit `f6a09d3b` with PR #45 (candidate 1). Hunk line numbers follow that chain.
- License: VIctory and the fork are GPL-3.0. This diff derives from that code and is under the same license.
- To apply: copy the `diff` block to `05-dstorage-workers.patch`, run `git apply --check 05-dstorage-workers.patch`, then `git apply 05-dstorage-workers.patch`.

## `crates/victory-hle/src/modules/dstorage.rs`

```diff
--- a/crates/victory-hle/src/modules/dstorage.rs
+++ b/crates/victory-hle/src/modules/dstorage.rs
@@ -427,7 +427,14 @@
         })
         .as_ref()?;
     STARTED.call_once(|| {
-        let workers = std::thread::available_parallelism().map_or(4, |n| n.get());
+        // `VICTORY_DSTORAGE_WORKERS` (1-64): how many read at once. One per
+        // core by default; on a hard disk the reads are small and scattered
+        // (`VICTORY_DSTORAGE_STATS`), and fewer at once may seek less.
+        let workers = std::env::var("VICTORY_DSTORAGE_WORKERS")
+            .ok()
+            .and_then(|v| v.trim().parse::<usize>().ok())
+            .map(|n| n.clamp(1, 64))
+            .unwrap_or_else(|| std::thread::available_parallelism().map_or(4, |n| n.get()));
         let started = (0..workers)
             .filter(|i| {
                 std::thread::Builder::new()
```

