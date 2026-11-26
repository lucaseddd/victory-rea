# Composing the two Series S planes (port of fxceless PR #1081)

Candidate 4. With `--console series-s`, the title presents two planes: the game and the interface. Without this patch only the first one shows, and boot, loading screens and prompts come out black. `VICTORY_PLANES=0` restores the old behavior; `VICTORY_PLANE_ALPHA=straight` uses straight alpha. `compose.rs` is the PR's file, unchanged (head `08ab0418`). The local addition also draws the FPS box on the two-plane path.

- **Apply in order**, on top of `fxceless/victory-fork` at commit `f6a09d3b` with PR #45 (candidate 1). Hunk line numbers follow that chain.
- License: VIctory and the fork are GPL-3.0. This diff derives from that code and is under the same license.
- To apply: copy the `diff` block to `03-series-s-planes-pr1081.patch`, run `git apply --check 03-series-s-planes-pr1081.patch`, then `git apply 03-series-s-planes-pr1081.patch`.

## `crates/victory-gpu/src/compose.rs`

```diff
--- a/crates/victory-gpu/src/compose.rs
+++ b/crates/victory-gpu/src/compose.rs
@@ -0,0 +1,244 @@
+// Port of fxceless/victory-fork pull request #1081 (KyleS98, head 08ab0418), unchanged.
+//! The console's second display plane, blended over the first at present.
+//!
+//! With the Series S profile the title presents two planes: the game at
+//! 1920x1080 (plane 0) and its interface at 3840x2160 (plane 1), each
+//! placed over the whole screen. The console's display blends the second
+//! over the first; showing only the first leaves out everything the title
+//! draws on the interface plane, which at boot is everything: the logos,
+//! the account picker and the loading screens were black for over a minute
+//! (with the Series X profile the title draws them into its one plane).
+//!
+//! The pass draws one triangle over the back buffer: the game plane
+//! sampled with a linear filter to the back buffer's size, the interface
+//! plane over it with premultiplied alpha, as display planes take it
+//! (`VICTORY_PLANE_ALPHA=straight`: straight alpha instead).
+
+use std::sync::OnceLock;
+
+use windows::Win32::Graphics::Direct3D::D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST;
+use windows::Win32::Graphics::Direct3D12::*;
+use windows::Win32::Graphics::Dxgi::Common::*;
+
+use crate::host::{compile, transition};
+
+const SOURCE: &str = r#"
+#define RS "DescriptorTable(SRV(t0, numDescriptors = 2), visibility = SHADER_VISIBILITY_PIXEL), RootConstants(num32BitConstants = 1, b0, visibility = SHADER_VISIBILITY_PIXEL), StaticSampler(s0, filter = FILTER_MIN_MAG_MIP_LINEAR, addressU = TEXTURE_ADDRESS_CLAMP, addressV = TEXTURE_ADDRESS_CLAMP, addressW = TEXTURE_ADDRESS_CLAMP, visibility = SHADER_VISIBILITY_PIXEL)"
+Texture2D<float4> game : register(t0);
+Texture2D<float4> overlay : register(t1);
+SamplerState linear_clamp : register(s0);
+cbuffer Settings : register(b0) { uint straight; };
+float4 corner(uint i : SV_VertexID, out float2 uv : TEXCOORD0) : SV_Position {
+    float2 p = float2(float(i & 1) * 4.0 - 1.0, float(i >> 1) * 4.0 - 1.0);
+    uv = float2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
+    return float4(p, 0.0, 1.0);
+}
+[RootSignature(RS)]
+float4 blend(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target {
+    float3 g = game.SampleLevel(linear_clamp, uv, 0).rgb;
+    float4 o = overlay.SampleLevel(linear_clamp, uv, 0);
+    float3 c = straight != 0 ? lerp(g, o.rgb, o.a) : g * (1.0 - o.a) + o.rgb;
+    return float4(c, 1.0);
+}
+"#;
+
+/// Descriptor pairs (and target views) used in turn, one per present: more
+/// than the presents that can be in the air at once.
+const RING: u32 = 16;
+const PIXEL_SHADER_RESOURCE: u32 = 0x80;
+
+pub(crate) struct Compose {
+    format: DXGI_FORMAT,
+    root: ID3D12RootSignature,
+    pipeline: ID3D12PipelineState,
+    views: ID3D12DescriptorHeap,
+    targets: ID3D12DescriptorHeap,
+    view_step: u32,
+    target_step: u32,
+    next: u32,
+}
+
+/// Whether two planes are blended (`VICTORY_PLANES=0`: only the first is
+/// shown, as before).
+pub(crate) fn on() -> bool {
+    static ON: OnceLock<bool> = OnceLock::new();
+    *ON.get_or_init(|| std::env::var_os("VICTORY_PLANES").is_none_or(|v| v != "0"))
+}
+
+fn straight() -> bool {
+    static ON: OnceLock<bool> = OnceLock::new();
+    *ON.get_or_init(|| std::env::var_os("VICTORY_PLANE_ALPHA").is_some_and(|v| v == "straight"))
+}
+
+/// The view format of a plane's texture (typeless ones read as UNORM).
+fn view_format(format: DXGI_FORMAT) -> DXGI_FORMAT {
+    match format {
+        DXGI_FORMAT_R8G8B8A8_TYPELESS => DXGI_FORMAT_R8G8B8A8_UNORM,
+        DXGI_FORMAT_B8G8R8A8_TYPELESS => DXGI_FORMAT_B8G8R8A8_UNORM,
+        DXGI_FORMAT_R10G10B10A2_TYPELESS => DXGI_FORMAT_R10G10B10A2_UNORM,
+        DXGI_FORMAT_R16G16B16A16_TYPELESS => DXGI_FORMAT_R16G16B16A16_FLOAT,
+        f => f,
+    }
+}
+
+impl Compose {
+    /// The pass for back buffers of `format`.
+    pub(crate) fn new(device: &ID3D12Device, format: DXGI_FORMAT) -> windows::core::Result<Compose> {
+        use windows::core::s;
+        let vs = compile(SOURCE, s!("corner"), s!("vs_5_1"))?;
+        let ps = compile(SOURCE, s!("blend"), s!("ps_5_1"))?;
+        let code = |bytes: &[u8]| D3D12_SHADER_BYTECODE {
+            pShaderBytecode: bytes.as_ptr().cast(),
+            BytecodeLength: bytes.len(),
+        };
+        // SAFETY: the root signature is inside the pixel shader; the
+        // description points at live data and never releases its pointer.
+        unsafe {
+            let root: ID3D12RootSignature = device.CreateRootSignature(0, &ps[..])?;
+            let mut formats = [DXGI_FORMAT_UNKNOWN; 8];
+            formats[0] = format;
+            let mut blend = D3D12_BLEND_DESC::default();
+            blend.RenderTarget[0].RenderTargetWriteMask = D3D12_COLOR_WRITE_ENABLE_ALL.0 as u8;
+            let desc = D3D12_GRAPHICS_PIPELINE_STATE_DESC {
+                pRootSignature: std::mem::transmute_copy(&root),
+                VS: code(&vs[..]),
+                PS: code(&ps[..]),
+                BlendState: blend,
+                SampleMask: u32::MAX,
+                RasterizerState: D3D12_RASTERIZER_DESC {
+                    FillMode: D3D12_FILL_MODE_SOLID,
+                    CullMode: D3D12_CULL_MODE_NONE,
+                    DepthClipEnable: true.into(),
+                    ..Default::default()
+                },
+                PrimitiveTopologyType: D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE,
+                NumRenderTargets: 1,
+                RTVFormats: formats,
+                SampleDesc: DXGI_SAMPLE_DESC {
+                    Count: 1,
+                    Quality: 0,
+                },
+                ..Default::default()
+            };
+            let pipeline: ID3D12PipelineState = device.CreateGraphicsPipelineState(&desc)?;
+            let views: ID3D12DescriptorHeap = device.CreateDescriptorHeap(&D3D12_DESCRIPTOR_HEAP_DESC {
+                Type: D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV,
+                NumDescriptors: 2 * RING,
+                Flags: D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE,
+                NodeMask: 0,
+            })?;
+            let targets: ID3D12DescriptorHeap = device.CreateDescriptorHeap(&D3D12_DESCRIPTOR_HEAP_DESC {
+                Type: D3D12_DESCRIPTOR_HEAP_TYPE_RTV,
+                NumDescriptors: RING,
+                Flags: D3D12_DESCRIPTOR_HEAP_FLAG_NONE,
+                NodeMask: 0,
+            })?;
+            tracing::info!(format = format.0, "present planes: the second is blended over the first");
+            Ok(Compose {
+                format,
+                root,
+                pipeline,
+                view_step: device.GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV),
+                target_step: device.GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_RTV),
+                views,
+                targets,
+                next: 0,
+            })
+        }
+    }
+
+    pub(crate) fn format(&self) -> DXGI_FORMAT {
+        self.format
+    }
+
+    /// Records into `list` the pass that draws `game` and `interface` (in
+    /// states `game_state` and `interface_state`, which they are left in)
+    /// over `back` (in the present state, which it is left in).
+    ///
+    /// # Safety
+    /// Live resources; `list` open; `back` of this pass's format and
+    /// `width` x `height`.
+    #[allow(clippy::too_many_arguments)]
+    pub(crate) unsafe fn record(
+        &mut self,
+        device: &ID3D12Device,
+        list: &ID3D12GraphicsCommandList,
+        back: &ID3D12Resource,
+        (width, height): (u32, u32),
+        game: &ID3D12Resource,
+        game_state: u32,
+        interface: &ID3D12Resource,
+        interface_state: u32,
+    ) {
+        let slot = self.next % RING;
+        self.next = self.next.wrapping_add(1);
+        // SAFETY: (all below) descriptor writes into our heaps, then
+        // commands into an open list, on live resources.
+        unsafe {
+            let cpu = self.views.GetCPUDescriptorHandleForHeapStart().ptr + (2 * slot * self.view_step) as usize;
+            for (k, texture) in [game, interface].into_iter().enumerate() {
+                let d = texture.GetDesc();
+                let view = D3D12_SHADER_RESOURCE_VIEW_DESC {
+                    Format: view_format(d.Format),
+                    ViewDimension: D3D12_SRV_DIMENSION_TEXTURE2D,
+                    Shader4ComponentMapping: D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING,
+                    Anonymous: D3D12_SHADER_RESOURCE_VIEW_DESC_0 {
+                        Texture2D: D3D12_TEX2D_SRV {
+                            MostDetailedMip: 0,
+                            MipLevels: 1,
+                            PlaneSlice: 0,
+                            ResourceMinLODClamp: 0.0,
+                        },
+                    },
+                };
+                let at = D3D12_CPU_DESCRIPTOR_HANDLE {
+                    ptr: cpu + k * self.view_step as usize,
+                };
+                device.CreateShaderResourceView(texture, Some(&view), at);
+            }
+            let target = D3D12_CPU_DESCRIPTOR_HANDLE {
+                ptr: self.targets.GetCPUDescriptorHandleForHeapStart().ptr + (slot * self.target_step) as usize,
+            };
+            device.CreateRenderTargetView(back, None, target);
+            // What moves for the pass, and back after it.
+            let mut moves: Vec<(&ID3D12Resource, D3D12_RESOURCE_STATES, D3D12_RESOURCE_STATES)> = Vec::new();
+            for (texture, state) in [(game, game_state), (interface, interface_state)] {
+                if state & PIXEL_SHADER_RESOURCE == 0 {
+                    moves.push((
+                        texture,
+                        D3D12_RESOURCE_STATES(state as i32),
+                        D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE,
+                    ));
+                }
+            }
+            moves.push((back, D3D12_RESOURCE_STATE_PRESENT, D3D12_RESOURCE_STATE_RENDER_TARGET));
+            let before: Vec<_> = moves.iter().map(|&(r, a, b)| transition(r, a, b)).collect();
+            list.ResourceBarrier(&before);
+            list.SetGraphicsRootSignature(&self.root);
+            list.SetDescriptorHeaps(&[Some(self.views.clone())]);
+            let gpu = self.views.GetGPUDescriptorHandleForHeapStart().ptr + u64::from(2 * slot * self.view_step);
+            list.SetGraphicsRootDescriptorTable(0, D3D12_GPU_DESCRIPTOR_HANDLE { ptr: gpu });
+            list.SetGraphicsRoot32BitConstant(1, u32::from(straight()), 0);
+            list.SetPipelineState(&self.pipeline);
+            list.OMSetRenderTargets(1, Some(&target), false, None);
+            list.RSSetViewports(&[D3D12_VIEWPORT {
+                TopLeftX: 0.0,
+                TopLeftY: 0.0,
+                Width: width as f32,
+                Height: height as f32,
+                MinDepth: 0.0,
+                MaxDepth: 1.0,
+            }]);
+            list.RSSetScissorRects(&[windows::Win32::Foundation::RECT {
+                left: 0,
+                top: 0,
+                right: width as i32,
+                bottom: height as i32,
+            }]);
+            list.IASetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
+            list.DrawInstanced(3, 1, 0, 0);
+            let after: Vec<_> = moves.iter().map(|&(r, a, b)| transition(r, b, a)).collect();
+            list.ResourceBarrier(&after);
+        }
+    }
+}
```

