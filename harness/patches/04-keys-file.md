# VICTORY_KEYS_FILE: teclas dirigidas por arquivo

Candidata 4, só em build com `--features diagnostics`. Cada vez que o conteúdo do arquivo muda, o runtime segura por 0,2 s a tecla nomeada na última palavra da última linha (mesmos nomes de `VICTORY_KEYS`). É o que permite ao `Vigiar-Rodada.ps1` apertar Enter só quando o jogo está em menu ou loading.

- **Aplicar em ordem**, sobre `fxceless/victory-fork` no commit `f6a09d3b` com o PR #45 (candidata 1). Os números de linha dos hunks seguem essa cadeia.
- Licença: o VIctory e o fork são GPL-3.0. Este diff é derivado desse código e segue a mesma licença.
- Para aplicar: copie o bloco `diff` para `04-keys-file.patch` e rode `git apply --check 04-keys-file.patch`, depois `git apply 04-keys-file.patch`.

## `crates/victory-hle/src/modules/gameinput.rs`

```diff
--- a/crates/victory-hle/src/modules/gameinput.rs
+++ b/crates/victory-hle/src/modules/gameinput.rs
@@ -1203,25 +1203,28 @@
     /// letter, a digit, or `Enter`, `Esc`, `Tab`, `Back`, `Up`, `Down`,
     /// `Left`, `Right` (the stand-in pad's table maps them to buttons).
     #[cfg(feature = "diagnostics")]
+    fn key_code(key: &str) -> Option<u8> {
+        Some(match key.trim() {
+            "Enter" => 0x0D,
+            "Esc" => 0x1B,
+            "Tab" => 0x09,
+            "Back" => 0x08,
+            "Up" => 0x26,
+            "Down" => 0x28,
+            "Left" => 0x25,
+            "Right" => 0x27,
+            k if k.len() == 1 && k.as_bytes()[0].is_ascii_alphanumeric() => k.as_bytes()[0].to_ascii_uppercase(),
+            _ => return None,
+        })
+    }
+
+    #[cfg(feature = "diagnostics")]
     fn scripted() -> Vec<u8> {
         static SCRIPT: LazyLock<(Instant, Vec<(Duration, u8)>)> = LazyLock::new(|| {
             let list = std::env::var("VICTORY_KEYS").unwrap_or_default();
             let keys = list.split(',').filter_map(|entry| {
                 let (at, key) = entry.split_once(':')?;
-                let vk = match key.trim() {
-                    "Enter" => 0x0D,
-                    "Esc" => 0x1B,
-                    "Tab" => 0x09,
-                    "Back" => 0x08,
-                    "Up" => 0x26,
-                    "Down" => 0x28,
-                    "Left" => 0x25,
-                    "Right" => 0x27,
-                    k if k.len() == 1 && k.as_bytes()[0].is_ascii_alphanumeric() => {
-                        k.as_bytes()[0].to_ascii_uppercase()
-                    }
-                    _ => return None,
-                };
+                let vk = key_code(key)?;
                 Some((
                     Duration::try_from_secs_f64(at.trim().parse().ok()?).ok()?,
                     vk,
@@ -1231,10 +1234,63 @@
         });
         let (start, keys) = &*SCRIPT;
         let now = start.elapsed();
-        keys.iter()
+        let mut down: Vec<u8> = keys
+            .iter()
             .filter(|&&(at, _)| (at..at + Duration::from_millis(200)).contains(&now))
             .map(|&(_, vk)| vk)
-            .collect()
+            .collect();
+        if let Some(vk) = from_file()
+            && !down.contains(&vk)
+        {
+            down.push(vk);
+        }
+        down
+    }
+
+    /// Debugging aid: `VICTORY_KEYS_FILE=<path>`. Each time the file's
+    /// contents change, the key named by the last word of its last line (as
+    /// in `VICTORY_KEYS`) is held for 0.2 s, with or without focus. A
+    /// launcher that watches the log can press Enter when the title waits
+    /// for it, and stop once the world shows. Read at most every 100 ms; the
+    /// contents first seen count as a change only if not empty.
+    #[cfg(feature = "diagnostics")]
+    fn from_file() -> Option<u8> {
+        use std::sync::Mutex;
+        struct State {
+            checked: Option<Instant>,
+            seen: Vec<u8>,
+            holding: Option<(Instant, u8)>,
+        }
+        static PATH: LazyLock<Option<std::path::PathBuf>> =
+            LazyLock::new(|| std::env::var_os("VICTORY_KEYS_FILE").map(std::path::PathBuf::from));
+        static STATE: Mutex<State> = Mutex::new(State {
+            checked: None,
+            seen: Vec::new(),
+            holding: None,
+        });
+        let path = PATH.as_ref()?;
+        let mut s = STATE.lock().unwrap_or_else(|e| e.into_inner());
+        if let Some((since, vk)) = s.holding {
+            if since.elapsed() < Duration::from_millis(200) {
+                return Some(vk);
+            }
+            s.holding = None;
+        }
+        if s.checked.is_some_and(|t| t.elapsed() < Duration::from_millis(100)) {
+            return None;
+        }
+        s.checked = Some(Instant::now());
+        let bytes = std::fs::read(path).ok()?;
+        if bytes == s.seen {
+            return None;
+        }
+        s.seen = bytes;
+        let text = String::from_utf8_lossy(&s.seen).into_owned();
+        let word = text.lines().rev().find(|l| !l.trim().is_empty())?.split_whitespace().last()?;
+        let vk = key_code(word)?;
+        tracing::info!(key = word, "a scripted key from VICTORY_KEYS_FILE");
+        s.holding = Some((Instant::now(), vk));
+        Some(vk)
     }
 
     /// The foreground window is one of ours (the title's or our fallback).
```

