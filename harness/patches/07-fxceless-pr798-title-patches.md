# Title patches: the fxceless PR #798 port (Series S upscaler)

Candidate 5. Port of fxceless/victory-fork PR #798. On the Series S profile the title picks FSR 4 as its upscaler, and every world frame comes out black. The patch makes the title's own upscaler choice return the Series X value. It is a per-build table (`KNOWN_BUILDS`, `CodePatch`) keyed by the executable's BLAKE3 hash, applied to the loaded image (`PreparedImage::patch`) by `apply_title_patches` when `VICTORY_TITLE_PATCHES` allows it. The table has one entry, for build `b99f876b` (the executable's BLAKE3 hash), with two code patches at per-build RVAs. Each write is guarded by a short byte signature, and the bytes written are `mov eax, 6; ret`. The only data taken from the executable is that hash, the RVAs and the guard signatures, which the asset policy allows.

- **Apply after** patches 01–06, on the same base. Hunk line numbers follow that chain.
- License: GPL-3.0, like the rest of VIctory and the fork.
- To apply: copy each `diff` block to a `.patch` file, run `git apply --check`, then `git apply`.

## `crates/victory-game/src/lib.rs`

```diff
--- a/crates/victory-game/src/lib.rs
+++ b/crates/victory-game/src/lib.rs
@@ -12,10 +12,51 @@
     pub label: &'static str,
     /// BLAKE3 of the original executable, hex.
     pub blake3: &'static str,
+    /// Changes to its code made before it is mapped.
+    pub patches: &'static [CodePatch],
 }
 
-/// Builds we support. Empty until the executable is available.
-pub const KNOWN_BUILDS: &[KnownBuild] = &[];
+/// A change to title code: at `rva`, the bytes `expect` (a short signature
+/// checked before anything is written) become `write`, our own code.
+#[derive(Debug, Clone, Copy)]
+pub struct CodePatch {
+    /// Our name for it, as logged.
+    pub name: &'static str,
+    pub rva: u32,
+    pub expect: &'static [u8],
+    pub write: &'static [u8],
+}
+
+/// `mov eax, 6; ret`: the upscaler a Series X uses.
+const UPSCALER_6: &[u8] = &[0xb8, 0x06, 0x00, 0x00, 0x00, 0xc3];
+
+/// Builds we support. Port of fxceless/victory-fork pull request #798.
+pub const KNOWN_BUILDS: &[KnownBuild] = &[KnownBuild {
+    label: "Xbox Series master",
+    blake3: "b99f876b74d4a77f03af5f878223b27bd647b5c35a79d5decd9f716504239e93",
+    // The title picks its upscaler by console: on a Series S with the
+    // FidelityFX upscaler's capability, FSR 4 (type 7), else its own
+    // (type 6, as on a Series X). FSR 4's output never reaches the screen
+    // here (every world frame is black with `--console series-s`), and
+    // without its DLL the title divides by zero. Both functions that make
+    // the choice return 6, so a Series S runs its own render profile (about
+    // 30% fewer milliseconds a frame than a Series X) with the upscaler that
+    // works.
+    patches: &[
+        CodePatch {
+            name: "upscaler choice",
+            rva: 0x7e_93f0,
+            expect: &[0x48, 0x83, 0xec, 0x28, 0x80, 0x3d],
+            write: UPSCALER_6,
+        },
+        CodePatch {
+            name: "upscaler choice (the per-frame copy)",
+            rva: 0x540_0190,
+            expect: &[0x48, 0x83, 0xec, 0x28, 0x48, 0x8b],
+            write: UPSCALER_6,
+        },
+    ],
+}];
 
 /// Looks up a build by the BLAKE3 hash of its executable.
 pub fn identify(blake3_hex: &str) -> Option<&'static KnownBuild> {
@@ -23,3 +64,25 @@
         .iter()
         .find(|b| b.blake3.eq_ignore_ascii_case(blake3_hex))
 }
+
+#[cfg(test)]
+mod tests {
+    use super::*;
+
+    #[test]
+    fn known_builds_are_well_formed() {
+        for build in KNOWN_BUILDS {
+            assert_eq!(build.blake3.len(), 64);
+            assert!(build.blake3.bytes().all(|b| b.is_ascii_hexdigit()));
+            assert_eq!(
+                identify(&build.blake3.to_uppercase()).map(|b| b.label),
+                Some(build.label)
+            );
+            for patch in build.patches {
+                assert!(!patch.write.is_empty(), "{}", patch.name);
+                assert_eq!(patch.expect.len(), patch.write.len(), "{}", patch.name);
+            }
+        }
+        assert!(identify("00").is_none());
+    }
+}
```

