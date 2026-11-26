# Automated test with a score

This test runs the title on VIctory and presses Enter by itself through the menus until the first 3D scene. It records milestones and computes a 0–100 score. Everything runs on your machine. Only `*.score.md`/`*.score.json`, which contain numbers alone, come back to the repository.

| File | Role |
|---|---|
| [Iniciar-Rodada.ps1](Iniciar-Rodada.ps1) ("start run") | Launcher: checks the hash and firewall, restores the seed save, sets the `VICTORY_*` variables, starts the runtime and opens the watcher |
| [Vigiar-Rodada.ps1](Vigiar-Rodada.ps1) ("watch run") | Watcher: follows the log, writes the key file, records milestones and computes the score when the game closes |
| [Medir-Rodada.ps1](Medir-Rodada.ps1) ("measure run") | Extractor: summarizes one or more `.stderr` logs (world, VRAM, mipmaps, COPY queue, worker, DirectStorage, black frames) |
| [harness.example.toml](harness.example.toml) | Configuration template. Copy it to `harness.toml`, which Git ignores |
| [patches/](patches/README.md) | Runtime diffs the test depends on |

**Origin.** These are the launcher, watcher and extractor from candidate 4 (2026-11-26).

- **Launcher:** generalized. Paths come from `harness.toml` or parameters, the firewall rule is found by program rather than by name, and the run folder cannot be inside the repository.
- **Watcher:** two changes. Its messages are in English, and `score.json` stores only the log's file name.
- **Extractor:** only the messages changed.
- **Parameter names and score keys** stay in Portuguese, so existing runs and notes remain compatible.

## Prerequisites

