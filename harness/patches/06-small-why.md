# SMALL_WHY: why small levels on a full card (optional)

Candidate 2, together with the DirectStorage counters. It logs why tiled textures were left with only small levels while the card was full. `Measure-Run.ps1` shows the `small levels on a full card` line. Not needed for the score.

- **Apply in order**, on top of `fxceless/victory-fork` at commit `f6a09d3b` with PR #45 (candidate 1). Hunk line numbers follow that chain.
- License: VIctory and the fork are GPL-3.0. This diff derives from that code and is under the same license.
- To apply: copy the `diff` block to `06-small-why.patch`, run `git apply --check 06-small-why.patch`, then `git apply 06-small-why.patch`.

## `crates/victory-gpu/src/tiles.rs`

```diff
--- a/crates/victory-gpu/src/tiles.rs
+++ b/crates/victory-gpu/src/tiles.rs
@@ -77,6 +77,15 @@
 /// tiles on a full card by [`small_when_full_mb`].
 pub(crate) static BLANK: [AtomicU64; 3] = [const { AtomicU64::new(0) }; 3];
 
+/// Since the start, with `VICTORY_TILES_SMALL_WHEN_FULL_MB` on, uploads on a
+/// full card for which [`Tiled::small_levels`] was asked: in all; refused
+/// because the tiles given in all already reach the switch's megabytes;
+/// refused because the texture's smallest levels need more than
+/// [`SMALL_TILES`] tiles; refused because its smallest level is not held;
+/// levels chosen that still got no tiles (no heap could be had). Counts
+/// only: the policy is unchanged. (Local, after the REA notes on 6 GB.)
+pub(crate) static SMALL_WHY: [AtomicU64; 5] = [const { AtomicU64::new(0) }; 5];
+
 /// `VICTORY_TILES_SMALL_WHEN_FULL_MB` (0, off, by default): while the card
 /// has no room, an upload still gives tiles to the smallest held levels of
 /// its texture (the packed ones, then standard ones from the smallest up,
@@ -416,6 +425,12 @@
         }
         let changed =
             self.give_locked(&mut given, queue, device, texture, named, if room { named } else { card | small });
+        if small != 0 {
+            let unbacked = self.without_locked(&given, small);
+            if unbacked != 0 {
+                SMALL_WHY[4].fetch_add(u64::from(unbacked.count_ones()), Ordering::Relaxed);
+            }
+        }
         let missing = self.without_locked(&given, named) != 0;
         (changed, missing)
     }
@@ -476,7 +491,12 @@
     /// reads no level without memory.
     fn small_levels(&self, held: u32) -> u32 {
         let cap = small_when_full_mb() << 20;
-        if cap == 0 || STATS[2].load(Ordering::Relaxed) >= cap {
+        if cap == 0 {
+            return 0;
+        }
+        SMALL_WHY[0].fetch_add(1, Ordering::Relaxed);
+        if STATS[2].load(Ordering::Relaxed) >= cap {
+            SMALL_WHY[1].fetch_add(1, Ordering::Relaxed);
             return 0;
         }
         let first_packed = self.standard.len() as u32;
@@ -485,6 +505,7 @@
         if self.packed > 0 {
             let packed_bits = self.every_level() & !((1u32 << first_packed) - 1);
             if held & packed_bits == 0 {
+                SMALL_WHY[3].fetch_add(1, Ordering::Relaxed);
                 return 0;
             }
             bits |= packed_bits;
@@ -498,7 +519,21 @@
             tiles += tiles_here;
             bits |= 1 << level;
         }
-        if tiles > SMALL_TILES { 0 } else { bits }
+        if tiles > SMALL_TILES {
+            SMALL_WHY[2].fetch_add(1, Ordering::Relaxed);
+            0
+        } else {
+            if bits == 0 {
+                // No packed levels and the smallest standard level is not
+                // held, or alone needs more than `SMALL_TILES` tiles.
+                let smallest = first_packed.checked_sub(1);
+                match smallest {
+                    Some(l) if held & (1 << l) == 0 => SMALL_WHY[3].fetch_add(1, Ordering::Relaxed),
+                    _ => SMALL_WHY[2].fetch_add(1, Ordering::Relaxed),
+                };
+            }
+            bits
+        }
     }
 
     /// The bits of the levels that get their tiles with level `level`:
@@ -806,6 +841,23 @@
         small_when_full_mb(),
         blank[2],
     );
+    if small_when_full_mb() != 0 {
+        let why: Vec<u64> = SMALL_WHY.iter().map(|w| w.load(Ordering::Relaxed)).collect();
+        tracing::info!(
+            "small levels on a full card since the start (VICTORY_TILES_SMALL_WHEN_FULL_MB={}): {} asked; refused: {} by the tiles \
+             given in all ({} MB given now, cap {} MB), {} by the texture's tile count (over {} tiles), {} because its smallest \
+             level is not held; {} levels chosen got no tiles (no heap)",
+            small_when_full_mb(),
+            why[0],
+            why[1],
+            s[2] >> 20,
+            small_when_full_mb(),
+            why[2],
+            SMALL_TILES,
+            why[3],
+            why[4],
+        );
+    }
 }
 
 /// On the card, without the title: what levels on demand relies on, with
```

