# 2. Build identity

An address is only valid for one binary. Every report starts with these lines.

## Executable and PDB hashes

```powershell
Get-FileHash .\victory.exe -Algorithm SHA256
```

```powershell
Get-FileHash .\victory.pdb -Algorithm SHA256
```

Upstream uses BLAKE3 as the build identity. Either works, as long as the report says which one.

## PDB GUID and age (RSDS)

The PE stores the CodeView record (`RSDS`) in its debug directory, with the GUID, the age and the PDB path. The GUID/age pair ties the exe to the right PDB.

```powershell
dumpbin /headers .\victory.exe | Select-String 'RSDS|Format:'
```

Publish the GUID and age, but not the PDB path, which may contain folder names from the machine.

## RVA and VA

- **VA** is the address including the image base. For the x64 `victory.exe` the preferred base is `0x140000000`, so `VA 0x1402AE4E3` = `RVA 0x2AE4E3`.
- **RVA** is the offset from the base. Prefer RVAs in reports: they do not change if the image loads at a different base.
- Ghidra shows VAs with the PE's base, and so does `dumpbin /disasm`. Convert before publishing and say which one you used.

Example report line:

```
`Host::relay_land` RVA 0x2A8D60 · build victory.exe sha256 D29834AE…378D772 · PDB GUID {59A6A622-…} age 1 [observed]
```

## Three builds, three maps

The candidates of 2026-11-26 had different hashes, and reports made on the `988aa416` reference did not automatically apply to candidate 1 [reported]. When reusing a finding from another build:

1. Check whether the source file is identical (hash of the `.rs`).
2. Look the symbol up again in the new build's PDB.
3. Tag the finding `[reported]` until it is checked.