1. A `victory.exe` built with the [patches](patches/README.md) and `--features diagnostics`.
2. The title's executable, from your own console's dump.
3. A run folder outside the repository, containing:
   - `data-semente\` ("seed data"): the starting save, copied to `data\` on every run (`-SemSemente` turns this off);
   - `cache\`: optional, a warm shader cache.
4. Windows Firewall on, and one blocking outbound rule per executable. In a PowerShell window **as administrator**:

   ```powershell
   New-NetFirewallRule -DisplayName 'VIctory runtime offline' -Direction Outbound -Action Block -Profile Any -Program '<path to victory.exe>'
   ```

   ```powershell
   New-NetFirewallRule -DisplayName 'VIctory title offline' -Direction Outbound -Action Block -Profile Any -Program '<path to the title executable>'
   ```

## Running

Run everything in a PowerShell window **as administrator**, because the launcher reads the firewall rules.

Check the hash, the firewall and the mapping, without running the title:

```powershell
.\harness\Iniciar-Rodada.ps1 -Config .\harness\harness.toml -Rapido -MapOnly
```

Full quick test. Press **F9** when the game becomes playable; the game closes 2 minutes later:

```powershell
.\harness\Iniciar-Rodada.ps1 -Config .\harness\harness.toml -Rapido -FecharAposJogavelS 120
```

Series X reference, with the same watcher and score:

```powershell
.\harness\Iniciar-Rodada.ps1 -Config .\harness\harness.toml -Console series-x -AutoEnter -FecharAposJogavelS 120
```

Summary of the logs of one or more runs:

```powershell
.\harness\Medir-Rodada.ps1 -Log 'D:\victory\runs\rapido-*.stderr'
```

### Parameters

| Parameter | Meaning |
|---|---|
| `-Config` | `harness.toml` with `runtime_exe`, `runtime_sha256`, `title_exe`, `run_dir` |
| `-Rapido` | quick preset (see below) |
| `-Console series-x\|series-s` | console profile passed to the runtime |
| `-DisplayMode WxH` | `VICTORY_DISPLAY_MODE` reported to the game |
| `-AutoEnter`, `-EnterApos`, `-EnterIntervalo` | automatic Enter; first press after N s; interval between presses |
| `-FecharAposJogavelS N` | close the game N s after F9 (playable) |
| `-MaxMinutos N` | close the game after N minutes in total |
| `-SemSemente` | do not restore `data\` from `data-semente\` |
| `-SemVigia` | do not open the watcher (no automatic Enter, no score) |
| `-DiscoWorkers N` | `VICTORY_DSTORAGE_WORKERS` (patch 05) |
| `-Fila 0\|1` | `VICTORY_QUEUE2` (readback on the COPY queue) |
| `-Worker 0\|1` | `VICTORY_HEAP_WORKER` |
| `-Mips 0\|1` | `VICTORY_LEVELS_ON_DEMAND` |
| `-PequenosMB` | `VICTORY_TILES_SMALL_WHEN_FULL_MB` |
| `-ReservaAlvosMB` | `VICTORY_CARD_ROOM_FOR_TARGETS_MB` |
| `-PisoTexturasMB` | `VICTORY_TEXTURE_FLOOR_MB` (patch 02) |
| `-TexturaAuto` | `VICTORY_TEXTURE_AUTO_VRAM=1` |
| `-SemContadores` | turns off `VICTORY_FRAME_LOG` and `VICTORY_DSTORAGE_STATS` |
| `-Capturar` | `VICTORY_CAPTURE` into the run folder (captures stay local) |
| `-MapOnly` | map without running |

### What `-Rapido` turns on

- `--console series-s`: the game renders smaller internally and scales the image itself (the fork measured 1280×720 inside 1920×1080). Needs patch 03; without it, the interface is black.
- `VICTORY_DISPLAY_MODE=1280x720`. It is cheap, but the fork measured that the game ignores the reported mode.
- Automatic Enter, the seed save, counters (`VICTORY_FRAME_LOG=1`, `VICTORY_DSTORAGE_STATS=1`) and the watcher.

Each item can be overridden with its parameter.

## What the watcher does

It only reads the log and the clock. Its only actions on the game are writing the key file and, if you ask, closing the process at the end.

- **Automatic Enter:**
  - starts at 20 s (`-EnterApos`) and repeats every 6 s (`-EnterIntervalo`);
  - only while the game is on a light screen: up to 50 draws per frame (menu, loading, character select);
  - stops for good at the first frame with more than 1,000 draws, so nothing is pressed during the cutscene.
- **Milestones:** first frame, first and last Enter, first 3D scene, playable (F9), first save written after the 3D scene, and free marks (F10). They all go to `<log>.marcos.log`.
- **Ending:** `-FecharAposJogavelS N` closes the game N seconds after F9; `-MaxMinutos N` closes it on a timer.
- **Output:** `<log>.score.json` and `<log>.score.md`.

## Score

| Component (key) | Weight | Computation |
|---|---|---|
| progress (`progresso`) | 30 | 10 = showed an image; 50 = reached the first 3D scene; 100 = playable (F9) |
| speed (`velocidade`) | 25 | median in-world FPS ÷ 30 × 100, capped at 100. Uses the playable stretch if F9 was pressed, otherwise the cutscene |
| loading (`carregamento`) | 20 | 100 if the first 3D scene appears within 60 s; 0 at 20 min; linear in between |
| shaders (`shaders`) | 15 | % of world draws not dropped for lack of a pipeline (per-frame median) |
| image (`imagem`) | 10 | 0–100 score from comparing against your reference recording (`cutscene-lab/score.py`), passed with `-ImagemScore` |

- **Total:** weighted average of the components that have data. A component without data drops out of the average; it does not count as zero.
- **World:** samples with more than 1,000 draws per frame (`-MundoDraws`).
- **Weights and scales:** these are conventions of this test. If you change any, say so in the PR, because scores from different watcher versions are not comparable. Cite the SHA-256 of `Vigiar-Rodada.ps1` in the report.

### What to publish

- **Goes into the PR** (from `.score.md`):
  - the total and the components;
  - the milestones in seconds;
  - the FPS medians and p95;
  - the shader counts.
- **Stays on the machine:** the `.stderr`, the `.stdout`, the `.marcos.log`, the key file, the `.settings.txt` and the run folder.
- **Log path:** in this copy of the watcher, the `log` field of `score.json` holds only the file name, not the local path.

## Known limitations

- F9 is manual. The first save after the 3D scene is an automatic hint, but it does not replace F9 in the score.
- Key reading uses `GetAsyncKeyState`, so F9 works whichever window has focus.
- The image score needs a local reference recording. Without it, the component stays out of the average.
- Not yet verified with candidate 4 [relatado]:
  - the Series S image with both planes;
  - the game's response to `VICTORY_KEYS_FILE`;
  - the gain from `-DiscoWorkers`.
