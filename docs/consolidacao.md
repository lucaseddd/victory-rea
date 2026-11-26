# Consolidação e score

De tempos em tempos, uma IA mais forte (R00 ou a designada pelo usuário) fecha um ciclo.

## Ciclo

1. **Ler.** Revisar os PRs abertos e os aceitos desde o último ciclo. Conferir hashes, marcação `[obs-local]`/`[relatado]`/`[estimado]` e se o número segue o protocolo comparável.
2. **Decidir.** Escolher as mudanças para a próxima candidata. Uma mudança isolada por candidata quando o objetivo é atribuir ganho (R14).
3. **Montar localmente.** Compilar a candidata em pasta própria, fora do repositório. Registrar só exe e hash, PDB GUID/age e a lista de variáveis `VICTORY_*` que mudaram.
4. **Medir.** Reservar a GPU (lock local) e rodar `harness/Iniciar-Rodada.ps1 -Rapido` (e a referência Series X), com cache frio e quente. O vigia calcula o score quando o jogo fecha.
5. **Publicar.** Abrir um PR com `consolidacao/<AAAA-MM-DD>-cand<N>.md` e atualizar `docs/indice.md`. Abrir Issues para regressões novas (label `image-regression`).

## Score

O score vem do teste automatizado ([harness/](../harness/README.md#score)): progresso 30, velocidade 25, carregamento 20, shaders 15, imagem 10. O cálculo roda na máquina local; entram no repositório só os componentes, os marcos e o total.

O relatório de consolidação cita o SHA-256 do `Vigiar-Rodada.ps1`, para que scores de ciclos diferentes sejam comparáveis. Junto do score, publique também o progresso das Issues R00–R15 e a VRAM típica e de pico. Esses números não entram na nota, mas explicam o resultado.

## Modelo do relatório

```markdown
# Consolidação <data> · candidata <N>

- Build: <exe> sha256 <hash> · PDB GUID <guid> age <n>
- Base: candidata <N-1> + PRs #<a>, #<b>
- Vigia (score): Vigiar-Rodada.ps1 sha256 <hash do script>
- Cenas: C1 (cutscene), M1 (primeira missão) · cache frio e quente

| Cena | Cache | FPS | Mediana ms | p95 ms | % > 33,33 ms | PSO wait p95 ms | Imagem | VRAM pico MB |
|---|---|---|---|---|---|---|---|---|

Score: <total> (progresso <a> · velocidade <b> · carregamento <c> · shaders <d> · imagem <e>) [obs-local]
```
