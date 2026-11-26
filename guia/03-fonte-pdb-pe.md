# 3. From source to PE

VIctory is open source and the build ships its PDB. So the reverse engineering here is mostly **confirmation**: the source says what should happen; the PDB and the PE say what was compiled with that configuration.

## Flow

1. **Source.** Find the function and the variables that control it. Example: `queue2::second()` only returns a queue when `VICTORY_QUEUE2=1`.
2. **PDB.** Confirm the symbol exists and note its RVA. Small functions are often inlined; in that case, find the caller and the call site.
3. **PE.** In Ghidra, import `victory.exe` together with `victory.pdb` (File → Import, then Analysis with the PDB). Go to the RVA and check:
   - the expected call (for example, `ExecuteCommandLists` followed by `Signal`);
   - the branch controlled by the variable;
   - the order of operations (who publishes the fence after what).
4. **Cross-check.** `dumpbin /disasm /range:<start VA>,<end VA> victory.exe` gives a second reading without Ghidra. Record only the address and the name; the listing stays in the local evidence.
5. **Independent spot-check.** Another AI checks a sample of the claims. On 2026-11-26, R00 confirmed 8 of 8 addresses from R01/R02 in the candidate's PE [relatado].

## What becomes publishable text

| Allowed | Not allowed |
|---|---|
| `fence::set` called at RVA `0x2AE4E3`, after `Late::Write` | the surrounding instruction lines |
| "the COPY `Wait` sits in a loop over (fence, value) pairs" | the listing of the loop |
| "`VICTORY_QUEUE2=1` enables `BESIDE`, `Second::sent_up` and two COPY queues" | strings or tables copied from the title |
| hashes, GUID/age, RVAs, VIctory symbol names | anything from the title's executable |

The `Test-RepoContent` check rejects listings with an address, bytes and a mnemonic, and blocks of instructions. Do not try to get around it: describe the code in words.

## AI-assisted Ghidra

- Ask the AI one closed question at a time ("who calls `relay_land`, and with which fence?"), not "analyze the exe".
- Give it the RVA and the symbol name; it navigates faster and makes fewer mistakes.
- Require in the answer: address, symbol, the matching source line and the `[obs-local]` tag.
- Be wary of conclusions about the "default" branch that ignore the run's effective configuration (`<log>.settings.txt`).
