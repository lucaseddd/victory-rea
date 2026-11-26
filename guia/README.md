# REA guide for VIctory

REA here means assisted reverse engineering. An AI (or you) reads the VIctory source, the PDB and the built runtime's PE, using Ghidra and `dumpbin`. The goal is to explain where frame time goes and what changes in a candidate build. The target is **the runtime** (`victory.exe`, open source). The title's executable is neither analyzed nor quoted here.

| Chapter | Contents |
|---|---|
| [1. Environment](01-ambiente.md) | Folders outside the repository, offline firewall, build, Agility SDK, hashes |
| [2. Build identity](02-identidade.md) | SHA-256, PDB GUID/age, RVA vs VA, making sure you analyze the right binary |
| [3. Source to PE](03-fonte-pdb-pe.md) | The source → PDB → PE flow with Ghidra and `dumpbin`, and what may be published |
| [4. Measuring](04-medir.md) | Log lines, `VICTORY_*` counters, the comparable protocol, the GPU lock |
| [5. Area map](05-areas.md) | Per area: symbols, variables and findings already checked on candidate 1 |
| [6. Pitfalls](06-armadilhas.md) | What has misled earlier analyses |
| [Automated test](../harness/README.md) | Launcher, watcher and score |

## The cycle on one page

1. **Pick the question.** One Issue per task (R00–R15), each with one area. Example: "who waits for which fence value after the readback?"
2. **Pin the build.** The exe's hash and the PDB's GUID/age. Without them, no address is valid.
3. **Read the source.** Find the path in the Rust code (`host.rs`, `queue.rs`, …) and the `VICTORY_*` variables that control it.
4. **Check the PDB and the PE.** Do the symbols exist? Was the function inlined? Is the branch the source suggests actually in the binary with this configuration?
5. **Measure.** Run with the launcher and the watcher, with the GPU reserved, and extract aggregates.
6. **Report.** One PR per attempt, text only: offsets, aggregate numbers and the `[obs-local]`/`[relatado]`/`[estimado]` tags.
7. **Consolidate.** The consolidating AI merges attempts into a candidate, runs the test and publishes the score.
