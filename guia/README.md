# Guia de REA no VIctory

REA aqui é engenharia reversa assistida: uma IA (ou você) lê o fonte do VIctory, o PDB e o PE do runtime compilado, com Ghidra e `dumpbin`, para explicar onde o tempo do quadro vai e o que muda numa build candidata. O alvo é **o runtime** (`victory.exe`, código aberto). O executável do título não é analisado nem citado aqui.

| Capítulo | Conteúdo |
|---|---|
| [1. Ambiente](01-ambiente.md) | Pastas fora do repositório, firewall offline, build, Agility SDK, hashes |
| [2. Identidade da build](02-identidade.md) | SHA-256, PDB GUID/age, RVA × VA, como conferir que você analisa o binário certo |
| [3. Do fonte ao PE](03-fonte-pdb-pe.md) | Fluxo fonte → PDB → PE com Ghidra e `dumpbin`, e o que pode ser publicado |
| [4. Medir](04-medir.md) | Linhas do log, contadores `VICTORY_*`, protocolo comparável, lock da GPU |
| [5. Mapa das áreas](05-areas.md) | Por área: símbolos, variáveis e achados já conferidos na candidata 1 |
| [6. Armadilhas](06-armadilhas.md) | O que já enganou análises anteriores |
| [Teste automatizado](../harness/README.md) | Launcher, vigia e score |

## O ciclo em uma página

1. **Escolher a pergunta.** Uma Issue por tarefa (R00–R15), com uma área cada. Exemplo: "quem espera qual valor da fence depois do readback?"
2. **Fixar a build.** Hash do exe e GUID/age do PDB. Sem isso, nenhum endereço vale.
3. **Ler o fonte.** Achar o caminho no Rust (`host.rs`, `queue.rs`, …) e as variáveis `VICTORY_*` que o controlam.
4. **Conferir no PDB e no PE.** Os símbolos existem? A função foi inlined? O ramo que o fonte sugere está no binário com essa configuração?
5. **Medir.** Rodar com o launcher e o vigia, com a GPU reservada, e extrair agregados.
6. **Relatar.** Um PR por tentativa, só com texto: offsets, números agregados e as marcas `[obs-local]`/`[relatado]`/`[estimado]`.
7. **Consolidar.** A IA consolidadora junta as tentativas numa candidata, roda o teste e publica o score.
