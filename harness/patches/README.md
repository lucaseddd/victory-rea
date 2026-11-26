# Patches de runtime necessários para o teste

O teste automatizado depende de variáveis que não existem no VIctory upstream nem no commit base do fork. Os diffs estão em texto, um por arquivo, e foram gerados comparando as árvores das candidatas 1 → 2 → 3 → 4.

**Base:** `fxceless/victory-fork` no commit `f6a09d3b` + PR #45 (orçamento de texturas pela VRAM) + exports do Agility SDK 1.620.2. Aplique os patches nesta ordem.

| # | Patch | Variáveis | Origem | Necessário para |
|---|---|---|---|---|
| 01 | [dstorage-stats](01-dstorage-stats.md) | `VICTORY_DSTORAGE_STATS` | local (candidata 2) | linhas de DirectStorage no extrator; diagnóstico de carregamento |
| 02 | [texture-floor](02-texture-floor.md) | `VICTORY_TEXTURE_FLOOR_MB`; `VICTORY_TEXTURE_AUTO_VRAM` passa a ser opt-in | local (candidata 3, R13) | `-PisoTexturasMB`; evita a cutscene preta em placas de 6 GB |
| 03 | [planos-series-s-pr1081](03-planos-series-s-pr1081.md) | `VICTORY_PLANES`, `VICTORY_PLANE_ALPHA` | porte do fxceless PR #1081 (head `08ab0418`) | `-Rapido` / `--console series-s` com imagem |
| 04 | [keys-file](04-keys-file.md) | `VICTORY_KEYS_FILE` | local (candidata 4) | Enter automático do vigia |
| 05 | [dstorage-workers](05-dstorage-workers.md) | `VICTORY_DSTORAGE_WORKERS` | local (candidata 4) | `-DiscoWorkers` (opcional) |
| 06 | [small-why](06-small-why.md) | linha `small levels on a full card` | local (candidata 2) | diagnóstico de mipmaps (opcional) |

## Compilar

```powershell
cargo rustc --offline --locked --release --features diagnostics -p victory --bin victory -- -C "link-arg=/EXPORT:D3D12SDKPath,DATA" -C "link-arg=/EXPORT:D3D12SDKVersion,DATA"
```

- `--features diagnostics` é obrigatório: `VICTORY_KEYS_FILE` só existe nessa configuração.
- Os exports `D3D12SDKPath`/`D3D12SDKVersion` ativam o Agility SDK da pasta `D3D12\` ao lado do exe.
- Confira depois: `Get-FileHash victory.exe -Algorithm SHA256` e registre o hash no `harness.toml` (`runtime_sha256`).

Na candidata 4 de referência (2026-11-26, toolchain 1.98.1): `victory.exe` SHA-256 `2FFD8CB5F3E66C16E6CEC8005E778A76692A337FD1075CC3D3CD72991FF41973` [relatado]. Testes: `victory-gpu` 213 ok e 1 falha antiga (depth bounds, presente em todas as árvores), `victory-hle` 108/108 [relatado].

## Licença

O VIctory e o fork são GPL-3.0. Os diffs desta pasta derivam desse código e seguem a GPL-3.0. O `compose.rs` é do PR #1081 do fork, sem mudança, com o crédito do autor no cabeçalho.
