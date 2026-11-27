# R27 · source changes of the reported build

Base commit: `2954325320735fa8b56a15e7f3e9654965e3462e` (VI-BR-PORT). Apply from the repository root with `git apply` after copying the block below into a `.diff` file. Only VIctory source (open source) is changed; nothing from the title is included.

```diff
diff --git a/apps/victory/src/main.rs b/apps/victory/src/main.rs
index 3b047e9..cbd6412 100644
--- a/apps/victory/src/main.rs
+++ b/apps/victory/src/main.rs
@@ -282,3 +282,18 @@ pub(crate) fn default_paths(paths: Vec<PathBuf>) -> Result<Vec<PathBuf>> {
     );
     Ok(all)
 }
+
+// Local change carried from fxceless-988aa416-test (not upstream): the D3D12
+// Agility SDK 1.620.2 runtime in .\D3D12\ beside victory.exe, exported with
+// /EXPORT link arguments (see BUILD-CANDIDATA.md).
+#[unsafe(no_mangle)]
+pub static D3D12SDKVersion: u32 = 620;
+
+#[repr(transparent)]
+pub struct SdkPath(*const u8);
+
+// The pointer permanently refers to immutable static bytes.
+unsafe impl Sync for SdkPath {}
+
+#[unsafe(no_mangle)]
+pub static D3D12SDKPath: SdkPath = SdkPath(c".\\D3D12\\".as_ptr().cast());
\ No newline at end of file
diff --git a/apps/victory/src/run.rs b/apps/victory/src/run.rs
index c8f3571..b551ffb 100644
--- a/apps/victory/src/run.rs
+++ b/apps/victory/src/run.rs
@@ -213,6 +213,7 @@ fn diagnostics(image: &victory_loader::LoadedImage, cfg: &victory_core::Config)
     victory_loader::dump_stacks_on_schedule();
     victory_loader::profile_on_schedule(victory_hle::frame_phase);
     victory_hle::modules::audio::capture::start();
+    victory_hle::modules::audio::mute::start();
     watch(image.base(), image.info().size_of_image as usize);
     poke(image.base(), image.info().size_of_image as usize);
     // Debugging aid: `VICTORY_CRASH_SAVE=<rva>:<len>,...` (hex) writes those
diff --git a/crates/victory-formats/src/bcpack.rs b/crates/victory-formats/src/bcpack.rs
index c8d3537..11dada0 100644
--- a/crates/victory-formats/src/bcpack.rs
+++ b/crates/victory-formats/src/bcpack.rs
@@ -744,10 +744,19 @@ fn pbits(mode: u16) -> bool {
     matches!(mode, 0 | 1 | 3 | 6 | 7)
 }
 
+/// Channel rotation bits; only BC7 modes 4 and 5 have a rotation field.
+fn rotation(ctrl: u16) -> usize {
+    if matches!(ctrl & 7, 4 | 5) {
+        usize::from(ctrl >> 3 & 3)
+    } else {
+        0
+    }
+}
+
 /// Channel precisions: the p-bit is red's lowest bit; rotation swaps alpha
 /// with the rotated channel.
 fn bc7_precision(ctrl: u16) -> [u8; 4] {
-    let (mode, rot) = (ctrl & 7, usize::from(ctrl >> 3 & 3));
+    let (mode, rot) = (ctrl & 7, rotation(ctrl));
     let mut p = BC7_BITS[usize::from(mode)];
     if rot != 0 {
         p.swap(3, rot - 1);
@@ -852,7 +861,7 @@ fn bc7_pack(ep: &Bc7Ep, ix: &Bc7Ix, prec: [u8; 4], out: &mut [u8]) {
     let mode = ctrl & 7;
     let subsets = usize::from((ctrl & 0xff) >> 6);
     let part = usize::from(ctrl >> 8 & 63);
-    let rot = usize::from(ctrl >> 3 & 3);
+    let rot = rotation(ctrl);
     let mut w = Bits::default();
     w.put(1 << mode, u32::from(mode) + 1);
     match mode {
@@ -1341,6 +1350,102 @@ mod tests {
         assert_eq!(dst, w.v.to_le_bytes());
     }
 
+    #[test]
+    fn bc7_rotation_applies_only_to_modes_4_and_5() {
+        const BC7_WIDTHS: [u8; 16] = [3, 3, 7, 7, 7, 7, 7, 6, 6, 4, 5, 7, 7, 7, 7, 4];
+        const CTRL7_OFFSET: usize = MODELS * BUCKETS * 2 + 256 + 64 + 256 + 64 + 64;
+        let tables_for = |ctrl: u16| {
+            let mut raw = tables();
+            raw[CTRL7_OFFSET..CTRL7_OFFSET + 2].copy_from_slice(&ctrl.to_le_bytes());
+            let t = Tables::parse(&raw).unwrap();
+            assert_eq!(t.ctrl7[0], ctrl);
+            t
+        };
+
+        let mut record = vec![0u8; 32];
+        for (i, &val) in [11, 23, 5, 19, 13, 29, 7, 17, 3, 25, 9, 21, 15, 31, 1, 12]
+            .iter()
+            .enumerate()
+        {
+            record[4 + i] = zigzag(val);
+        }
+        record[20] = zigzag(6);
+        record[21] = zigzag(14);
+
+        // Modes without a BC7 rotation field must ignore ctrl bits 4:3 instead of
+        // panicking on shift overflow (modes 0/1/3 with rot=1) or corrupting channels.
+        for (mode, subsets) in [(0u16, 3u16), (1, 2), (2, 3), (3, 2), (6, 1), (7, 2)] {
+            let base_ctrl = (subsets << 6) | mode;
+            let base_tables = tables_for(base_ctrl);
+            let base_src = stream(&base_tables, &BC7_WIDTHS, 2, std::slice::from_ref(&record));
+            let mut want = [0u8; 16];
+            decode(7, &base_src, &mut want, &base_tables).unwrap();
+
+            for rot in 1..=3u16 {
+                let ctrl = base_ctrl | (rot << 3);
+                let t = tables_for(ctrl);
+                let src = stream(&t, &BC7_WIDTHS, 2, std::slice::from_ref(&record));
+                let mut got = [0u8; 16];
+                decode(7, &src, &mut got, &t).unwrap();
+                assert_eq!(got, want, "mode {mode} rot {rot}");
+                assert_eq!(
+                    bc7_precision(ctrl),
+                    bc7_precision(base_ctrl),
+                    "mode {mode} rot {rot}"
+                );
+            }
+        }
+
+        // Modes 4 and 5 do have a 2-bit rotation field: rotation swaps alpha with channel rot-1.
+        for (mode, base_bits) in [(4u16, [5u8, 5, 5, 6]), (5u16, [7u8, 7, 7, 8])] {
+            for rot in 1..=3usize {
+                let ctrl = (1 << 6) | ((rot as u16) << 3) | mode;
+                let mut expected_prec = base_bits;
+                expected_prec.swap(3, rot - 1);
+                assert_eq!(bc7_precision(ctrl), expected_prec, "mode {mode} rot {rot}");
+            }
+
+            // Decode mode 4/5 with rot=1 (swap R and A) and check the packed BC7 block.
+            let ctrl = (1 << 6) | (1 << 3) | mode;
+            let t = tables_for(ctrl);
+            let mut s = vec![0u8; 32];
+            s[4] = zigzag(0x21); // stored R0 (holds alpha precision after rot=1)
+            s[5] = zigzag(0x12); // stored R1
+            s[6] = zigzag(0x05); // stored G0
+            s[7] = zigzag(0x06); // stored G1
+            s[8] = zigzag(0x09); // stored B0
+            s[9] = zigzag(0x0a); // stored B1
+            s[10] = zigzag(0x0d); // stored A0 (holds color precision after rot=1)
+            s[11] = zigzag(0x0e); // stored A1
+            let src = stream(&t, &BC7_WIDTHS, 2, &[s]);
+            let mut dst = [0u8; 16];
+            decode(7, &src, &mut dst, &t).unwrap();
+
+            let color_bits = u32::from(base_bits[0]);
+            let alpha_bits = u32::from(base_bits[3]);
+            let mut w = Bits::default();
+            w.put(1 << mode, u32::from(mode) + 1);
+            w.put(1, 2); // rotation = 1
+            if mode == 4 {
+                w.put(0, 1); // indexSelectionBit = 0
+            }
+            // Endpoint order after rot=1 swaps indices 3 and 0: [3 (R), 1 (G), 2 (B), 0 (A)].
+            for (v, n) in [
+                (0x0d, color_bits),
+                (0x0e, color_bits),
+                (0x05, color_bits),
+                (0x06, color_bits),
+                (0x09, color_bits),
+                (0x0a, color_bits),
+                (0x21, alpha_bits),
+                (0x12, alpha_bits),
+            ] {
+                w.put(v, n);
+            }
+            assert_eq!(dst, w.v.to_le_bytes(), "mode {mode} rot 1");
+        }
+    }
+
     #[test]
     fn malformed_input_is_an_error() {
         let t = Tables::parse(&tables()).unwrap();
diff --git a/crates/victory-gpu/src/ambient.rs b/crates/victory-gpu/src/ambient.rs
index 174ce26..5e67a4b 100644
--- a/crates/victory-gpu/src/ambient.rs
+++ b/crates/victory-gpu/src/ambient.rs
@@ -612,6 +612,12 @@ void clear_air(uint3 at : SV_DispatchThreadID) {
     // (`room`: as much as the screen is inside.)
     if (air_hold > 0.0) cap /= gain_whole(cells[CELLS]);
     float3 c = scattered[at];
+    // A non-finite froxel contaminates the full ray that crosses it.
+    // The integer test also works when the HLSL compiler assumes finite floats.
+    if (any((asuint(c) & 0x7f800000u) == 0x7f800000u)) {
+        scattered[at] = float3(0.0, 0.0, 0.0);
+        return;
+    }
     float has = dot(c, LUMA);
     // (VICTORY_AMBIENT_OUTSIDE) As much as the screen is inside: none on a
     // night street, whose lamps light its fog.
diff --git a/crates/victory-gpu/src/host.rs b/crates/victory-gpu/src/host.rs
index f9a3d36..467fb76 100644
--- a/crates/victory-gpu/src/host.rs
+++ b/crates/victory-gpu/src/host.rs
@@ -9178,7 +9178,12 @@ impl Batch {
         let started = std::time::Instant::now();
         if self.fills.len() < FEW {
             for (dst, src, len) in self.fills.drain(..) {
-                copy_mapped(dst as *mut u8, src as *const u8, len, false);
+                let (dst, src) = (dst as *mut u8, src as *const u8);
+                if len >= WIDE_UPLOAD_MIN && wide_upload_on() {
+                    copy_upload_pieces(dst, src, len);
+                } else {
+                    copy_mapped(dst, src, len, false);
+                }
             }
         } else {
             let fills = std::mem::take(&mut self.fills);
@@ -9301,6 +9306,38 @@ impl Batch {
     }
 }
 
+/// Parallel staging for large uploads (AnyXboxX c9c9a642). Only use the
+/// shared worker pool at the batch boundary where fills already use it.
+/// Other copy_mapped callers can hold the texture thread's read buffer
+/// while calling it, and the pool can run another texture job on this thread.
+const WIDE_UPLOAD_MIN: usize = 8 << 20;
+const WIDE_UPLOAD_PIECE: usize = 2 << 20;
+
+fn wide_upload_on() -> bool {
+    static ON: OnceLock<bool> = OnceLock::new();
+    *ON.get_or_init(|| std::env::var_os("VICTORY_WIDE_COPY").is_some_and(|v| v == "1"))
+}
+
+#[cfg(test)]
+#[test]
+fn staged_upload_pieces_copy_the_tail() {
+    let size = WIDE_UPLOAD_MIN + 4097;
+    let src: Vec<u8> = (0..size).map(|i| (i.wrapping_mul(131) ^ (i >> 20)) as u8).collect();
+    let mut dst = vec![0; size];
+    copy_upload_pieces(dst.as_mut_ptr(), src.as_ptr(), size);
+    assert!(src == dst, "parallel upload changed bytes");
+}
+
+fn copy_upload_pieces(dst: *mut u8, src: *const u8, len: usize) {
+    let (dst, src) = (dst as usize, src as usize);
+    let jobs = (0..len).step_by(WIDE_UPLOAD_PIECE).map(|offset| {
+        let size = (len - offset).min(WIDE_UPLOAD_PIECE);
+        Box::new(move || copy_mapped((dst + offset) as *mut u8, (src + offset) as *const u8, size, false))
+            as Box<dyn FnOnce() + Send>
+    }).collect();
+    crate::shadow::wide_run(jobs);
+}
+
 /// Copies title memory at submission. The ranges were checked against their
 /// resources when recorded, but the title may since have unmapped pages of
 /// them (tiled memory, page mappings), which read as zeros here; a title
diff --git a/crates/victory-gpu/src/pipeline/make.rs b/crates/victory-gpu/src/pipeline/make.rs
index adb3dd8..0487e16 100644
--- a/crates/victory-gpu/src/pipeline/make.rs
+++ b/crates/victory-gpu/src/pipeline/make.rs
@@ -208,6 +208,16 @@ pub(crate) fn ready(p: &Arc<Pending>) -> Option<&HostPipeline> {
     }
     if p.made.get().is_none() {
         start(p, REQUESTED);
+        static COMPUTE_WAITS: OnceLock<bool> = OnceLock::new();
+        let wait_for_compute = *COMPUTE_WAITS.get_or_init(|| {
+            std::env::var_os("VICTORY_PIPELINE_COMPUTE_WAIT").is_some_and(|value| value == "1")
+        });
+        // Some compute dispatches initialize a resource only once. Preserve
+        // them on a cold cache, as in fxceless #1312.
+        if p.graphics.is_none() && wait_for_compute {
+            p.make();
+            return p.made.get()?.as_ref();
+        }
         let frame = crate::frame::current();
         let first = match p.waited_frame.compare_exchange(
             u64::MAX,
diff --git a/crates/victory-gpu/src/pool.rs b/crates/victory-gpu/src/pool.rs
index 4d6a92d..f3cdec1 100644
--- a/crates/victory-gpu/src/pool.rs
+++ b/crates/victory-gpu/src/pool.rs
@@ -42,7 +42,17 @@ static SPARES: AtomicUsize = AtomicUsize::new(SPARE);
 /// [`SPARE_KEPT`] below 85 % ([`crate::host::keep_freed`]), else [`SPARE`].
 /// Asked once a second.
 pub(crate) fn room(memory: Option<[u64; 4]>) {
-    SPARES.store(spares(memory, crate::host::keep_freed()), Ordering::Relaxed);
+    // Small GPUs must not retain a large inventory of empty 64 MiB heaps
+    // during the transition from the menu into the world.
+    static LIMIT: std::sync::OnceLock<usize> = std::sync::OnceLock::new();
+    let limit = *LIMIT.get_or_init(|| {
+        std::env::var("VICTORY_TEXTURE_SPARE_BLOCKS")
+            .ok()
+            .and_then(|value| value.trim().parse::<usize>().ok())
+            .unwrap_or(SPARE_KEPT)
+            .clamp(SPARE, SPARE_KEPT)
+    });
+    SPARES.store(spares(memory, crate::host::keep_freed()).min(limit), Ordering::Relaxed);
 }
 
 fn spares(memory: Option<[u64; 4]>, keep: bool) -> usize {
diff --git a/crates/victory-gpu/src/tiles.rs b/crates/victory-gpu/src/tiles.rs
index 6d3c3d8..8d9100e 100644
--- a/crates/victory-gpu/src/tiles.rs
+++ b/crates/victory-gpu/src/tiles.rs
@@ -323,6 +323,8 @@ impl Tiled {
         STATS[0].fetch_add(1, Ordering::Relaxed);
         STATS[1].fetch_add(full, Ordering::Relaxed);
         STATS[4].fetch_add(1, Ordering::Relaxed);
+        BLANK[0].fetch_add(1, Ordering::Relaxed);
+        BLANK[1].fetch_add(full, Ordering::Relaxed);
         Some(Tiled {
             given: Mutex::new(Given {
                 levels: vec![false; standard.len()],
@@ -344,13 +346,11 @@ impl Tiled {
     /// from its staging buffer, of which `held` are the title's now (the
     /// others are zeros there): tiles for the held ones that have none.
     /// `room`: whether the card has room for more host copies
-    /// (`resource.rs` `room`). Without room no held level gets tiles: the
+    /// (`resource.rs` `room`). Without room no held level gets tiles unless
+    /// `VICTORY_TILES_SMALL_WHEN_FULL_MB` allows the smallest held levels: the
     /// list still brings the levels that have theirs up to date (which
     /// takes none of the card's memory), and its copies into the others go
-    /// nowhere. (An upload of a host copy that exists passes the full
-    /// card's gate in `draw.rs` on the ground that it takes no memory;
-    /// with tiles given here regardless, the line would not bound these
-    /// textures.)
+    /// nowhere.
     /// Returns whether the first level a view may show changed, and
     /// whether a level named is still without tiles (no room, or no heap
     /// could be had): the caller has the upload recorded again later, or
@@ -376,9 +376,21 @@ impl Tiled {
         self.held.store(held, Ordering::Relaxed);
         let card = self.card.load(Ordering::Relaxed);
         let named = held | card;
-        // The levels the card itself writes are few and are not kept
-        // waiting: a write of the card's into no memory is lost.
-        let changed = self.give_locked(&mut given, queue, device, texture, named, if room { named } else { card });
+        // On a full card, with `VICTORY_TILES_SMALL_WHEN_FULL_MB`, the smallest
+        // held levels still get tiles so textures show small mips instead of black
+        // (after `fxceless/victory-fork` f6a09d3ba4 / 0a40a00a6; default 0 = off).
+        let small = if room { 0 } else { self.small_levels(held) };
+        if small != 0 {
+            BLANK[2].fetch_add(u64::from(small.count_ones()), Ordering::Relaxed);
+        }
+        let changed = self.give_locked(
+            &mut given,
+            queue,
+            device,
+            texture,
+            named,
+            if room { named } else { card | small },
+        );
         let missing = self.without_locked(&given, named) != 0;
         (changed, missing)
     }
@@ -430,6 +442,33 @@ impl Tiled {
         changed
     }
 
+    fn small_levels(&self, held: u32) -> u32 {
+        let cap = small_when_full_mb() << 20;
+        if cap == 0 || STATS[2].load(Ordering::Relaxed) >= cap {
+            return 0;
+        }
+        let first_packed = self.standard.len() as u32;
+        let mut bits = 0u32;
+        let mut tiles = 0u32;
+        if self.packed > 0 {
+            let packed_bits = self.every_level() & !((1u32 << first_packed) - 1);
+            if held & packed_bits == 0 {
+                return 0;
+            }
+            bits |= packed_bits;
+            tiles += self.packed;
+        }
+        for level in (0..first_packed).rev() {
+            let tiles_here = self.standard[level as usize];
+            if held & (1 << level) == 0 || tiles + tiles_here > SMALL_TILES {
+                break;
+            }
+            tiles += tiles_here;
+            bits |= 1 << level;
+        }
+        if tiles > SMALL_TILES { 0 } else { bits }
+    }
+
     /// The bits of the levels that get their tiles with level `level`:
     /// itself, or every level the card packs together if it is one of them.
     pub(crate) fn with_level(&self, level: u32) -> u32 {
@@ -587,7 +626,15 @@ impl Tiled {
             }
         };
         let shown = (0..self.levels).find(|&level| has(level) && with_tiles(level)).unwrap_or(u32::MAX);
-        self.shown.swap(shown, Ordering::Relaxed) != shown
+        let old = self.shown.swap(shown, Ordering::Relaxed);
+        if old == u32::MAX && shown != u32::MAX {
+            BLANK[0].fetch_sub(1, Ordering::Relaxed);
+            BLANK[1].fetch_sub(self.full, Ordering::Relaxed);
+        } else if old != u32::MAX && shown == u32::MAX {
+            BLANK[0].fetch_add(1, Ordering::Relaxed);
+            BLANK[1].fetch_add(self.full, Ordering::Relaxed);
+        }
+        old != shown
     }
 
     /// The first level a view of the texture may show; `None` while no
@@ -627,6 +674,21 @@ impl Tiled {
     }
 }
 
+/// Textures alive with no level shown, their full bytes, and small levels given
+/// tiles on a full card (`VICTORY_TILES_SMALL_WHEN_FULL_MB`, default 0 = off).
+pub(crate) static BLANK: [AtomicU64; 3] = [const { AtomicU64::new(0) }; 3];
+const SMALL_TILES: u32 = 16;
+
+fn small_when_full_mb() -> u64 {
+    static MB: std::sync::OnceLock<u64> = std::sync::OnceLock::new();
+    *MB.get_or_init(|| {
+        std::env::var("VICTORY_TILES_SMALL_WHEN_FULL_MB")
+            .ok()
+            .and_then(|v| v.trim().parse::<u64>().ok())
+            .map_or(0, |mb| mb.min(1024))
+    })
+}
+
 impl Drop for Tiled {
     fn drop(&mut self) {
         let given = self.given.get_mut().unwrap_or_else(|e| e.into_inner());
@@ -642,6 +704,10 @@ impl Drop for Tiled {
         STATS[0].fetch_sub(1, Ordering::Relaxed);
         STATS[1].fetch_sub(self.full, Ordering::Relaxed);
         STATS[2].fetch_sub(bytes, Ordering::Relaxed);
+        if *self.shown.get_mut() == u32::MAX {
+            BLANK[0].fetch_sub(1, Ordering::Relaxed);
+            BLANK[1].fetch_sub(self.full, Ordering::Relaxed);
+        }
     }
 }
 
@@ -713,6 +779,16 @@ pub(crate) fn status() {
         s[9],
         s[10],
     );
+    let blank: Vec<u64> = BLANK.iter().map(|b| b.load(Ordering::Relaxed)).collect();
+    tracing::info!(
+        "textures with levels on demand that show no level now: {} of {} alive ({} MB full); \
+         small levels given tiles on a full card since start (VICTORY_TILES_SMALL_WHEN_FULL_MB={}): {}",
+        blank[0],
+        s[0],
+        blank[1] >> 20,
+        small_when_full_mb(),
+        blank[2],
+    );
 }
 
 /// On the card, without the title: what levels on demand relies on, with
diff --git a/crates/victory-hle/src/modules/audio.rs b/crates/victory-hle/src/modules/audio.rs
index 8da3346..66bae5c 100644
--- a/crates/victory-hle/src/modules/audio.rs
+++ b/crates/victory-hle/src/modules/audio.rs
@@ -28,6 +28,8 @@ use crate::{HleModule, hle_export};
 
 #[cfg(all(windows, feature = "diagnostics"))]
 pub mod capture;
+#[cfg(windows)]
+pub mod mute;
 
 const E_FAIL: HRESULT = 0x8000_4005_u32 as i32;
 const E_OUTOFMEMORY: HRESULT = 0x8007_000E_u32 as i32;
diff --git a/crates/victory-hle/src/modules/gameinput.rs b/crates/victory-hle/src/modules/gameinput.rs
index ef38e43..d1bdc44 100644
--- a/crates/victory-hle/src/modules/gameinput.rs
+++ b/crates/victory-hle/src/modules/gameinput.rs
@@ -111,6 +111,10 @@ trait Source: Send {
     fn pad(&mut self, slot: usize) -> Option<PadState>;
     /// Keys held down; none while the title's window lacks focus.
     fn keys(&mut self) -> Vec<KeyState>;
+    /// Mouse input for the PC layout, or none without window focus.
+    fn pc_mouse(&mut self, _enabled: bool, _keys: &[KeyState]) -> Option<PcMouse> {
+        None
+    }
     /// Motor speeds: low frequency (left), high frequency (right).
     fn rumble(&mut self, slot: usize, low: u16, high: u16);
 }
@@ -152,6 +156,104 @@ fn merged(a: PadState, b: PadState) -> PadState {
     }
 }
 
+/// Mouse deltas from one host poll, plus buttons while look is captured.
+#[derive(Default)]
+struct PcMouse {
+    x: f32,
+    y: f32,
+    aim: bool,
+    fire: bool,
+    middle: bool,
+}
+
+fn pc_layout() -> bool {
+    static ENABLED: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
+    *ENABLED.get_or_init(|| std::env::var_os("VICTORY_KBM_GTA").is_some_and(|value| value == "1"))
+}
+
+fn key_held(keys: &[KeyState], vk: u8) -> bool {
+    keys.iter().any(|key| key.virtual_key == vk)
+}
+
+fn bit_value(value: bool) -> f32 {
+    if value { 1.0 } else { 0.0 }
+}
+
+fn pc_pad(keys: &[KeyState], mouse: &PcMouse) -> PadState {
+    let on = |vk| key_held(keys, vk);
+    let shift = on(0xa0) || on(0xa1);
+    let control = on(0xa2) || on(0xa3);
+    let tab = on(0x09);
+    let bindings = [
+        (on(0x1b) || on(b'P'), MENU),
+        (on(0x0d) || (shift && !tab), A),
+        (on(0x08) || on(b'R'), B),
+        (on(0x20) || on(b'X'), X),
+        (on(b'F') || on(b'Y'), Y),
+        (on(0x21) || (tab && shift), LEFT_SHOULDER),
+        (on(0x22) || (tab && !shift) || on(b'Q'), RIGHT_SHOULDER),
+        (control, LEFT_STICK),
+        (mouse.middle || on(b'C'), RIGHT_STICK),
+        (on(b'V'), VIEW),
+        (on(0x26), UP),
+        (on(0x28), DOWN),
+        (on(0x25), LEFT),
+        (on(0x27) || on(b'E'), RIGHT),
+    ];
+    let axis = |positive, negative| bit_value(on(positive)) - bit_value(on(negative));
+    PadState {
+        buttons: bindings.into_iter().filter(|(pressed, _)| *pressed).fold(0, |bits, (_, button)| bits | button),
+        left_trigger: bit_value(mouse.aim || on(b'Z')),
+        right_trigger: bit_value(mouse.fire),
+        left_x: axis(b'D', b'A'),
+        left_y: axis(b'W', b'S'),
+        right_x: axis(b'L', b'J'),
+        right_y: axis(b'I', b'K'),
+    }
+}
+
+#[derive(Default)]
+struct PcPad {
+    down: u32,
+    pending: u32,
+    mouse: (f32, f32),
+}
+
+impl PcPad {
+    /// Keep a press until the title reads the pad, even if it was released
+    /// between two frames. Preserve mouse movement across the same polls.
+    fn poll(&mut self, keys: &[KeyState], mouse: PcMouse) -> PadState {
+        let mut pad = pc_pad(keys, &mouse);
+        // Shift may have queued sprint before the second key of Shift+Tab.
+        if key_held(keys, 0x09) && (key_held(keys, 0xa0) || key_held(keys, 0xa1))
+            && !key_held(keys, 0x0d)
+        {
+            self.pending &= !A;
+        }
+        const AIM: u32 = 1 << 30;
+        const FIRE: u32 = 1 << 31;
+        let down = pad.buttons
+            | if pad.left_trigger > 0.0 { AIM } else { 0 }
+            | if pad.right_trigger > 0.0 { FIRE } else { 0 };
+        self.pending |= down & !self.down;
+        self.down = down;
+        let buttons = down | self.pending;
+        pad.buttons = buttons & !(AIM | FIRE);
+        pad.left_trigger = bit_value(buttons & AIM != 0);
+        pad.right_trigger = bit_value(buttons & FIRE != 0);
+        self.mouse.0 = (self.mouse.0 + mouse.x).clamp(-1.0, 1.0);
+        self.mouse.1 = (self.mouse.1 + mouse.y).clamp(-1.0, 1.0);
+        pad.right_x = (pad.right_x + self.mouse.0).clamp(-1.0, 1.0);
+        pad.right_y = (pad.right_y + self.mouse.1).clamp(-1.0, 1.0);
+        pad
+    }
+
+    fn read(&mut self) {
+        self.pending = 0;
+        self.mouse = (0.0, 0.0);
+    }
+}
+
 /// Whether the title sees one pad that is always there, fed by the keyboard
 /// and by every host pad (on by default; `VICTORY_ONE_PAD=0` shows each host
 /// pad as a device of its own, and the stand-in only while there is none).
@@ -346,6 +448,7 @@ struct Slot {
 
 struct State {
     slots: [Slot; DEVICES],
+    pc_pad: PcPad,
     callbacks: Vec<Registration>,
     /// Asynchronous enumerations, delivered by the next poll.
     pending: Vec<Event>,
@@ -395,6 +498,7 @@ impl Hub {
             one_pad,
             state: Mutex::new(State {
                 slots: Default::default(),
+                pc_pad: PcPad::default(),
                 callbacks: Vec::new(),
                 pending: Vec::new(),
                 running: Vec::new(),
@@ -430,12 +534,14 @@ impl Hub {
 
     /// Reads the host once; device callbacks run on the calling thread.
     fn poll(&self) {
-        let (pads, keys) = {
+        let (pads, keys, mouse) = {
             let mut source = lock(&self.source);
             let pads: [_; PADS] = std::array::from_fn(|slot| source.pad(slot));
-            (pads, source.keys())
+            let keys = source.keys();
+            let mouse = source.pc_mouse(pc_layout() && (self.one_pad || pads.iter().all(Option::is_none)), &keys);
+            (pads, keys, mouse)
         };
-        let events = self.state().poll(&self.devices, self.one_pad, pads, keys);
+        let events = self.state().poll(&self.devices, self.one_pad, pads, keys, mouse);
         self.deliver(events);
     }
 
@@ -481,21 +587,26 @@ impl State {
         one_pad: bool,
         pads: [Option<PadState>; PADS],
         keys: Vec<KeyState>,
+        mouse: Option<PcMouse>,
     ) -> Vec<Event> {
         let now = now();
         let mut events = std::mem::take(&mut self.pending);
+        let any_pad = pads.iter().any(Option::is_some);
+        let keyboard_pad = if let Some(mouse) = mouse {
+            self.pc_pad.poll(&keys, mouse)
+        } else {
+            self.pc_pad = PcPad::default();
+            if pc_layout() { pc_pad(&keys, &PcMouse::default()) } else { fallback(&keys) }
+        };
         if one_pad {
-            let pad = pads.into_iter().flatten().fold(fallback(&keys), merged);
+            let pad = pads.into_iter().flatten().fold(keyboard_pad, merged);
             self.update(devices, FALLBACK, Some(Value::Pad(pad)), now, &mut events);
-            self.update(devices, KEYBOARD, Some(Value::Keys(keys)), now, &mut events);
-            return events;
-        }
-        let any_pad = pads.iter().any(Option::is_some);
-        for (slot, pad) in pads.into_iter().enumerate() {
-            self.update(devices, slot, pad.map(Value::Pad), now, &mut events);
+        } else {
+            for (slot, pad) in pads.into_iter().enumerate() {
+                self.update(devices, slot, pad.map(Value::Pad), now, &mut events);
+            }
+            self.update(devices, FALLBACK, (!any_pad).then_some(Value::Pad(keyboard_pad)), now, &mut events);
         }
-        let fallback = (!any_pad).then(|| Value::Pad(fallback(&keys)));
-        self.update(devices, FALLBACK, fallback, now, &mut events);
         self.update(devices, KEYBOARD, Some(Value::Keys(keys)), now, &mut events);
         events
     }
@@ -629,7 +740,7 @@ extern "system" fn current_reading(
     out: Out,
 ) -> HRESULT {
     let hub = hub(this);
-    let state = hub.state();
+    let mut state = hub.state();
     let newest = |i: usize| {
         state.slots[i]
             .history
@@ -654,7 +765,12 @@ extern "system" fn current_reading(
         sequence = found.map(|r| r.sequence),
         "current reading"
     );
-    hand(out, found)
+    let fallback_read = found.is_some_and(|reading| std::ptr::eq(reading.device, &hub.devices[FALLBACK]));
+    let result = hand(out, found);
+    if result == S_OK && fallback_read {
+        state.pc_pad.read();
+    }
+    result
 }
 
 /// The reading after (`forward`) or before `reference` on its device.
@@ -1114,11 +1230,20 @@ pub(crate) fn module() -> HleModule {
     }
 }
 
+#[cfg(windows)]
+static PC_MOUSE_CAPTURED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
+
+#[cfg(windows)]
+pub(crate) fn pc_mouse_captured() -> bool {
+    PC_MOUSE_CAPTURED.load(Ordering::Relaxed)
+}
+
 /// Host input: XInput pads, the keyboard while our process has focus.
 #[cfg(windows)]
 mod host {
     use std::time::{Duration, Instant};
 
+    use windows_sys::Win32::Foundation::POINT;
     use windows_sys::Win32::System::Threading::GetCurrentProcessId;
     use windows_sys::Win32::UI::Input::KeyboardAndMouse::{
         GetAsyncKeyState, MAPVK_VK_TO_VSC_EX, MapVirtualKeyW,
@@ -1132,7 +1257,8 @@ mod host {
         XInputSetState,
     };
     use windows_sys::Win32::UI::WindowsAndMessaging::{
-        GetForegroundWindow, GetWindowThreadProcessId,
+        GetCursorPos, GetForegroundWindow, GetWindowInfo, GetWindowThreadProcessId,
+        PostMessageW, SetCursorPos, WINDOWINFO, HTCLIENT, WM_MOUSEMOVE, WM_SETCURSOR,
     };
 
     use super::*;
@@ -1177,6 +1303,8 @@ mod host {
     #[derive(Default)]
     pub(super) struct Host {
         empty_until: [Option<Instant>; PADS],
+        mouse_captured: bool,
+        toggle_was_down: bool,
     }
 
     impl Source for Host {
@@ -1247,6 +1375,65 @@ mod host {
                 .collect()
         }
 
+        fn pc_mouse(&mut self, enabled: bool, keys: &[KeyState]) -> Option<PcMouse> {
+            if !enabled || !focused() {
+                self.mouse_captured = false;
+                self.toggle_was_down = false;
+                PC_MOUSE_CAPTURED.store(false, Ordering::Relaxed);
+                return None;
+            }
+            let toggle = key_held(keys, 0x71); // F2
+            let pause = key_held(keys, 0x1b) || key_held(keys, b'P');
+            let was_captured = self.mouse_captured;
+            if pause {
+                self.mouse_captured = false;
+            } else if toggle && !self.toggle_was_down {
+                self.mouse_captured = !self.mouse_captured;
+            }
+            self.toggle_was_down = toggle;
+            if was_captured != self.mouse_captured {
+                PC_MOUSE_CAPTURED.store(self.mouse_captured, Ordering::Relaxed);
+                // SAFETY: the focused window belongs to this process. The
+                // message asks its own thread to update the cursor immediately.
+                unsafe {
+                    let window = GetForegroundWindow();
+                    if !window.is_null() && focused() {
+                        PostMessageW(window, WM_SETCURSOR, window as usize,
+                                     HTCLIENT as isize | ((WM_MOUSEMOVE as isize) << 16));
+                    }
+                }
+            }
+            if !self.mouse_captured {
+                return Some(PcMouse::default());
+            }
+            let mut info = WINDOWINFO { cbSize: size_of::<WINDOWINFO>() as u32, ..Default::default() };
+            let mut position = POINT::default();
+            // SAFETY: both structures are valid output buffers. Only move the
+            // pointer while the game's foreground window still owns focus.
+            unsafe {
+                let window = GetForegroundWindow();
+                if window.is_null() || GetWindowInfo(window, &mut info) == 0
+                    || GetCursorPos(&mut position) == 0 || !focused()
+                    || window != GetForegroundWindow()
+                {
+                    return Some(PcMouse::default());
+                }
+                let x = info.rcClient.left + (info.rcClient.right - info.rcClient.left) / 2;
+                let y = info.rcClient.top + (info.rcClient.bottom - info.rcClient.top) / 2;
+                if (position.x != x || position.y != y) && SetCursorPos(x, y) == 0 {
+                    return Some(PcMouse::default());
+                }
+                let sensitivity = mouse_sensitivity();
+                Some(PcMouse {
+                    x: if was_captured { (position.x - x) as f32 * sensitivity } else { 0.0 },
+                    y: if was_captured { (y - position.y) as f32 * sensitivity } else { 0.0 },
+                    aim: GetAsyncKeyState(0x02) < 0,
+                    fire: GetAsyncKeyState(0x01) < 0,
+                    middle: GetAsyncKeyState(0x04) < 0,
+                })
+            }
+        }
+
         fn rumble(&mut self, slot: usize, low: u16, high: u16) {
             let speeds = XINPUT_VIBRATION {
                 wLeftMotorSpeed: low,
@@ -1257,6 +1444,16 @@ mod host {
         }
     }
 
+    fn mouse_sensitivity() -> f32 {
+        static SENSITIVITY: std::sync::OnceLock<f32> = std::sync::OnceLock::new();
+        *SENSITIVITY.get_or_init(|| {
+            std::env::var("VICTORY_MOUSE_LOOK")
+                .ok().and_then(|value| value.parse().ok())
+                .filter(|value: &f32| value.is_finite() && (0.001..=1.0).contains(value))
+                .unwrap_or(0.045)
+        })
+    }
+
     /// Debugging aid: `VICTORY_KEYS=<seconds>:<key>,...` holds each key for
     /// 0.2 s that long after input starts (`<from>-<to>:<key>`: all that
     /// time), with or without focus. A key is a
@@ -1343,6 +1540,8 @@ mod host {
             "Enter" => 0x0D,
             "Esc" => 0x1B,
             "Tab" => 0x09,
+            "PageUp" => 0x21,
+            "PageDown" => 0x22,
             "Back" => 0x08,
             "Up" => 0x26,
             "Down" => 0x28,
@@ -1607,6 +1806,34 @@ mod tests {
         release(rest);
     }
 
+    #[test]
+    fn pc_layout_switches_tabs_without_sprinting() {
+        let keys = |codes: &[u8]| codes.iter().map(|&virtual_key| KeyState {
+            virtual_key, ..KeyState::default()
+        }).collect::<Vec<_>>();
+        let mouse = PcMouse::default();
+        assert_eq!(pc_pad(&keys(&[0x09]), &mouse).buttons, RIGHT_SHOULDER);
+        assert_eq!(pc_pad(&keys(&[0x09, 0xa0]), &mouse).buttons, LEFT_SHOULDER);
+        assert_eq!(pc_pad(&keys(&[0x21]), &mouse).buttons, LEFT_SHOULDER);
+        assert_eq!(pc_pad(&keys(&[0x22]), &mouse).buttons, RIGHT_SHOULDER);
+        assert_eq!(pc_pad(&keys(&[0x1b]), &mouse).buttons, MENU);
+        assert_eq!(pc_pad(&keys(&[0x0d]), &mouse).buttons, A);
+    }
+
+    #[test]
+    fn pc_pad_holds_short_tab_taps_and_mouse_until_read() {
+        let mut input = PcPad::default();
+        input.poll(&[key(0x22)], PcMouse { x: 0.25, ..PcMouse::default() });
+        let pad = input.poll(&[], PcMouse { x: 0.25, ..PcMouse::default() });
+        assert_eq!(pad.buttons, RIGHT_SHOULDER);
+        assert_eq!(pad.right_x, 0.5);
+        input.read();
+        assert_eq!(input.poll(&[], PcMouse::default()), PadState::default());
+        input.poll(&[key(0xa0)], PcMouse::default());
+        let chord = input.poll(&[key(0xa0), key(0x09)], PcMouse::default());
+        assert_eq!(chord.buttons, LEFT_SHOULDER);
+    }
+
     #[test]
     fn keys_feed_the_keyboard_and_the_stand_in_pad() {
         let (hub, host) = fake();
diff --git a/crates/victory-hle/src/modules/lifecycle.rs b/crates/victory-hle/src/modules/lifecycle.rs
index 00699f7..8e0c0cd 100644
--- a/crates/victory-hle/src/modules/lifecycle.rs
+++ b/crates/victory-hle/src/modules/lifecycle.rs
@@ -257,6 +257,14 @@ extern "system" fn window_proc(
     wparam: WPARAM,
     lparam: LPARAM,
 ) -> LRESULT {
+    if message == wm::WM_SETCURSOR && lparam as u16 == wm::HTCLIENT as u16
+        && super::gameinput::pc_mouse_captured()
+        && unsafe { wm::GetForegroundWindow() } == hwnd
+    {
+        // SAFETY: this is the foreground game's client area.
+        unsafe { wm::SetCursor(std::ptr::null_mut()) };
+        return 1;
+    }
     // A user close (close button, Alt+F4, window or taskbar menu); a
     // console title never sees one, nor a WM_CLOSE from it.
     if message == wm::WM_SYSCOMMAND && wparam & 0xFFF0 == wm::SC_CLOSE as usize {
diff --git a/crates/victory-shader/src/emit/wave.rs b/crates/victory-shader/src/emit/wave.rs
index 56f981b..5f82b80 100644
--- a/crates/victory-shader/src/emit/wave.rs
+++ b/crates/victory-shader/src/emit/wave.rs
@@ -375,6 +375,7 @@ fn simulate(insts: &[Inst], wave: u32, saved: Value) -> Left {
             }
             continue;
         };
+        let f16_inline = name == "v_add_f16";
         let lanes = |op: &Operand,
                      vec: &HashMap<Value, Vec<Sym>>,
                      uni: &HashMap<Value, Sym>|
@@ -392,6 +393,12 @@ fn simulate(insts: &[Inst], wave: u32, saved: Value) -> Left {
                     Some(x) => one(uni.get(&x).copied().unwrap_or(Sym::Uni(x))),
                     None => one(Sym::Unknown),
                 },
+                Operand::Const(c @ 240..=248) if f16_inline => {
+                    let h = [
+                        0x3800, 0xB800, 0x3C00, 0xBC00, 0x4000, 0xC000, 0x4400, 0xC400, 0x3118,
+                    ][usize::from(c - 240)];
+                    one(Sym::K(h))
+                }
                 Operand::Const(c) => one(crate::resource::inline(c).map_or(Sym::Unknown, Sym::K)),
                 Operand::Literal(x) => one(Sym::K(x)),
                 _ => one(Sym::Unknown),
@@ -1289,4 +1296,44 @@ mod tests {
             assert_eq!(per_lane(&bad_ident, all), None);
         }
     }
+
+    #[test]
+    fn v_add_f16_inline_float_constants_are_not_zero_identity() {
+        // Wave32 f16 sum reduction with an extra `v_add_f16 v1, <const>, v1`
+        // step: 0 (code 128) is a true additive identity, whereas inline float
+        // constants (240..=248: 0.5, -0.5, 1.0, ..., 1/(2*pi)) are non-zero
+        // f16 values on GFX10 and must not be decoded as f32 bits whose low 15
+        // bits happen to be zero.
+        let run = |src_const: u16| -> (Option<Shape>, Value, Value) {
+            let mut w = vec![sop1(0, 0x3D, 193)]; // s_or_saveexec_b32 s0, -1
+            w.extend(vop3(1, 0x101, 128, 256, 0)); // v_cndmask_b32 v1, 0, v0, s0
+            w.push(vop2(1, 0x32, src_const, 1)); // v_add_f16 v1, <const>, v1
+            for ctrl in [0x00B1u16, 0x004E, 0x0164, 0x0168] {
+                w.push(vop2(1, 0x32, 0xFA, 1));
+                w.push(dpp16(1, ctrl, 0xF, 0xF, false));
+            }
+            w.extend(vop3(2, 0x378, 257, 128, 128)); // v_permlanex16_b32 v2, v1, 0, 0
+            w.push(vop2(1, 0x32, 258, 1)); // v_add_f16 v1, v2, v1
+            w.extend(vop3(1, 0x360, 257, 128 + 31, 0)); // v_readlane_b32 s1, v1, 31
+            w.push(sop1(EXEC, 0x03, 0)); // s_mov_b32 exec_lo, s0
+
+            let p = build(&w, false);
+            let insts = &p.blocks[0].insts;
+            let saved = insts[0].write(Reg::S(0)).unwrap();
+            let v0_in = insts[1].read(Reg::V(0)).unwrap();
+            let s1 = insts[insts.len() - 3].write(Reg::S(1)).unwrap();
+            let sec = &sections(&p, 0)[&0];
+            (sec.shapes.get(&s1).copied(), v0_in, saved)
+        };
+
+        let (zero_shape, v0_in, saved) = run(128);
+        assert_eq!(
+            zero_shape,
+            Some(Shape::Active(Op::AddH, v0_in, saved, 0))
+        );
+        for c in 240..=248u16 {
+            let (shape, _, _) = run(c);
+            assert_eq!(shape, None, "inline float const {c} was treated as identity");
+        }
+    }
 }
diff --git a/crates/victory-hle/src/modules/audio/mute.rs b/crates/victory-hle/src/modules/audio/mute.rs
new file mode 100644
index 0000000..be9ab78
--- /dev/null
+++ b/crates/victory-hle/src/modules/audio/mute.rs
@@ -0,0 +1,70 @@
+//! Mutes this runtime's own Windows audio sessions when requested.
+
+use std::time::Duration;
+use windows::Win32::Media::Audio::{
+    DEVICE_STATE_ACTIVE, IAudioSessionControl2, IAudioSessionManager2, IMMDeviceEnumerator,
+    ISimpleAudioVolume, MMDeviceEnumerator, eRender,
+};
+use windows::Win32::System::Com::{CLSCTX_ALL, COINIT_MULTITHREADED, CoCreateInstance, CoInitializeEx};
+use windows::core::{Interface, Result};
+
+pub fn start() {
+    if !std::env::var_os("VICTORY_MUTE").is_some_and(|value| value == "1") {
+        return;
+    }
+    if let Err(error) = std::thread::Builder::new().name("VIctory audio mute".into()).spawn(|| {
+        if let Err(error) = keep_muted() {
+            tracing::warn!(%error, "VIctory audio mute stopped");
+        }
+    }) {
+        tracing::warn!(%error, "VIctory audio mute could not start");
+    }
+}
+
+fn keep_muted() -> Result<()> {
+    let pid = std::process::id();
+    // SAFETY: the worker owns its COM apartment and all its audio interfaces.
+    let enumerator: IMMDeviceEnumerator = unsafe {
+        CoInitializeEx(None, COINIT_MULTITHREADED).ok()?;
+        CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)?
+    };
+    let mut confirmed = false;
+    loop {
+        if mute_sessions(&enumerator, pid).unwrap_or(false) && !confirmed {
+            confirmed = true;
+            tracing::info!(pid, "VIctory audio session muted and verified");
+        }
+        std::thread::sleep(Duration::from_millis(if confirmed { 500 } else { 100 }));
+    }
+}
+
+fn mute_sessions(enumerator: &IMMDeviceEnumerator, pid: u32) -> Result<bool> {
+    let mut found = false;
+    // SAFETY: each interface belongs to the initialized COM worker. The PID
+    // is checked before changing the mute state of a session.
+    unsafe {
+        let endpoints = enumerator.EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE)?;
+        for index in 0..endpoints.GetCount()? {
+            let Ok(endpoint) = endpoints.Item(index) else { continue };
+            let Ok(manager) = endpoint.Activate::<IAudioSessionManager2>(CLSCTX_ALL, None) else { continue };
+            let Ok(sessions) = manager.GetSessionEnumerator() else { continue };
+            for index in 0..sessions.GetCount().unwrap_or(0) {
+                let Ok(session) = sessions.GetSession(index) else { continue };
+                let Ok(control) = session.cast::<IAudioSessionControl2>() else { continue };
+                let mut owner = 0;
+                let result = (Interface::vtable(&control).GetProcessId)(control.as_raw(), &mut owner);
+                // GetProcessId returns a distinct success code for shared
+                // sessions. Only mute a session owned by this process alone.
+                if result.0 != 0 || owner != pid {
+                    continue;
+                }
+                let Ok(volume) = control.cast::<ISimpleAudioVolume>() else { continue };
+                if !volume.GetMute().is_ok_and(|muted| muted.as_bool()) {
+                    let _ = volume.SetMute(true, std::ptr::null());
+                }
+                found |= volume.GetMute().is_ok_and(|muted| muted.as_bool());
+            }
+        }
+    }
+    Ok(found)
+}
```
