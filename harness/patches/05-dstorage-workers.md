# VICTORY_DSTORAGE_WORKERS: leituras simultâneas no disco

Candidata 4. `VICTORY_DSTORAGE_WORKERS=1-64` define quantas leituras do DirectStorage correm ao mesmo tempo. O padrão continua um worker por núcleo. O `-DiscoWorkers` do launcher usa esse patch. É opcional para o score.

- **Aplicar em ordem**, sobre `fxceless/victory-fork` no commit `f6a09d3b` com o PR #45 (candidata 1). Os números de linha dos hunks seguem essa cadeia.
- Licença: o VIctory e o fork são GPL-3.0. Este diff é derivado desse código e segue a mesma licença.
- Para aplicar: copie o bloco `diff` para `05-dstorage-workers.patch` e rode `git apply --check 05-dstorage-workers.patch`, depois `git apply 05-dstorage-workers.patch`.

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

