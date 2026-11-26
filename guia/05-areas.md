# 5. Mapa das áreas

Ponto de partida por área. RVAs e números são da **candidata 1** (`victory.exe` SHA-256 `D29834AE…378D772`, PDB GUID `{59A6A622-1BF5-4FB1-8733-C224125D0A00}` age 1), vêm dos relatórios de 2026-11-26 e estão marcados `[relatado]`. Em outra build, confira de novo.

Os números de log vêm de uma rodada do perfil Controle **fora de protocolo** (sem cena identificada nem janela exclusiva). Servem para orientar, não como baseline.

## Submissão e próximo quadro (R01, label `submissao`)

- `frame::wait` (RVA `0x252C40`) gera o token do quadro. `queue::execute` (`0x173BD0`) com `VICTORY_ASYNC_SUBMIT=1` empilha as partes e acorda a thread `victory-submit` (`queue::worker`, `0x173840`).
- `Host::submit` (`0x2BD070`) atribui `STARTED`, executa as listas na DIRECT e sinaliza `Host.fence`.
- `victory-relay` (`0x2EB520`) espera a fence, chama `Host::relay_land` (`0x2A8D60`) e só então publica a fence do guest e `FINISHED`.
- Com `VICTORY_ASYNC_PRESENT=0`, `queue::present` (`0x1765D0`) é síncrono e espera a thread de submissão. [relatado]

## Readback e fence (R02, R05, label `readback`)

- A fence do guest (`Fence::value`, +0x10) só é publicada no fim de `relay_land`, depois de `card_merge_relay`, `read_backs` e `Late::Write`. `fence::set` está em RVA `0x487D40`, chamado em `0x2AE4E3`. [relatado]
- `VICTORY_QUEUE2=0`: a cópia de volta roda na DIRECT. `=1`: roda na COPY `second.down` (`Lane::send`, `0x26D170`), com `Wait(host.fence)` antes. [relatado]
- `QUEUE2=1` não muda só a fila: liga também `BESIDE` (releitura de blocos de 64 KiB), `Second::sent_up` e cria duas filas COPY e três threads. Um A/B de `QUEUE2` mede tudo isso junto. [relatado, R05]
- No log do Controle (mundo): `relay_wait_card` mediana 163 ms e `settle_wait` 126 ms. [relatado]

## Execução na GPU (R06, label `gpu-exec`)

- `VICTORY_LATE_WAIT=1` faz o ramo adiantado (`ExecuteCommandLists` + `Signal` sem espera) ser o padrão.
- A DIRECT espera a COPY na GPU (`Second::hold`), e o present faz uma cópia serial do quadro para o back buffer.
- Falta medir com timestamps por fila (R03). [relatado]

## VRAM e mipmaps (R07, label `vram-mips`)

- `resource::room_with_memory` (`0x283190`): abaixo do piso, as texturas do título são criadas sem consultar o orçamento. Acima dele, só com uso < 90% do orçamento. O PR #45 troca o piso fixo de 2 GiB por `min(2 GiB, orçamento/4)`. [relatado]
- `targets_room_kept` reserva 3 GiB para render targets e cortou a criação de texturas com só 46% do orçamento em uso. [relatado]
- `tiles::show_from` (`0x488A10`) ajusta `MostDetailedMip` preservando o `ResourceMinLODClamp`. Com `VICTORY_TILES_SMALL_WHEN_FULL_MB=0`, 22–62 texturas tiled ficaram sem nenhum nível (pretas). [relatado]

## Worker de texturas (R08, label `texturas`)

- `VICTORY_HEAP_WORKER=1` move o upload para a thread `victory-heap` (`heap_worker::worker`, `0x1A87C0`). As listas resultantes entram na **DIRECT** antes das do título, não na COPY. [relatado]
- Sem o worker, `heap_textures` levou mediana de 15 ms e p95 de 74 ms na thread de gravação. [relatado]

## DirectStorage (R09, label `directstorage`)

- 16 workers (um por núcleo), staging de 32 MiB e `read_into` (`0x133BF0`) sem coalescimento. [relatado]
- Num HD SATA, o loading fica preso no disco: de 2,5 a 6 MB/s em leituras de ~16 KB, com só 2–5% contíguas. Coalescer não compensa. [relatado, candidata 4]
- Use o patch 01 (`VICTORY_DSTORAGE_STATS`) para medir e o patch 05 (`VICTORY_DSTORAGE_WORKERS`) para testar menos leituras simultâneas.

## Threads e esperas (R10, label `threads-sync`)

- No mundo, a thread de render ficou ~96% bloqueada. A DIRECT ficou ociosa ~443 ms por quadro de ~782 ms. [relatado]
- Maiores esperas: PSOs em `pipeline::make::wait` (~500 ms/quadro), o mutex `HostHeap::mirror` com `VICTORY_HEAP_LOCKS=0`, e `settle` por `WHY_STALE`. [relatado]
- `MWAITX` não apareceu em nenhuma linha do log. Só investigue se os dados apontarem. [relatado]

## Shaders e PSOs (R11, label `shaders`)

- O primeiro draw chama `make::ready` (`0x1FB280`), que espera até `VICTORY_PIPELINE_WAIT_MS=500` ms por tick. Num quadro que cruza dois ticks, isso chega a ~1 s. [relatado]
- Cache frio: `wait_for_pipelines` ~500 ms em todas as janelas de mundo. Com o cache quente da referência, 0 ms na mediana e 9,6 ms no p95. [relatado]
- O cache de shaders é chaveado pela impressão do tradutor (`translation_fingerprint`), não pelo hash do exe. Dá para reaproveitar o cache entre candidatas quando o tradutor for idêntico (confira por hash). [relatado]

## Present e pacing (R12, label `present`)

- O FPS da meta conta Presents DXGI (`Meter::frame`, `host.rs`), com `FLIP_DISCARD`, 2 buffers e `SyncInterval=0`. Ele mistura quadros de mundo com quadros de menu e loading. [relatado]
- Com `--console series-s`, o título apresenta dois planos. Sem o patch 03, só a cena aparece e a interface sai preta.

## Regressões de imagem (R13, label `image-regression`)

- Cutscene preta na candidata 1: o piso `orçamento/4` do PR #45 segurou as texturas do título em ~849 MB (mediana), contra 1.921 MB na referência. As superfícies ficaram sem cor base. O patch 02 torna o PR #45 opt-in. [relatado]
- O log da build `diagnostics` marca `a black frame after a frame that was not`, um bom gatilho automático.
