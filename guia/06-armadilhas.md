# 6. Armadilhas

Erros que já aconteceram ou quase aconteceram neste projeto.

| Armadilha | Como evitar |
|---|---|
| Endereço de uma build aplicado a outra | Hash e GUID/age em toda afirmação; refaça a busca do símbolo |
| FPS médio da rodada inteira | Separe por draws/quadro: menu ~10, cena 3D > 1.000 |
| Log histórico tratado como baseline | Rodada sem cena identificada nem GPU exclusiva só orienta. Marque `[relatado]` e diga "fora de protocolo" |
| A/B que muda mais de uma coisa | Leia o que a variável liga no fonte. `QUEUE2=1` liga três mecanismos |
| Cutscene preta tomada como "referência" | Compare com uma gravação de referência; use a detecção de quadro preto |
| Loading lento atribuído à GPU | Ligue `VICTORY_DSTORAGE_STATS`. Num HD, o gargalo foi o disco |
| Janela menor para "acelerar" | Não muda a leitura do disco. A redução real vem do perfil Series S |
| `VICTORY_DISPLAY_MODE` para baixar a resolução | O jogo ignora o modo informado (medido no fork) |
| Series S com imagem preta | Falta o patch 03 (composição dos dois planos) |
| Launcher falha com "Acesso negado" | Ler regras de firewall exige administrador. Rode elevado; não desligue a checagem |
| PresentMon "access denied" | Administrador ou grupo Performance Log Users |
| Dois chats na mesma GPU | Lock local atômico; confira que nenhum `victory` está rodando |
| Claim antigo "abandonado" | Só repasse explícito do titular ou arquivamento confirmado pelo usuário |
| Disco externo que anuncia mais do que tem | Não grave dados de teste nele; gravar além da capacidade real corrompe sem aviso |
| Cache de shaders frio contaminando o FPS | Informe frio/quente; reaproveite o cache só com tradutor idêntico (hash) |
| Material do jogo num commit | `Test-RepoContent.ps1` antes de cada PR. Se escapar, reescreva o histórico |
