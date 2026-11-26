# VICTORY_DSTORAGE_STATS: DirectStorage counters

Candidate 2. Enabled with `VICTORY_DSTORAGE_STATS=1`. Every 5 s it logs requests per Submit, contiguity (`adjacent_pairs`/`joined_reads`), queue latency, and read, decode and destination time. The launcher enables it by default, and `Medir-Rodada.ps1` summarizes the `dstorage per Submit` lines.

- **Apply in order**, on top of `fxceless/victory-fork` at commit `f6a09d3b` with PR #45 (candidate 1). Hunk line numbers follow that chain.
- License: VIctory and the fork are GPL-3.0. This diff derives from that code and is under the same license.
- To apply: copy the `diff` block to `01-dstorage-stats.patch`, run `git apply --check 01-dstorage-stats.patch`, then `git apply 01-dstorage-stats.patch`.

## `crates/victory-hle/src/modules/dstorage.rs`

```diff
--- a/crates/victory-hle/src/modules/dstorage.rs
+++ b/crates/victory-hle/src/modules/dstorage.rs
@@ -26,6 +26,8 @@
 use std::sync::{Condvar, Mutex, MutexGuard, OnceLock};
 
 use victory_formats::bcpack::{self, Tables};
+
+mod stats;
 
 use super::xasync::{E_INVALIDARG, E_NOTIMPL, E_PENDING};
 use super::xgameruntime::{Guid, HRESULT, Methods, Object, S_OK, add_ref, missing, put};
@@ -584,6 +586,9 @@
         }
         lane.reads.pop_front();
         lane.running.insert(seq);
+        if stats::on() {
+            stats::started(id, seq);
+        }
         self.staged += staging;
         let size = u64::from(request.destination_size.max(request.source_size)).max(1);
         self.now = self.clock[class];
@@ -641,6 +646,7 @@
         if lane.reads.is_empty() {
             lane.clock = lane.clock.max(self.lane_now[class]);
         }
+        let ready_before = lane.reads.len();
         let mut commands = if explicit { std::mem::take(&mut lane.held) } else { Vec::new() };
         commands.append(&mut lane.unsubmitted);
         for command in commands {
@@ -660,6 +666,13 @@
                 Command::Status(status) => lane.statuses.push_back((seq, status)),
             }
         }
+        // Counters only (`VICTORY_DSTORAGE_STATS=1`): what this Submit made
+        // ready. The reads and their order are as above.
+        if stats::on() && lane.reads.len() > ready_before {
+            let fresh = lane.reads.range(ready_before..);
+            let ready = stats::batch(fresh.clone().map(|(_, r)| r), stats::join_cap());
+            stats::submitted(id, class, explicit, &ready, fresh.map(|&(seq, _)| seq));
+        }
         lane.flush();
     }
 }
@@ -733,6 +746,9 @@
         return;
     };
     lane.closed = true;
+    if stats::on() {
+        stats::closed(id);
+    }
     lane.unsubmitted.clear();
     lane.held.clear();
     lane.reads.clear();
@@ -956,6 +972,7 @@
     let tables = if bc != 0 { Some(bcpack_tables()?) } else { None };
     let source = read_source(request).map_err(|hr| fail(hr, "reading the source"))?;
     // The console's order: zlib first, then BCPack.
+    let decoding = std::time::Instant::now();
     let source = if bc != 0 && options & ZLIB != 0 {
         let mut packed = vec![0; request.intermediate_size as usize];
         let n = inflate(&source, &mut packed).map_err(|hr| fail(hr, "zlib"))?;
@@ -964,11 +981,19 @@
     } else {
         source
     };
-    into_destination(request, size, |out| match tables {
-        Some(tables) => bcpack::decode(bc, &source, out, tables)
-            .map(|()| out.len())
-            .map_err(|e| fail(INVALID_DATA, &e.to_string())),
-        None => inflate(&source, out).map_err(|hr| fail(hr, "zlib")),
+    let first_stage = decoding.elapsed();
+    into_destination(request, size, |out| {
+        let decoding = std::time::Instant::now();
+        let done = match tables {
+            Some(tables) => bcpack::decode(bc, &source, out, tables)
+                .map(|()| out.len())
+                .map_err(|e| fail(INVALID_DATA, &e.to_string())),
+            None => inflate(&source, out).map_err(|hr| fail(hr, "zlib")),
+        };
+        if stats::on() {
+            stats::stage(stats::DECODE, first_stage + decoding.elapsed());
+        }
+        done
     })?;
     tracing::trace!(
         options = format_args!("{options:#x}"),
@@ -1107,6 +1132,9 @@
         }
     };
     READING.fetch_add(started.elapsed().as_nanos() as u64, Ordering::Relaxed);
+    if stats::on() {
+        stats::stage(stats::READ, started.elapsed());
+    }
     result
 }
 
@@ -1116,6 +1144,29 @@
 /// physical pages are too when they are consecutive pages of one
 /// allocation, and otherwise go through a buffer.
 fn into_destination(
+    request: &Request,
+    len: usize,
+    fill: impl FnOnce(&mut [u8]) -> Result<usize, HRESULT>,
+) -> Result<(), HRESULT> {
+    if !stats::on() {
+        return into_destination_inner(request, len, fill);
+    }
+    // Counters only: the destination's own time is the whole less `fill`
+    // (which reads and/or decodes, counted by those stages).
+    let started = std::time::Instant::now();
+    let filling = std::cell::Cell::new(std::time::Duration::ZERO);
+    let result = into_destination_inner(request, len, |out| {
+        let t = std::time::Instant::now();
+        let r = fill(out);
+        filling.set(t.elapsed());
+        r
+    });
+    stats::stage(stats::DESTINATION, started.elapsed().saturating_sub(filling.get()));
+    result
+}
+
+/// [`into_destination`] itself.
+fn into_destination_inner(
     request: &Request,
     len: usize,
     fill: impl FnOnce(&mut [u8]) -> Result<usize, HRESULT>,
```

