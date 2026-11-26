# Data policy

This follows the upstream VIctory asset policy (`docs/asset-policy.md`, rule #1): **nothing from the game is ever stored in this repository.**

## Not allowed, in any form

- Title assets: models, textures, shaders, audio, video, text, `.rpf` files and other packages.
- The title's executable or any part of it: sections, strings, tables, resources.
- Derived material: decompiled code or disassembly of the title, shader dumps, extracted tables, screenshots, recordings, RenderDoc/PIX captures.
- Build binaries: `.exe`, `.dll`, `.pdb`, `.lib`, shader and pipeline caches.
- Raw logs (`*.stderr`, `*.stdout`, `.log`, `.etl`, dumps). Only aggregate numbers come out of a log.
- Personal data: real names, e-mail addresses, paths containing a user name, hardware IDs.

## Allowed

- Build identity: the executable's hash (SHA-256 or BLAKE3) and the PDB's CodeView GUID/age.
- Function offsets and RVAs, with the VIctory symbol name (open source) or a name of our own.
- Aggregate numbers: medians, p95, counts, averages, maximums, small CSV tables.
- Runtime environment variables and configuration (`VICTORY_*`).
- Markdown reports, our own measurement and conversion scripts, and synthetic data those scripts generate.
- References to lines in the VIctory or fork source (`host.rs:9313`), which is open source.

When in doubt, leave it out. Describe the finding in words and cite the offset.

## How the rule is enforced

1. `.gitignore` works as an allowlist: it ignores everything and lets through only `.md`, `.yml`, `.yaml`, `.json`, `.csv`, `.ps1`, `.py` and `.toml`. `harness.toml` and `victory.toml`, which hold machine paths, are kept out.
2. `scripts/Test-RepoContent.ps1` rejects:
   - extensions outside the allowlist;
   - binaries;
   - files over 512 KiB;
   - long hex or base64 runs;
   - disassembly listings;
   - e-mail addresses;
   - Windows user-profile paths.
3. The `content-check` workflow runs the same script on every push and PR.

## If something slips through

A follow-up commit is not enough. Rewrite history (`git filter-repo --path <file> --invert-paths`), force-push and have everyone re-clone. Report it on the R00 Issue.
