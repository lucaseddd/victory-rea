# 1. Environment

## Where everything lives

```
<local workspace>\               outside the repository
  victory-fork-<commit>\         runtime source (fork's git)
  cand<N>\                       copy of the source with candidate N's patches
  cand<N>-dist\victory.exe       built binary (+ victory.pdb, D3D12\)
  cand<N>-run\                   runs: logs, cache, data, data-semente
  REA-COORD\evidence\...         raw data for each attempt
<this repository>\               text only: guide, harness, reports
```

Rules:

- **One folder per candidate.** Never rebuild on top of a candidate that has already been measured. Copy the source, apply the change and build into `cand<N+1>`.
- **The title dump is read-only.** Nobody writes to it.
- **Derived data outside the repository.** Shader and pipeline caches, saves, captures and logs stay in the pipeline's `work_dir`. The harness refuses a `work_dir` inside the repository.

## Offline

The title runs without network access. Before the first run of each new exe, create the blocking outbound rule (PowerShell as administrator):

```powershell
New-NetFirewallRule -DisplayName 'VIctory runtime offline' -Direction Outbound -Action Block -Profile Any -Program '<path to victory.exe>'
```

The launcher checks that the firewall is on in all three profiles and that there is one blocking rule for the runtime and another for the title. Reading the rules requires elevation, so without administrator rights it stops with "Access denied". That is expected: do not work around it.

## Building

```powershell
cargo rustc --offline --locked --release --features diagnostics -p victory --bin victory -- -C "link-arg=/EXPORT:D3D12SDKPath,DATA" -C "link-arg=/EXPORT:D3D12SDKVersion,DATA"
```

- `--features diagnostics` enables `VICTORY_KEYS`, `VICTORY_KEYS_FILE`, black-frame detection and other aids.
- The exports activate the Agility SDK in `D3D12\` next to the exe. Check with `dumpbin /exports victory.exe`.
- Pin the toolchain (`cargo +<version>`) and record the version in the build report.
- Run the tests of the crate you changed (`cargo test -p victory-gpu`, `-p victory-hle`). Old failures that are present in every tree go in the report as "old failure", with the test name.

## Before running

```powershell
.\harness\Rodar-Versao.ps1 -Versao ultima -MapOnly
```

`-MapOnly` maps the title without running it, after checking the version's hash and the firewall rules, and reports missing imports. Exit 0 with 0 missing imports is the minimum before asking for the GPU.
