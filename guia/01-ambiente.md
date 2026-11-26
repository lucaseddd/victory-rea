# 1. Ambiente

## Onde cada coisa fica

```
<workspace local>\               fora do repositório
  victory-fork-<commit>\         fonte do runtime (git do fork)
  cand<N>\                       cópia do fonte com os patches da candidata N
  cand<N>-dist\victory.exe       build compilada (+ victory.pdb, D3D12\)
  cand<N>-run\                   rodadas: logs, cache, data, data-semente
  REA-COORD\evidence\...         dados brutos de cada tentativa
<este repositório>\              só texto: guia, harness, relatórios
```

Regras:

- **Uma pasta por candidata.** Nunca recompile em cima de uma candidata já medida. Copie o fonte, aplique a mudança e compile em `cand<N+1>`.
- **O dump do título fica em leitura.** Ninguém escreve nele.
- **Derivados fora do repositório.** Cache de shaders, pipelines, saves, capturas e logs ficam na pasta da rodada. O launcher do harness recusa uma pasta de rodada dentro do repositório.

## Offline

O título roda sem rede. Antes da primeira rodada de cada exe novo, crie a regra de saída bloqueada (PowerShell como administrador):

```powershell
New-NetFirewallRule -DisplayName 'VIctory runtime offline' -Direction Outbound -Action Block -Profile Any -Program '<caminho do victory.exe>'
```

O launcher confere se o firewall está ligado nos três perfis e se há uma regra de bloqueio para o runtime e outra para o título. Como ler as regras exige elevação, sem administrador ele para com "Acesso negado". Isso é esperado: não contorne.

## Compilar

```powershell
cargo rustc --offline --locked --release --features diagnostics -p victory --bin victory -- -C "link-arg=/EXPORT:D3D12SDKPath,DATA" -C "link-arg=/EXPORT:D3D12SDKVersion,DATA"
```

- `--features diagnostics` liga o `VICTORY_KEYS`, o `VICTORY_KEYS_FILE`, a detecção de quadro preto e outros auxílios.
- Os exports ativam o Agility SDK de `D3D12\` ao lado do exe. Confira com `dumpbin /exports victory.exe`.
- Fixe o toolchain (`cargo +<versão>`) e anote a versão no relatório da build.
- Rode os testes do crate que você mudou (`cargo test -p victory-gpu`, `-p victory-hle`). Falhas antigas, presentes em todas as árvores, entram no relatório como "falha antiga", com o nome do teste.

## Antes de executar

```powershell
.\harness\Iniciar-Rodada.ps1 -Config .\harness\harness.toml -MapOnly
```

O `-MapOnly` mapeia o título sem executar: confere o hash, o firewall e os imports faltando. Exit 0 com 0 imports faltando é o mínimo para pedir a GPU.
