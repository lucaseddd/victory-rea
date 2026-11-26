# VICTORY_DSTORAGE_TRACE: the list of disk reads

Candidate 5. `VICTORY_DSTORAGE_TRACE=<file>` writes every DirectStorage read of the run as tab-separated `path<TAB>offset<TAB>bytes` lines. A code comment in the diff shows an example path; it is generalized here to `G:\<package file>`. The pipeline replays the previous runs' lists before opening the game (`Pre-Warm.ps1`), reading the same ranges in file order so Windows' file cache is warm. The trace contains file paths of the game's package, so it stays on the machine: only the aggregate pre-warm numbers go into a PR.

- **Apply after** patches 01–06, on the same base. Hunk line numbers follow that chain.
- License: GPL-3.0, like the rest of VIctory and the fork.
- To apply: copy each `diff` block to a `.patch` file, run `git apply --check`, then `git apply`.

## `crates/victory-hle/src/modules/dstorage.rs`

```diff
--- a/crates/victory-hle/src/modules/dstorage.rs
+++ b/crates/victory-hle/src/modules/dstorage.rs
@@ -1126,6 +1126,7 @@
     let file = &unsafe { &*request.source.cast::<Instance<File>>() }
         .state
         .file;
+    stats::trace(request.source as usize, request.offset, out.len() as u64);
     let started = std::time::Instant::now();
     let mut done = 0;
     let result = loop {
```

## `crates/victory-hle/src/modules/dstorage/stats.rs`

```diff
--- a/crates/victory-hle/src/modules/dstorage/stats.rs
+++ b/crates/victory-hle/src/modules/dstorage/stats.rs
@@ -27,6 +27,40 @@
 pub(super) fn on() -> bool {
     static ON: OnceLock<bool> = OnceLock::new();
     *ON.get_or_init(|| std::env::var_os("VICTORY_DSTORAGE_STATS").is_some_and(|v| v == "1"))
+}
+
+/// `VICTORY_DSTORAGE_TRACE=<file>`: every read from a file is appended to it
+/// as `path<TAB>offset<TAB>bytes` (the title's own path, as `G:\<package file>`).
+/// A loading reads the same ranges from the same save, so the list lets a
+/// tool read them ahead, in file order, into the system's file cache before
+/// the next launch (on a hard disk: one pass in order instead of thousands
+/// of scattered reads). Writing the list changes no read.
+pub(super) fn trace(source: usize, offset: u64, bytes: u64) {
+    use std::io::Write;
+    static PATH: OnceLock<Option<std::path::PathBuf>> = OnceLock::new();
+    static OUT: Mutex<Option<std::io::LineWriter<std::fs::File>>> = Mutex::new(None);
+    let Some(path) = PATH.get_or_init(|| std::env::var_os("VICTORY_DSTORAGE_TRACE").map(std::path::PathBuf::from)) else {
+        return;
+    };
+    let name = super::WALLS_FILES
+        .lock()
+        .unwrap_or_else(|e| e.into_inner())
+        .iter()
+        .find(|f| f.0 == source)
+        .map_or_else(|| "?".to_string(), |f| f.1.clone());
+    let mut out = OUT.lock().unwrap_or_else(|e| e.into_inner());
+    if out.is_none() {
+        match std::fs::OpenOptions::new().create(true).append(true).open(path) {
+            Ok(f) => *out = Some(std::io::LineWriter::new(f)),
+            Err(e) => {
+                tracing::warn!(error = %e, path = %path.display(), "dstorage: the read list cannot be written (VICTORY_DSTORAGE_TRACE)");
+                return;
+            }
+        }
+    }
+    if let Some(w) = out.as_mut() {
+        let _ = writeln!(w, "{name}\t{offset}\t{bytes}");
+    }
 }
 
 /// The most bytes one modelled joined read takes.
```

