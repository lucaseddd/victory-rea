# Capture and black-frame probe on the two-plane path, and VICTORY_CAPTURE_MENUS

Candidate 5. `VICTORY_CAPTURE_MENUS=0` skips captures of menu and loading frames (only 3D frames are saved). The black-frame probe, which only ran on the one-plane path, now also runs on the two-plane path added by patch 03 (fork PR #1081).

- **Apply after** patches 01–06, on the same base. Hunk line numbers follow that chain.
- License: GPL-3.0, like the rest of VIctory and the fork.
- To apply: copy each `diff` block to a `.patch` file, run `git apply --check`, then `git apply`.

## `crates/victory-gpu/src/capture.rs`

```diff
--- a/crates/victory-gpu/src/capture.rs
+++ b/crates/victory-gpu/src/capture.rs
@@ -174,7 +174,12 @@
 pub(crate) fn wanted(n: u64) -> bool {
     // Before the world, with `VICTORY_CAPTURE_WORLD`: every 16th frame too
     // (small pictures of menus, loading screens and title cards).
-    let before_world = world_on() && n.is_multiple_of(16) && WORLD.load(std::sync::atomic::Ordering::Relaxed) == u64::MAX;
+    // `VICTORY_CAPTURE_MENUS=0`: not those (a long loading screen at 30 fps
+    // would save hundreds of pictures and slow the run being measured).
+    static MENUS: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
+    let menus = *MENUS.get_or_init(|| std::env::var_os("VICTORY_CAPTURE_MENUS").is_none_or(|v| v != "0"));
+    let before_world =
+        menus && world_on() && n.is_multiple_of(16) && WORLD.load(std::sync::atomic::Ordering::Relaxed) == u64::MAX;
     // In the world: every 8th frame's picture, a timeline of the opening
     // cutscene (its shots do not fall on the same frame numbers from run to
     // run, so single frames cannot be compared between runs).
```

## `crates/victory-gpu/src/host.rs`

```diff
--- a/crates/victory-gpu/src/host.rs
+++ b/crates/victory-gpu/src/host.rs
@@ -9736,17 +9736,26 @@
                         overlay,
                         overlay_state,
                     );
-                    list.ResourceBarrier(&[transition(
-                        &back,
-                        D3D12_RESOURCE_STATE_PRESENT,
-                        D3D12_RESOURCE_STATE_COPY_DEST,
-                    )]);
+                    // The game plane as a copy's source while the box is
+                    // drawn and, in diagnostics builds, while the frame is
+                    // saved and probed for black as on the one-plane path
+                    // (the probe reads the game plane: the picture's own
+                    // pixels, not the interface over it).
+                    list.ResourceBarrier(&[
+                        transition(texture, state, D3D12_RESOURCE_STATE_COPY_SOURCE),
+                        transition(&back, D3D12_RESOURCE_STATE_PRESENT, D3D12_RESOURCE_STATE_COPY_DEST),
+                    ]);
                     crate::fpsbox::draw(self, list, &back, (width, height, format));
-                    list.ResourceBarrier(&[transition(
-                        &back,
-                        D3D12_RESOURCE_STATE_COPY_DEST,
-                        D3D12_RESOURCE_STATE_PRESENT,
-                    )]);
+                    #[cfg(feature = "diagnostics")]
+                    let capture = crate::capture::wanted(frame)
+                        .then(|| crate::capture::read_back(&self.device, list, texture))
+                        .flatten();
+                    #[cfg(feature = "diagnostics")]
+                    let probe = if slot.is_some() { None } else { crate::capture::probe(&self.device, list, texture) };
+                    list.ResourceBarrier(&[
+                        transition(texture, D3D12_RESOURCE_STATE_COPY_SOURCE, state),
+                        transition(&back, D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_PRESENT),
+                    ]);
                     copy.close();
                     match slot {
                         Some(i) => {
@@ -9755,8 +9764,15 @@
                         }
                         None => self.execute(&[copy]),
                     }
+                    #[cfg(feature = "diagnostics")]
+                    if let Some((buffer, footprint)) = capture {
+                        crate::capture::save_read_back(frame, &buffer, &footprint);
+                    }
                     let _ = p.swap_chain.Present(0, DXGI_PRESENT(0));
                     p.meter.frame(p.hwnd);
+                    #[cfg(feature = "diagnostics")]
+                    return Some(probe.is_some_and(|b| crate::capture::black(&b)));
+                    #[cfg(not(feature = "diagnostics"))]
                     return Some(false);
                 }
             }
```