## `crates/victory-gpu/src/host.rs`

```diff
--- a/crates/victory-gpu/src/host.rs
+++ b/crates/victory-gpu/src/host.rs
@@ -9280,6 +9280,9 @@
     ahead: Vec<(HostList, u64)>,
     hwnd: HWND,
     meter: Meter,
+    /// The pass that blends a second present plane, once one is presented
+    /// (fork pull request #1081).
+    compose: Option<crate::compose::Compose>,
 }
 
 /// The frame rate, shown in the window's caption every second and logged
@@ -9608,14 +9611,28 @@
     /// Shows `texture`, which is in `state` (a host state) and stays in it,
     /// as frame `frame` (saved if captures are on). `None` if nothing was
     /// shown; else, in diagnostics builds, whether the frame was black.
-    pub(crate) fn present(&self, texture: &ID3D12Resource, state: u32, frame: u64) -> Option<bool> {
+    /// `interface`: the second present plane and its state, blended over
+    /// `texture` (`crate::compose`, fork pull request #1081).
+    pub(crate) fn present(
+        &self,
+        texture: &ID3D12Resource,
+        state: u32,
+        interface: Option<(&ID3D12Resource, u32)>,
+        frame: u64,
+    ) -> Option<bool> {
         let showing = std::time::Instant::now();
-        let shown = self.present_now(texture, state, frame);
+        let shown = self.present_now(texture, state, interface, frame);
         crate::framelog::add(crate::framelog::T::PresentShowUs, showing.elapsed().as_micros() as u64);
         shown
     }
 
-    fn present_now(&self, texture: &ID3D12Resource, state: u32, frame: u64) -> Option<bool> {
+    fn present_now(
+        &self,
+        texture: &ID3D12Resource,
+        state: u32,
+        interface: Option<(&ID3D12Resource, u32)>,
+        frame: u64,
+    ) -> Option<bool> {
         // SAFETY: a live resource.
         let desc = unsafe { texture.GetDesc() };
         let Some(format) = swap_format(desc.Format) else {
@@ -9691,6 +9708,58 @@
             };
             copy.reset();
             let list = &copy.list;
+            // Two present planes (the Series S profile): the interface plane
+            // blended over the game plane (`crate::compose`, fork pull
+            // request #1081), then the frame-rate box as usual.
+            static NO_COMPOSE: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
+            if let Some((overlay, overlay_state)) = interface
+                && !NO_COMPOSE.load(Ordering::Relaxed)
+            {
+                if p.compose.as_ref().is_none_or(|c| c.format() != p.format) {
+                    p.compose = match crate::compose::Compose::new(&self.device, p.format) {
+                        Ok(c) => Some(c),
+                        Err(e) => {
+                            NO_COMPOSE.store(true, Ordering::Relaxed);
+                            tracing::warn!(error = %e, "no pass to blend the second present plane; only the first is shown");
+                            None
+                        }
+                    };
+                }
+                if let Some(c) = p.compose.as_mut() {
+                    c.record(
+                        &self.device,
+                        list,
+                        &back,
+                        (p.width, p.height),
+                        texture,
+                        state.0 as u32,
+                        overlay,
+                        overlay_state,
+                    );
+                    list.ResourceBarrier(&[transition(
+                        &back,
+                        D3D12_RESOURCE_STATE_PRESENT,
+                        D3D12_RESOURCE_STATE_COPY_DEST,
+                    )]);
+                    crate::fpsbox::draw(self, list, &back, (width, height, format));
+                    list.ResourceBarrier(&[transition(
+                        &back,
+                        D3D12_RESOURCE_STATE_COPY_DEST,
+                        D3D12_RESOURCE_STATE_PRESENT,
+                    )]);
+                    copy.close();
+                    match slot {
+                        Some(i) => {
+                            let flown = self.execute_own(copy);
+                            p.ahead[i].1 = flown;
+                        }
+                        None => self.execute(&[copy]),
+                    }
+                    let _ = p.swap_chain.Present(0, DXGI_PRESENT(0));
+                    p.meter.frame(p.hwnd);
+                    return Some(false);
+                }
+            }
             list.ResourceBarrier(&[
                 transition(texture, state, D3D12_RESOURCE_STATE_COPY_SOURCE),
                 transition(
@@ -9792,6 +9861,7 @@
                 ahead: Vec::new(),
                 hwnd,
                 meter: Meter::new(),
+                compose: None,
             })
         }
     }
```

