<!-- Um PR por tentativa. Só texto: nada do jogo, nenhum binário, log bruto, captura ou disassembly do título. -->

## Tentativa

- Issue: Refs #<n>  <!-- use Closes #<n> só quando a tarefa chegar a 100% -->
- Tarefa e tentativa: R??-<Nome>-<NN>
- Área (label): <readback | vram-mips | directstorage | present | shaders | image-regression | …>
- Relatório: `tentativas/R??/R??-<Nome>-<NN>/relatorio.md`

## Build

- Executável e hash: <victory.exe sha256 …>
- PDB GUID/age: <{…} age n | indisponível>
- Base da build: <commit do fork, PRs aplicados>

## Cena e perfil

- Cena e checkpoints: <C1, M1 | análise estática>
- Perfil efetivo: <Controle/Candidato> · variáveis que diferem: <…>
- Resolução, escala, gráficos, cache: <…> · <frio/quente>

## Métricas

| Métrica | Antes | Depois | Marca |
|---|---|---|---|
| FPS renderizado | | | |
| Mediana ms / p95 ms | | | |
| % > 33,33 ms | | | |
| Travamentos | | | |
| VRAM típica / pico MB | | | |

Escreva **indisponível** quando não houver medição.

## Conferência

- [ ] Todo número está marcado como `[obs-local]`, `[relatado]` ou `[estimado]`
- [ ] Os hashes citados foram conferidos nesta máquina (`Get-FileHash`)
- [ ] `scripts/Test-RepoContent.ps1` passou localmente
- [ ] Nada do jogo: nenhum asset, executável, DLL, PDB, log bruto, captura, vídeo ou disassembly do título
- [ ] Nenhum dado pessoal (nome real, e-mail, caminho com nome de usuário)
