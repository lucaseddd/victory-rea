# 4. Medir

## A linha de quadro do log

O runtime escreve no `stderr`, a cada ~5 s, uma linha agregada no formato abaixo:

```
<fps> fps, <ms> ms/frame (<x> preparing …; <y> on the GPU; <z> copying back <n> MB), <d> draws/frame[, dropped <k> without a host pipeline]
```

- **draws/frame separa as fases.** Cerca de 10 draws é menu ou loading. Acima de 500–1.000 é cena 3D (cutscene ou mundo). O vigia usa 50 e 1.000 como limites.
- **Média de rodada inteira engana.** Na candidata 1, o total ponderado deu 26,7 fps, mas o mundo ficou em 1,15 fps [relatado, R04]. Sempre separe por fase.
- **Com `VICTORY_FRAME_LOG=1`** sai também o tempo por quadro (necessário para p95 de verdade e para atribuir picos).

## Contadores úteis

| Variável | O que acrescenta ao log |
|---|---|
| `VICTORY_FRAME_LOG=1` | tempo por quadro, `PipelineWaitUs`, submissões por quadro |
| `VICTORY_DSTORAGE_STATS=1` | pedidos por Submit, contiguidade, latência, leitura/descompressão/destino (patch 01) |
| `VICTORY_LOG=info` | VRAM própria e compartilhada, orçamento DXGI, texturas vivas, piso efetivo |
| build `diagnostics` | detecção de quadro preto (`a black frame after a frame that was not`) |

O [Medir-Rodada.ps1](../harness/Medir-Rodada.ps1) resume tudo isso por rodada.

## Protocolo comparável

Todo número informa:

- build (hash);
- cena e checkpoints;
- perfil efetivo (as `VICTORY_*` do `.settings.txt`);
- resolução e console (`series-x`/`series-s`);
- cache frio ou quente.

Ao comparar duas configurações:

- mude **uma** variável por vez;
- alterne A/B/A/B, em vez de AAA/BBB;
- use a mesma semente de save;
- informe mediana, p95, % de quadros > 33,33 ms, travamentos e VRAM típica e pico.

## GPU exclusiva

Só uma captura por vez. A reserva é o arquivo local `locks\gpu-capture.json`, criado com `[System.IO.File]::Move(temp, destino)`, que falha se o destino existir. Reserve só depois de confirmar que nenhum `victory` está rodando ou que o usuário liberou. Ao terminar, mova o lock para `locks\arquivo\`.

## Ferramentas externas

- **PresentMon** precisa de administrador ou do grupo Performance Log Users. Sem isso, dá "access denied".
- **RenderDoc/PIX**: as capturas contêm assets do título. Ficam na máquina e nunca vão para o repositório.
- **Imagem:** a comparação com a referência roda local (`cutscene-lab/score.py`). Só a nota sai.