## `crates/victory-loader/src/prepare.rs`

```diff
--- a/crates/victory-loader/src/prepare.rs
+++ b/crates/victory-loader/src/prepare.rs
@@ -22,12 +22,58 @@
     pub bytes: Vec<u8>,
     /// BLAKE3 of the original bytes: identifies the exact build.
     pub original_hash: blake3::Hash,
+    /// BLAKE3 of the title-code patches applied ([`PreparedImage::patch`]),
+    /// if any: part of the copy's file name, so a patched copy and the
+    /// plain one never stand in for each other.
+    pub patched: Option<blake3::Hash>,
 }
 
 impl PreparedImage {
-    /// File name for the patched copy, unique per original build.
+    /// File name for the patched copy, unique per original build (and per
+    /// set of title-code patches).
     pub fn file_name(&self) -> String {
-        format!("victory-image-{}.dll", &self.original_hash.to_hex()[..16])
+        match &self.patched {
+            None => format!("victory-image-{}.dll", &self.original_hash.to_hex()[..16]),
+            Some(p) => format!(
+                "victory-image-{}-p{}.dll",
+                &self.original_hash.to_hex()[..16],
+                &p.to_hex()[..8]
+            ),
+        }
+    }
+
+    /// Changes title code: each patch is (RVA, the bytes expected there,
+    /// the bytes to write). Every expected run is checked before anything
+    /// is written, so a patch made for another build of the title changes
+    /// nothing and is an error. (fxceless pull request #798.)
+    pub fn patch(&mut self, patches: &[(u32, Vec<u8>, Vec<u8>)]) -> Result<(), PrepareError> {
+        let mut at = Vec::with_capacity(patches.len());
+        for (rva, old, new) in patches {
+            if old.len() != new.len() || new.is_empty() {
+                return Err(PrepareError::Patch(
+                    "a title patch's old and new bytes differ in length",
+                ));
+            }
+            let offset = self
+                .info
+                .rva_to_file_offset(*rva)
+                .ok_or(PrepareError::Patch("a title patch's RVA is not file-backed"))? as usize;
+            if self.bytes.get(offset..offset + old.len()) != Some(old.as_slice()) {
+                return Err(PrepareError::Patch(
+                    "a title patch's expected bytes are not there (another build?)",
+                ));
+            }
+            at.push(offset);
+        }
+        let mut id = blake3::Hasher::new();
+        for ((rva, old, new), offset) in patches.iter().zip(at) {
+            self.bytes[offset..offset + new.len()].copy_from_slice(new);
+            id.update(&rva.to_le_bytes());
+            id.update(old);
+            id.update(new);
+        }
+        self.patched = Some(id.finalize());
+        Ok(())
     }
 }
 
@@ -110,6 +156,7 @@
         info,
         bytes,
         original_hash: blake3::hash(original),
+        patched: None,
     })
 }
 
@@ -280,4 +327,31 @@
         let b = prepare(&original).unwrap();
         assert_eq!(a.file_name(), b.file_name());
     }
-}
+
+    /// fxceless pull request #798.
+    #[test]
+    fn title_patches_check_before_they_write() {
+        let original = std::fs::read(std::env::current_exe().unwrap()).unwrap();
+        let mut prepared = prepare(&original).unwrap();
+        let plain = prepared.file_name();
+        let section = prepared.info.sections[0].clone();
+        let rva = section.rva + 16;
+        let at = prepared.info.rva_to_file_offset(rva).unwrap() as usize;
+        let old = prepared.bytes[at..at + 4].to_vec();
+        let new: Vec<u8> = old.iter().map(|b| !b).collect();
+
+        // Wrong expected bytes (another build): an error, nothing written.
+        let before = prepared.bytes.clone();
+        let wrong = (rva, new.clone(), old.clone());
+        assert!(prepared.patch(&[(rva, old.clone(), new.clone()), wrong]).is_err());
+        assert_eq!(prepared.bytes, before);
+        assert_eq!(prepared.file_name(), plain);
+        assert!(prepared.patch(&[(rva, old.clone(), vec![0])]).is_err());
+
+        prepared.patch(&[(rva, old.clone(), new.clone())]).unwrap();
+        assert_eq!(&prepared.bytes[at..at + 4], new.as_slice());
+        let patched = prepared.file_name();
+        assert_ne!(patched, plain, "a patched copy has a file name of its own");
+        assert!(patched.starts_with(plain.trim_end_matches(".dll")));
+    }
+}
```