## `crates/victory-gpu/src/lib.rs`

```diff
--- a/crates/victory-gpu/src/lib.rs
+++ b/crates/victory-gpu/src/lib.rs
@@ -48,6 +48,8 @@
 #[cfg(windows)]
 pub mod framelog;
 #[cfg(windows)]
+mod compose;
+#[cfg(windows)]
 mod heap_worker;
 #[cfg(windows)]
 mod host;
```

## `crates/victory-gpu/src/queue.rs`

```diff
--- a/crates/victory-gpu/src/queue.rs
+++ b/crates/victory-gpu/src/queue.rs
@@ -137,6 +137,10 @@
 #[cfg(windows)]
 fn send_behind(this: This, planes: u32, plane_parameters: *const Plane) -> bool {
     if this.is_null() || planes == 0 || PRESENTS_HELD.load(Ordering::Relaxed) != 0 {
+        return false;
+    }
+    // Two planes are blended (`crate::compose`) by the present in line.
+    if planes > 1 && crate::compose::on() {
         return false;
     }
     let frame = FRAMES.load(Ordering::Relaxed) + 1;
@@ -894,7 +898,7 @@
                     Held::Present(texture, state, frame) => {
                         let show = || {
                             if let Some(host) = crate::host::host() {
-                                let _ = host.present(&texture, state, frame);
+                                let _ = host.present(&texture, state, None, frame);
                             }
                         };
                         if all {
@@ -1115,12 +1119,17 @@
 }
 
 /// The start of a present plane: frame token, then the plane's resources.
+/// The title passes an array of them, `PLANE_STRIDE` bytes apart (then the
+/// source and placement rectangles, color space, flags and more).
 #[repr(C)]
 pub(crate) struct Plane {
     token: u64,
     count: u32,
     resources: *const This,
 }
+/// Bytes from one present plane's description to the next (as the Series
+/// S profile's two planes lie). Fork pull request #1081.
+const PLANE_STRIDE: usize = 72;
 /// Submission tagged with the frame it belongs to `(count, lists, frame
 /// token, flags)`; frames are paced elsewhere, so it runs as a plain one.
 extern "system" fn execute_x(this: This, count: u32, lists: *const This, _token: u64, _flags: u32) {
@@ -1402,10 +1411,34 @@
         && let Some(host) = crate::host::host()
     {
         const COPY_SOURCE: u32 = 0x800;
+        const PIXEL_SHADER_RESOURCE: u32 = 0x80;
+        // The second plane (the interface, with the Series S profile),
+        // blended over the first (`crate::compose`, fork pull request #1081).
+        let interface = (planes > 1 && crate::compose::on())
+            // SAFETY: the title passes `planes` descriptions of PLANE_STRIDE bytes.
+            .then(|| unsafe { plane_parameters.cast::<u8>().add(PLANE_STRIDE).cast::<Plane>().as_ref() })
+            .flatten()
+            .filter(|p| p.count > 0 && !p.resources.is_null())
+            // SAFETY: the plane lists `count` resources.
+            .map(|p| unsafe { *p.resources })
+            .filter(|&r| r != resource)
+            .and_then(|r| crate::resource::host_resource(r).map(|t| (r, t)));
+        let interface_state = interface.map(|(r, _)| {
+            crate::resource::host_transition(r, PIXEL_SHADER_RESOURCE)
+                .map_or(PIXEL_SHADER_RESOURCE, |(_, before)| before)
+        });
         let state = crate::resource::host_transition(resource, COPY_SOURCE)
             .map_or(COPY_SOURCE, |(_, before)| before);
-        let shown = host.present(texture, state, frame);
+        let shown = host.present(
+            texture,
+            state,
+            interface.zip(interface_state).map(|((_, t), s)| (t, s)),
+            frame,
+        );
         crate::resource::host_transition(resource, state);
+        if let Some(((r, _), s)) = interface.zip(interface_state) {
+            crate::resource::host_transition(r, s);
+        }
         #[cfg(feature = "diagnostics")]
         blinks(frame, resource, state, shown);
         #[cfg(not(feature = "diagnostics"))]
```