## `crates/victory-hle/src/modules/dstorage/stats.rs`

```diff
--- a/crates/victory-hle/src/modules/dstorage/stats.rs
+++ b/crates/victory-hle/src/modules/dstorage/stats.rs
@@ -0,0 +1,317 @@
+//! Counters only (`VICTORY_DSTORAGE_STATS=1`; off by default): what each
+//! Submit hands the workers, and where a request's time goes. Nothing here
+//! changes what is read, in which order, or when a status is written.
+//!
+//! Per Submit: the reads made ready (from files and from memory), their
+//! bytes, the pairs of reads of one file whose ranges touch exactly, and how
+//! many reads there would be if such ranges were read as one, up to
+//! `VICTORY_DSTORAGE_STATS_JOIN_KB` (128) a read. That last number is a
+//! model for deciding whether joining is worth doing on this disk; no read
+//! is joined. Per request: the time reading the file, decoding (zlib and/or
+//! BCPack), and getting the bytes into the destination (mapping the pages,
+//! the copy, telling the GPU side). Per read: the wait from its Submit to
+//! its start. Summed every 5 s into one info line.
+//!
+//! Local addition after the REA notes on DirectStorage on an HD
+//! (`rea-directstorage-hd`). File-cache hits and physical reads are not told
+//! apart: nothing here can see which a read was.
+
+use std::collections::HashMap;
+use std::sync::atomic::{AtomicU64, Ordering};
+use std::sync::{Mutex, OnceLock};
+use std::time::{Duration, Instant};
+
+use super::{MEMORY_SOURCE, Request};
+
+/// Whether the counters run.
+pub(super) fn on() -> bool {
+    static ON: OnceLock<bool> = OnceLock::new();
+    *ON.get_or_init(|| std::env::var_os("VICTORY_DSTORAGE_STATS").is_some_and(|v| v == "1"))
+}
+
+/// The most bytes one modelled joined read takes.
+pub(super) fn join_cap() -> u64 {
+    static BYTES: OnceLock<u64> = OnceLock::new();
+    *BYTES.get_or_init(|| {
+        std::env::var("VICTORY_DSTORAGE_STATS_JOIN_KB")
+            .ok()
+            .and_then(|v| v.trim().parse::<u64>().ok())
+            .map_or(128, |kb| kb.max(4))
+            << 10
+    })
+}
+
+/// What one Submit made ready.
+#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
+pub(super) struct Batch {
+    pub(super) reads: u64,
+    pub(super) memory_reads: u64,
+    pub(super) file_reads: u64,
+    pub(super) file_bytes: u64,
+    pub(super) memory_bytes: u64,
+    /// Files the file reads name.
+    pub(super) files: u64,
+    /// Pairs of reads of one file where one starts where the other ends.
+    pub(super) adjacent_pairs: u64,
+    /// The file reads there would be with exactly touching ranges of one
+    /// file joined, up to the cap a read.
+    pub(super) joined_reads: u64,
+}
+
+/// [`Batch`] of `reads` (one Submit of one queue), joining up to `cap`
+/// bytes a read in the model.
+pub(super) fn batch<'a>(reads: impl IntoIterator<Item = &'a Request>, cap: u64) -> Batch {
+    let mut b = Batch::default();
+    let mut by_file: HashMap<usize, Vec<(u64, u64)>> = HashMap::new();
+    for r in reads {
+        b.reads += 1;
+        let size = u64::from(r.source_size);
+        if r.options & MEMORY_SOURCE != 0 {
+            b.memory_reads += 1;
+            b.memory_bytes += size;
+            continue;
+        }
+        b.file_reads += 1;
+        b.file_bytes += size;
+        by_file.entry(r.source as usize).or_default().push((r.offset, size));
+    }
+    b.files = by_file.len() as u64;
+    for ranges in by_file.values_mut() {
+        ranges.sort_unstable();
+        // The modelled read being built: where it ends, its bytes.
+        let mut open: Option<(u64, u64)> = None;
+        for &(offset, size) in ranges.iter() {
+            if let Some((end, bytes)) = open
+                && offset == end
+            {
+                b.adjacent_pairs += 1;
+                if bytes + size <= cap {
+                    open = Some((offset + size, bytes + size));
+                    continue;
+                }
+            }
+            b.joined_reads += 1;
+            open = Some((offset + size, size));
+        }
+    }
+    b
+}
+
+/// Stages of a request: reading the file, decoding, the destination.
+pub(super) const READ: usize = 0;
+pub(super) const DECODE: usize = 1;
+pub(super) const DESTINATION: usize = 2;
+static STAGE_NS: [AtomicU64; 3] = [const { AtomicU64::new(0) }; 3];
+static STAGE_COUNT: [AtomicU64; 3] = [const { AtomicU64::new(0) }; 3];
+
+/// Adds `spent` to a stage.
+pub(super) fn stage(which: usize, spent: Duration) {
+    STAGE_NS[which].fetch_add(spent.as_nanos() as u64, Ordering::Relaxed);
+    STAGE_COUNT[which].fetch_add(1, Ordering::Relaxed);
+}
+
+/// The 5 s window the info line sums.
+#[derive(Default)]
+struct Window {
+    since: Option<Instant>,
+    submits: u64,
+    explicit: u64,
+    reads_by_class: [u64; 3],
+    sum: Batch,
+    /// Submits that made two or more file reads ready.
+    multi: u64,
+    /// When each submitted read (queue, sequence) was made ready.
+    queued: HashMap<(u64, u64), Instant>,
+    /// Waits from Submit to start, in microseconds.
+    waits: Vec<u64>,
+}
+
+static WINDOW: Mutex<Option<Window>> = Mutex::new(None);
+
+fn with_window(f: impl FnOnce(&mut Window)) {
+    let mut w = WINDOW.lock().unwrap_or_else(|e| e.into_inner());
+    let w = w.get_or_insert_with(Window::default);
+    w.since.get_or_insert_with(Instant::now);
+    f(w);
+}
+
+/// A Submit (`explicit` false: a half-full queue submitted itself) of queue
+/// `lane` of priority class `class` made `ready` ready, with these
+/// sequence numbers.
+pub(super) fn submitted(lane: u64, class: usize, explicit: bool, ready: &Batch, seqs: impl IntoIterator<Item = u64>) {
+    let now = Instant::now();
+    with_window(|w| {
+        w.submits += 1;
+        w.explicit += u64::from(explicit);
+        w.reads_by_class[class.min(2)] += ready.reads;
+        w.multi += u64::from(ready.file_reads >= 2);
+        let s = &mut w.sum;
+        s.reads += ready.reads;
+        s.memory_reads += ready.memory_reads;
+        s.file_reads += ready.file_reads;
+        s.file_bytes += ready.file_bytes;
+        s.memory_bytes += ready.memory_bytes;
+        s.files += ready.files;
+        s.adjacent_pairs += ready.adjacent_pairs;
+        s.joined_reads += ready.joined_reads;
+        for seq in seqs {
+            w.queued.insert((lane, seq), now);
+        }
+    });
+    report();
+}
+
+/// A worker started read `seq` of queue `lane`.
+pub(super) fn started(lane: u64, seq: u64) {
+    with_window(|w| {
+        if let Some(at) = w.queued.remove(&(lane, seq)) {
+            w.waits.push(at.elapsed().as_micros() as u64);
+        }
+    });
+}
+
+/// A queue closed: its reads not started never will be.
+pub(super) fn closed(lane: u64) {
+    with_window(|w| w.queued.retain(|&(l, _), _| l != lane));
+}
+
+/// The `p`th percentile (0-100) of sorted values.
+fn percentile(sorted: &[u64], p: usize) -> u64 {
+    if sorted.is_empty() {
+        return 0;
+    }
+    sorted[(sorted.len() - 1) * p / 100]
+}
+
+/// Every 5 s: the info line.
+pub(super) fn report() {
+    let mut guard = WINDOW.lock().unwrap_or_else(|e| e.into_inner());
+    let Some(w) = guard.as_mut() else {
+        return;
+    };
+    let Some(since) = w.since else {
+        return;
+    };
+    let elapsed = since.elapsed();
+    if elapsed.as_secs() < 5 {
+        return;
+    }
+    let mut waits = std::mem::take(&mut w.waits);
+    waits.sort_unstable();
+    let ns: Vec<u64> = STAGE_NS.iter().map(|s| s.swap(0, Ordering::Relaxed)).collect();
+    let n: Vec<u64> = STAGE_COUNT.iter().map(|s| s.swap(0, Ordering::Relaxed)).collect();
+    let s = w.sum;
+    tracing::info!(
+        "dstorage per Submit (VICTORY_DSTORAGE_STATS=1), last {:.1} s: {} submits ({} explicit, {} by a half-full queue), \
+         {} with two or more file reads; reads made ready: {} ({} from files, {:.1} MB, over {} file-submits; {} from memory, \
+         {:.1} MB); by class low/normal/high {}/{}/{}; exactly touching pairs of one file: {}; file reads if those were read as \
+         one up to {} KiB (a model, nothing is joined): {} of {}; time: reading files {:.1} ms in {}, decoding {:.1} ms in {}, \
+         destination (pages, copy, telling the GPU side) {:.1} ms in {}; wait from Submit to start p50 {} us, p95 {} us, \
+         max {} us over {} reads",
+        elapsed.as_secs_f64(),
+        w.submits,
+        w.explicit,
+        w.submits - w.explicit,
+        w.multi,
+        s.reads,
+        s.file_reads,
+        s.file_bytes as f64 / 1e6,
+        s.files,
+        s.memory_reads,
+        s.memory_bytes as f64 / 1e6,
+        w.reads_by_class[0],
+        w.reads_by_class[1],
+        w.reads_by_class[2],
+        s.adjacent_pairs,
+        join_cap() >> 10,
+        s.joined_reads,
+        s.file_reads,
+        ns[READ] as f64 / 1e6,
+        n[READ],
+        ns[DECODE] as f64 / 1e6,
+        n[DECODE],
+        ns[DESTINATION] as f64 / 1e6,
+        n[DESTINATION],
+        percentile(&waits, 50),
+        percentile(&waits, 95),
+        waits.last().copied().unwrap_or(0),
+        waits.len(),
+    );
+    let queued = std::mem::take(&mut w.queued);
+    *w = Window::default();
+    w.queued = queued;
+    w.since = Some(Instant::now());
+}
+
+#[cfg(test)]
+mod tests {
+    use super::*;
+
+    const KIB: u64 = 1024;
+
+    fn file_read(file: usize, offset: u64, size: u32) -> Request {
+        Request {
+            options: 0,
+            destination: std::ptr::null_mut(),
+            page_offset: 0,
+            destination_size: size,
+            source: file as *const std::ffi::c_void,
+            offset,
+            source_size: size,
+            intermediate_size: 0,
+            tag: 0,
+            name: std::ptr::null(),
+        }
+    }
+
+    /// The REA model's first case: four clusters of eight touching 8 KiB
+    /// reads, interleaved: 32 reads, 4 if joined.
+    #[test]
+    fn four_interleaved_clusters_join_to_four() {
+        let mut reads = Vec::new();
+        for i in 0..8u64 {
+            for c in 0..4u64 {
+                reads.push(file_read(1, c * 1024 * KIB + i * 8 * KIB, 8192));
+            }
+        }
+        let b = batch(&reads, 128 * KIB);
+        assert_eq!((b.file_reads, b.joined_reads, b.adjacent_pairs, b.file_bytes), (32, 4, 28, 262_144));
+    }
+
+    /// Scattered reads with gaps: nothing joins.
+    #[test]
+    fn scattered_reads_stay_apart() {
+        let reads: Vec<Request> = (0..32u64).map(|i| file_read(1, i * 16 * KIB, 8192)).collect();
+        let b = batch(&reads, 128 * KIB);
+        assert_eq!((b.joined_reads, b.adjacent_pairs), (32, 0));
+    }
+
+    /// Touching ranges of different files are not joined; memory sources
+    /// are counted apart.
+    #[test]
+    fn files_and_memory_are_kept_apart() {
+        let mut reads = vec![file_read(1, 0, 8192), file_read(2, 8192, 8192), file_read(3, 16384, 8192)];
+        let mut memory = file_read(4, 0, 4096);
+        memory.options = MEMORY_SOURCE;
+        reads.push(memory);
+        let b = batch(&reads, 128 * KIB);
+        assert_eq!((b.file_reads, b.files, b.joined_reads, b.adjacent_pairs), (3, 3, 3, 0));
+        assert_eq!((b.memory_reads, b.memory_bytes), (1, 4096));
+    }
+
+    /// The cap: seventeen touching 8 KiB reads make two reads of at most
+    /// 128 KiB.
+    #[test]
+    fn the_cap_bounds_a_joined_read() {
+        let reads: Vec<Request> = (0..17u64).map(|i| file_read(1, i * 8 * KIB, 8192)).collect();
+        let b = batch(&reads, 128 * KIB);
+        assert_eq!((b.joined_reads, b.adjacent_pairs, b.file_bytes), (2, 16, 139_264));
+    }
+
+    #[test]
+    fn percentiles() {
+        assert_eq!(percentile(&[], 50), 0);
+        let v: Vec<u64> = (1..=100).collect();
+        assert_eq!((percentile(&v, 50), percentile(&v, 95), percentile(&v, 100)), (50, 95, 100));
+    }
+}
```