## `apps/victory/src/run.rs`

```diff
--- a/apps/victory/src/run.rs
+++ b/apps/victory/src/run.rs
@@ -20,12 +20,14 @@
     victory_hle::modules::lifecycle::wait_for_previous();
     let cfg = victory_core::Config::load()?;
     let original = std::fs::read(exe).with_context(|| format!("reading {}", exe.display()))?;
-    let prepared = victory_loader::prepare(&original)?;
+    let mut prepared = victory_loader::prepare(&original)?;
     let hash = prepared.original_hash.to_hex();
-    match victory_game::identify(&hash) {
+    let build = victory_game::identify(&hash);
+    match build {
         Some(build) => println!("build          {} ({hash})", build.label),
         None => println!("build          unknown ({hash})"),
     }
+    apply_title_patches(&mut prepared, build)?;
 
     let images = cfg.cache_subdir("images")?;
     victory_hle::modules::d3d12x::use_shader_cache(cfg.cache_subdir("shaders")?);
@@ -342,3 +344,55 @@
 pub fn run(_: &Path, _: Unimplemented, _: bool, _: bool, _: Console) -> Result<()> {
     anyhow::bail!("running titles requires Windows")
 }
+
+/// Bytes as lower-case hex.
+#[cfg(windows)]
+fn hex_str(bytes: &[u8]) -> String {
+    bytes.iter().map(|b| format!("{b:02x}")).collect()
+}
+
+/// The known build's code patches (`VICTORY_TITLE_PATCHES=0`: none), then
+/// any from `VICTORY_TITLE_PATCH=<rva>:<old hex>:<new hex>,...`. The old
+/// bytes must be there (another build of the title is refused), and the
+/// patched copy has a file name of its own. fxceless pull request #798.
+#[cfg(windows)]
+fn apply_title_patches(
+    prepared: &mut victory_loader::PreparedImage,
+    build: Option<&victory_game::KnownBuild>,
+) -> Result<()> {
+    let mut patches = Vec::new();
+    let mut names = Vec::new();
+    if std::env::var("VICTORY_TITLE_PATCHES").as_deref() != Ok("0") {
+        for p in build.map_or(&[][..], |b| b.patches) {
+            patches.push((p.rva, p.expect.to_vec(), p.write.to_vec()));
+            names.push(p.name.to_owned());
+        }
+    }
+    let spec = std::env::var("VICTORY_TITLE_PATCH").unwrap_or_default();
+    for one in spec.split(',').filter(|p| !p.trim().is_empty()) {
+        let parts: Vec<&str> = one.split(':').collect();
+        anyhow::ensure!(parts.len() == 3, "VICTORY_TITLE_PATCH entry is not <rva>:<old>:<new>: {one}");
+        let rva = u32::from_str_radix(parts[0].trim().trim_start_matches("0x"), 16)?;
+        patches.push((rva, from_hex(parts[1])?, from_hex(parts[2])?));
+        names.push("VICTORY_TITLE_PATCH".to_owned());
+    }
+    if patches.is_empty() {
+        return Ok(());
+    }
+    prepared.patch(&patches)?;
+    for ((rva, old, new), name) in patches.iter().zip(names) {
+        println!("title patch    +{rva:#x} {name}: {} -> {}", hex_str(old), hex_str(new));
+    }
+    Ok(())
+}
+
+/// Bytes from hex digits.
+#[cfg(windows)]
+fn from_hex(s: &str) -> Result<Vec<u8>> {
+    let s = s.trim();
+    anyhow::ensure!(s.len().is_multiple_of(2), "odd hex length: {s}");
+    (0..s.len())
+        .step_by(2)
+        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).map_err(anyhow::Error::from))
+        .collect()
+}
```

