# VICTORY_TEXTURE_FLOOR_MB e AUTO_VRAM desligado por padrão

Candidata 3, correção da cutscene preta (R13). O orçamento de texturas pela VRAM (PR #45) só liga com `VICTORY_TEXTURE_AUTO_VRAM=1`. `VICTORY_TEXTURE_FLOOR_MB` define o piso direto, e uma linha no início do log informa o piso efetivo. O `-PisoTexturasMB` do launcher usa esse patch.

- **Aplicar em ordem**, sobre `fxceless/victory-fork` no commit `f6a09d3b` com o PR #45 (candidata 1). Os números de linha dos hunks seguem essa cadeia.
- Licença: o VIctory e o fork são GPL-3.0. Este diff é derivado desse código e segue a mesma licença.
- Para aplicar: copie o bloco `diff` para `02-texture-floor.patch` e rode `git apply --check 02-texture-floor.patch`, depois `git apply 02-texture-floor.patch`.

## `crates/victory-gpu/src/draw.rs`

```diff
--- a/crates/victory-gpu/src/draw.rs
+++ b/crates/victory-gpu/src/draw.rs
@@ -4861,11 +4861,14 @@
 }
 
 /// Whether texture budgets follow the adapter's VRAM budget (fork pull
-/// request #45); `VICTORY_TEXTURE_AUTO_VRAM=0` keeps the fixed 2 GiB floor
-/// and 192 MiB staging per frame, as before.
+/// request #45): only with `VICTORY_TEXTURE_AUTO_VRAM=1`. Off by default:
+/// on a 6 GB card whose use stands over nine tenths of its budget, the
+/// quarter-of-the-budget floor held the title's textures at about 1.27 GB
+/// (2 GiB before), surfaces read zero base colour and the cutscene came out
+/// black (candidate 1, Controle run of 2026-11-26 07:02, REA-COORD R13).
 pub(crate) fn texture_auto_vram() -> bool {
     static ON: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
-    *ON.get_or_init(|| std::env::var_os("VICTORY_TEXTURE_AUTO_VRAM").is_none_or(|v| v != "0"))
+    *ON.get_or_init(|| std::env::var_os("VICTORY_TEXTURE_AUTO_VRAM").is_some_and(|v| v == "1"))
 }
 
 /// Per-frame texture staging byte budget scaled from the adapter's local VRAM
```

## `crates/victory-gpu/src/resource.rs`

```diff
--- a/crates/victory-gpu/src/resource.rs
+++ b/crates/victory-gpu/src/resource.rs
@@ -1467,11 +1467,32 @@
     if let Some(limit) = limit {
         return filled < limit;
     }
-    let floor = if crate::draw::texture_auto_vram() {
-        texture_floor_bytes(memory.map(|[budget, ..]| budget))
-    } else {
-        texture_floor_bytes(None)
+    // `VICTORY_TEXTURE_FLOOR_MB` sets the floor outright (picture first: more
+    // of the title's textures made before the budget check; beyond the card's
+    // budget they spill to the PC's memory). Local, REA-COORD R13.
+    static FLOOR_MB: std::sync::OnceLock<Option<u64>> = std::sync::OnceLock::new();
+    let set = *FLOOR_MB.get_or_init(|| {
+        std::env::var("VICTORY_TEXTURE_FLOOR_MB")
+            .ok()
+            .and_then(|v| v.trim().parse::<u64>().ok())
+            .map(|mb| mb.min(16 << 10) << 20)
+    });
+    let floor = match set {
+        Some(bytes) => bytes,
+        None if crate::draw::texture_auto_vram() => texture_floor_bytes(memory.map(|[budget, ..]| budget)),
+        None => texture_floor_bytes(None),
     };
+    static SAID: std::sync::Once = std::sync::Once::new();
+    SAID.call_once(|| {
+        tracing::info!(
+            floor_mb = floor >> 20,
+            set_by_floor_mb = set.is_some(),
+            auto_vram = crate::draw::texture_auto_vram(),
+            budget_mb = memory.map_or(0, |[budget, ..]| budget >> 20),
+            "the title's textures are made up to this floor before the card's budget is asked \
+             (VICTORY_TEXTURE_FLOOR_MB, VICTORY_TEXTURE_AUTO_VRAM=1 for a quarter of the budget)"
+        );
+    });
     if filled < floor {
         return true;
     }
```

