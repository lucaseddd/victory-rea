# R27 · Keyboard and mouse that play like GTA V on PC, with PC key prompts · attempt R27-Teclas-01

- **Issue:** Marvisak/VIctory (thread linked from here) · **Area:** input, interface
- **Build:** R27-Atual (perfil T2 of [R27-Atual-02](../R27-Atual-02/report.md)) plus [source-changes.md](source-changes.md). The shader translator is untouched, so a warm pipeline cache stays warm.
- **Hardware:** RTX 3060 Laptop 6 GB, Ryzen 7 5700X, 32 GB RAM, Windows 10 22H2
- **Progress:** 75% (built and unit-tested; in-game confirmation of every item in progress, see the last section)

## One-line result

WASD already worked, but the rest of the keyboard and mouse did not feel like a PC game: the prompts showed Xbox buttons, Tab did not switch menu tabs, the mouse had to be captured by hand and aiming depended on that. This build fixes all of that without touching the renderer.

## What changed

| Before | Now |
|---|---|
| Prompts show Xbox buttons (A, B, LB, RT…) | **PC key caps over the title's own button pictures**: white rounded keys with the key name, a mouse with the button filled in for the triggers ([preview](https://raw.githubusercontent.com/lucaseddd/VIctory/docs/kbm-keycaps/docs/kbm/keycaps-preview.png)) |
| Tab was RB and LB sat on Shift+Tab / Page Up, so the menu asked for a button with no key | **Tab = LB** (weapon wheel, tab to the left), **Q = RB** (cover, tab to the right), as GTA V on PC; Page Up / Page Down stay as the other keys |
| Mouse look only with F2 | **A click in the window captures the mouse** as the camera, Alt+Tab back captures it again, Esc / P free it, F2 still toggles (`VICTORY_MOUSE_AUTOLOCK=0` turns this off) |
| Right/left mouse buttons ignored while the mouse was not captured | **Aim (RMB = LT) and fire (LMB = RT) work whenever the cursor is in the window** |
| Mouse sensitivity 0.045 | **0.09** by default in the launcher (`VICTORY_MOUSE_LOOK`) |
| D-pad right shown as an arrow | **E** (interact), as GTA V |

Key prompt layout (`VICTORY_KBM_GTA=1` + `VICTORY_PROMPTS=keys`): Menu Esc · View V · A Enter · B Back · X Space · Y F · LB Tab · RB Q · L3 Ctrl · R3 C · LT right mouse button · RT left mouse button · D-pad arrows, right = E · sticks WASD / IJKL.

### How the prompts work

The adaptation of Marvisak/VIctory#3433 (by @imjustprism) redraws the title's icon movie in memory when the streaming store hands it over: the back shape of each button becomes a key cap and the front shape the key's label, from the host's own font. Changes on top of the PR: the GTA layout table (`pad::gta_key`, chosen with `VICTORY_KBM_GTA`), labels written out like GTA V and RDR2 on PC (Enter, Back, Space, Ctrl), and a vector mouse for the triggers. The hook is enabled with `VICTORY_PROMPTS=keys` and only for build 1.0.2.1, whose offsets are known.

### Other tooling in this attempt

- [Prepare-PC.ps1](Prepare-PC.ps1): closes GPU miners (Kryptex, Salad), browsers, chat and overlays before playing. On this 6 GB card that raised the game's D3D12 budget to 5,228 MB and removed the drops under 3 fps.
- [Record-Session.ps1](Record-Session.ps1): started by the launcher; when the game closes it scores the session 0–100 from its own log (performance 60, stability 25, loading 15), appends it to a CSV and a Markdown history, and archives the build that ran.
- Window caption: `Bolinha | fps | mean fps | ms | build | VRAM used/budget | RAM | CPU% | GPU%`.

## Tested

- Builds with `cargo rustc --release --features diagnostics -p victory`; the key-prompt, pad and gfx unit tests pass (55).
- In game: `prompts keyboard keys: hook placed` at start, cache stays warm (515 MB library mapped), frame rate unchanged against the same profile (9.4 fps median).
- **In progress:** the user's in-game check of every prompt, the menu tabs with Tab/Q, auto-capture and aiming with the right button in the first mission. This report is updated with the result.

## Known gaps

- The console title reads the mouse as the right stick, so the fastest turn is the stick's full deflection: small movements now answer more, but a fast flick cannot turn faster than the stick allows.
- `victory-hle`'s unit tests do not build without the diagnostics feature (the per-process mute module needs `windows`); unrelated to these changes.
