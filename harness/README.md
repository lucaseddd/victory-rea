# Teste automatizado com score

Roda o título no VIctory, aperta Enter sozinho nos menus até a primeira cena 3D, marca os tempos e calcula um score de 0 a 100. Tudo roda na sua máquina. Para o repositório volta só o `*.score.md`/`*.score.json`, que contém só números.

| Arquivo | Função |
|---|---|
| [Iniciar-Rodada.ps1](Iniciar-Rodada.ps1) | Launcher: confere hash e firewall, restaura o save da semente, define as `VICTORY_*`, inicia o runtime e abre o vigia |
| [Vigiar-Rodada.ps1](Vigiar-Rodada.ps1) | Vigia: segue o log, escreve o arquivo de teclas, registra os marcos e calcula o score quando o jogo fecha |
| [Medir-Rodada.ps1](Medir-Rodada.ps1) | Extrator: resume um ou mais `.stderr` (mundo, VRAM, mipmaps, fila COPY, worker, DirectStorage, quadros pretos) |
| [harness.example.toml](harness.example.toml) | Modelo de configuração. Copie para `harness.toml`, que o Git ignora |
| [patches/](patches/README.md) | Diffs de runtime de que o teste depende |

Origem: launcher, vigia e extrator da candidata 4 (2026-11-26). O launcher foi generalizado: caminhos vêm do `harness.toml` ou de parâmetros, a regra de firewall é localizada pelo programa e não pelo nome, e a pasta da rodada não pode ficar dentro do repositório. No vigia, a única mudança é que o `score.json` grava só o nome do log. O extrator é idêntico.

## Pré-requisitos

1. Um `victory.exe` compilado com os [patches](patches/README.md) e `--features diagnostics`.
2. O executável do título, do dump do seu próprio console.
3. Uma pasta de rodada fora do repositório, com:
   - `data-semente\`: o save de partida, copiado para `data\` a cada rodada (`-SemSemente` desliga);
   - `cache\`: opcional, um cache de shaders aquecido.
4. Firewall do Windows ligado e uma regra de saída bloqueada para cada executável. Num PowerShell **como administrador**:

   ```powershell
   New-NetFirewallRule -DisplayName 'VIctory runtime offline' -Direction Outbound -Action Block -Profile Any -Program '<caminho do victory.exe>'
   ```

   ```powershell
   New-NetFirewallRule -DisplayName 'VIctory titulo offline' -Direction Outbound -Action Block -Profile Any -Program '<caminho do executavel do titulo>'
   ```

## Rodar

Tudo num PowerShell **como administrador**, porque o launcher lê as regras do firewall.

Conferir hash, firewall e mapeamento, sem executar o título:

```powershell
.\harness\Iniciar-Rodada.ps1 -Config .\harness\harness.toml -Rapido -MapOnly
```

Teste rápido completo. Aperte **F9** quando ficar jogável; o jogo fecha 2 minutos depois:

```powershell
.\harness\Iniciar-Rodada.ps1 -Config .\harness\harness.toml -Rapido -FecharAposJogavelS 120
```

Referência em Series X, com o mesmo vigia e o mesmo score:

```powershell
.\harness\Iniciar-Rodada.ps1 -Config .\harness\harness.toml -Console series-x -AutoEnter -FecharAposJogavelS 120
```

Resumo do log de uma ou mais rodadas:

```powershell
.\harness\Medir-Rodada.ps1 -Log 'D:\victory\rodadas\rapido-*.stderr'
```

### O que o `-Rapido` liga

- `--console series-s`: o jogo renderiza menor por dentro e escala sozinho (o fork mediu 1280×720 dentro de 1920×1080). Precisa do patch 03; sem ele, a interface sai preta.
- `VICTORY_DISPLAY_MODE=1280x720`. É barato, mas o fork mediu que o jogo ignora o modo informado.
- Enter automático, save da semente, contadores (`VICTORY_FRAME_LOG=1`, `VICTORY_DSTORAGE_STATS=1`) e o vigia.

Cada item pode ser sobrescrito pelo parâmetro correspondente. Os eixos das candidatas anteriores também estão disponíveis: `-Fila`, `-Worker`, `-Mips`, `-PequenosMB`, `-ReservaAlvosMB`, `-PisoTexturasMB`, `-TexturaAuto`, `-DiscoWorkers`.

## O que o vigia faz

Ele só lê o log e o relógio. As únicas ações sobre o jogo são escrever o arquivo de teclas e, se você pedir, fechar o processo no fim.

- **Enter automático:** começa aos 20 s (`-EnterApos`) e repete a cada 6 s (`-EnterIntervalo`), só enquanto o jogo está numa tela leve (até 50 draws por quadro: menu, loading, escolha de personagem). Para de vez no primeiro quadro com mais de 1.000 draws, para não apertar nada na cutscene.
- **Marcos:** primeiro quadro, primeiro e último Enter, primeira cena 3D, jogável (F9), primeiro save gravado depois da cena 3D e marcas livres (F10). Tudo vai para `<log>.marcos.log`.
- **Encerramento:** `-FecharAposJogavelS N` fecha N segundos depois do F9; `-MaxMinutos N` fecha por tempo.
- **Saída:** `<log>.score.json` e `<log>.score.md`.

## Score

| Componente | Peso | Cálculo |
|---|---|---|
| progresso | 30 | 10 = mostrou imagem; 50 = chegou à primeira cena 3D; 100 = jogável (F9) |
| velocidade | 25 | FPS mediano no mundo ÷ 30 × 100, limitado a 100. Usa o trecho jogável se houver F9; senão, a cutscene |
| carregamento | 20 | 100 se a primeira cena 3D aparece em até 60 s; 0 em 20 min; linear entre os dois |
| shaders | 15 | % de draws do mundo que não foram descartados por falta de pipeline (mediana por quadro) |
| imagem | 10 | Nota 0–100 da comparação com a sua gravação de referência (`cutscene-lab/score.py`), passada com `-ImagemScore` |

- **Total:** média ponderada dos componentes que têm dado. Um componente sem dado sai da média e não conta como zero.
- **Mundo:** amostras com mais de 1.000 draws por quadro (`-MundoDraws`).
- **Pesos e escalas:** são convenções deste teste. Se mudar algum, registre a mudança no PR, porque scores de versões diferentes do vigia não são comparáveis. Cite o SHA-256 do `Vigiar-Rodada.ps1` no relatório.

### O que publicar

Do `.score.md` entram no PR: o total, os componentes, os marcos em segundos, as medianas e p95 de FPS e as contagens de shaders. Ficam na máquina: o `.stderr`, o `.stdout`, o `.marcos.log`, o arquivo de teclas, o `.settings.txt` e a pasta da rodada. Nesta cópia do vigia, o campo `log` do `score.json` guarda só o nome do arquivo, não o caminho local.

## Limitações conhecidas

- O F9 é manual. O primeiro save depois da cena 3D serve de indício automático, mas não substitui o F9 no score.
- A leitura de teclas usa `GetAsyncKeyState`, então o F9 funciona com qualquer janela em foco.
- A nota de imagem depende de uma gravação de referência local. Sem ela, o componente fica fora da média.
- Com a candidata 4, ainda não foram verificados: a imagem do Series S com os dois planos, a reação do jogo ao `VICTORY_KEYS_FILE` e o ganho do `-DiscoWorkers` [relatado].
