# 2. Identidade da build

Um endereço só vale para um binário. Todo relatório começa por estas linhas.

## Hash do executável e do PDB

```powershell
Get-FileHash .\victory.exe -Algorithm SHA256
```

```powershell
Get-FileHash .\victory.pdb -Algorithm SHA256
```

O upstream usa BLAKE3 como identidade de build. Qualquer um dos dois serve, desde que o relatório diga qual.

## GUID e age do PDB (RSDS)

O PE guarda no diretório de debug o registro CodeView (`RSDS`) com GUID, age e caminho do PDB. O par GUID/age liga o exe ao PDB certo.

```powershell
dumpbin /headers .\victory.exe | Select-String 'RSDS|Format:'
```

Publique o GUID e o age, mas não o caminho do PDB, que pode conter nomes de pasta da máquina.

## RVA e VA

- **VA** é o endereço com a base da imagem. No `victory.exe` x64 a base preferida é `0x140000000`, então `VA 0x1402AE4E3` = `RVA 0x2AE4E3`.
- **RVA** é o deslocamento a partir da base. Prefira RVA no relatório: não muda se a imagem for carregada em outra base.
- Ghidra mostra VA com a base do PE; `dumpbin /disasm` também. Converta antes de publicar e diga qual dos dois você usou.

Exemplo de linha de relatório:

```
`Host::relay_land` RVA 0x2A8D60 · build victory.exe sha256 D29834AE…378D772 · PDB GUID {59A6A622-…} age 1 [obs-local]
```

## Três builds, três mapas

As candidatas de 2026-11-26 tinham hashes diferentes, e os relatórios feitos na referência `988aa416` não valiam automaticamente para a candidata 1 [relatado]. Ao reaproveitar um achado de outra build:

1. Confira se o arquivo-fonte é idêntico (hash do `.rs`).
2. Procure o símbolo de novo no PDB da build nova.
3. Marque o achado como `[relatado]` até conferir.
