<#
.SYNOPSIS
  Watcher: follows a run's log, drives the menus, records milestones, closes the game and scores the run.

.DESCRIPTION
  Fully automatic: reads the log and the clock, writes the key file (the runtime holds the key
  for 0.2 s, VICTORY_KEYS_FILE) and closes the process at the end. No user key presses.
  "Playable" = the first save written after the first 3D scene.
  Outputs: <OutBase>.marcos.log (milestones), .amostras.csv (samples), .score.json, .score.md.
  Parameter names and score keys are kept in Portuguese for compatibility with earlier runs.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Stderr,          # victory.exe log for this run
    [Parameter(Mandatory)][int]$ProcessId,          # victory.exe PID
    [Parameter(Mandatory)][string]$OutBase,         # output prefix: .marcos.log .amostras.csv .score.json .score.md
    [string]$KeysFile = '',                         # VICTORY_KEYS_FILE ('' = no automatic Enter)
    [string]$SavesDir = '',                         # saves folder: the first save after the 3D scene = playable
    [int]$EnterApos = 20,                           # seconds before the first Enter
    [int]$EnterIntervalo = 6,                       # seconds between Enters, only on light screens and before the 3D scene
    [int]$MundoDraws = 1000,                        # draws/frame from which a frame counts as a 3D scene
    [int]$MedirJogavelS = 120,                      # seconds measured after playable, then close the game (0 = do not close)
    [int]$MaxMinutos = 45,                          # close the game after this (0 = no limit)
    [int]$SemProgressoMin = 12,                     # close if no new milestone for this long (0 = never)
    [double]$ImagemScore = -1                       # 0-100 score from cutscene-lab, if available
)

$esc = [char]27
$inicio = Get-Date
$marcos = "$OutBase.marcos.log"
function Get-Agora { [math]::Round(((Get-Date) - $inicio).TotalSeconds, 1) }
$script:ultimoMarco = 0
function Write-Marco([string]$texto, [switch]$Progresso) {
    $linha = '{0,7:N1} s  {1}' -f (Get-Agora), $texto
    Add-Content -LiteralPath $marcos -Value $linha -Encoding utf8
    Write-Host $linha
    if ($Progresso) { $script:ultimoMarco = Get-Agora }
}
if ($KeysFile) { Set-Content -LiteralPath $KeysFile -Value '' -Encoding ascii -NoNewline }
Write-Marco "start; log $(Split-Path -Leaf $Stderr)" -Progresso

$amostras = New-Object System.Collections.Generic.List[object]
$reader = $null; $parcial = ''
$t = [ordered]@{ primeiroQuadro = $null; primeiroEnter = $null; enterAceito = $null; cutscene = $null; jogavel = $null }
$enters = 0; $ultimoEnterEm = -999; $ultimoDraws = 0
$aceitar = $null   # Enter waiting for confirmation: (time, draws at that moment)
$shaders = 0; $recusados = @{}; $removido = 0; $motivoFim = 'the game closed'
$saveBase = $null
if ($SavesDir -and (Test-Path -LiteralPath $SavesDir)) {
    $saveBase = (Get-ChildItem -LiteralPath $SavesDir -Recurse -File | Measure-Object LastWriteTime -Maximum).Maximum
}
$proximaChecagemSave = 0

while ($true) {
    $vivo = [bool](Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
    if (-not $reader -and (Test-Path -LiteralPath $Stderr)) {
        $reader = New-Object IO.StreamReader([IO.File]::Open($Stderr, 'Open', 'Read', 'ReadWrite'))
    }
    if ($reader) {
        $novo = $reader.ReadToEnd()
        if ($novo) {
            $linhas = ($parcial + $novo) -split "`n"
            $parcial = $linhas[-1]
            foreach ($l in $linhas[0..($linhas.Count - 2)]) {
                $s = $l -replace "$esc\[[0-9;]*m", ''
                if ($s -match '([\d.]+) fps, ([\d.]+) ms/frame .*?, (\d+) draws/frame(, dropped (\d+) without a host pipeline)?') {
                    $agora = Get-Agora
                    $draws = [int]$matches[3]
                    $amostras.Add([pscustomobject]@{ t = $agora; fps = [double]$matches[1]; ms = [double]$matches[2]; draws = $draws; dropped = $(if ($matches[5]) { [int]$matches[5] } else { 0 }) })
                    if (-not $t.primeiroQuadro) { $t.primeiroQuadro = $agora; Write-Marco 'first frame presented' -Progresso }
                    # An Enter was accepted when the screen state changes (draws) within the next 3-15 s.
                    if ($aceitar -and -not $t.enterAceito -and $agora -ge $aceitar[0] + 3) {
                        if ($draws -ne $aceitar[1]) { $t.enterAceito = $aceitar[0]; Write-Marco ("Enter accepted (the screen went from {0} to {1} draws)" -f $aceitar[1], $draws) -Progresso }
                        elseif ($agora -gt $aceitar[0] + 15) { $aceitar = $null }
                    }
                    if (-not $t.cutscene -and $draws -gt $MundoDraws) {
                        $t.cutscene = $agora
                        Write-Marco "FIRST 3D SCENE: $draws draws/frame, $($matches[1]) fps; automatic Enter off" -Progresso
                    }
                    $ultimoDraws = $draws
                }
                elseif ($s -match 'shader translated') { $shaders++ }
                elseif ($s -match 'without a host pipeline: refused \[(\w+) ([0-9a-f]+)\]') { $recusados[$matches[2]] = $matches[1] }
                elseif ($s -match 'device (removed|lost|hung)|DEVICE_REMOVED') { $removido++; Write-Marco "GPU LOST: $($s.Trim())" }
            }
        }
    }
    $agora = Get-Agora
    if ($KeysFile -and -not $t.cutscene -and $agora -ge $EnterApos -and ($agora - $ultimoEnterEm) -ge $EnterIntervalo -and $ultimoDraws -le 50 -and $t.primeiroQuadro) {
        $enters++
        $ultimoEnterEm = $agora
        Add-Content -LiteralPath $KeysFile -Value "$enters Enter" -Encoding ascii
        if (-not $t.primeiroEnter) { $t.primeiroEnter = $agora; Write-Marco 'first automatic Enter' }
        if (-not $t.enterAceito -and -not $aceitar) { $aceitar = @($agora, $ultimoDraws) }
    }
    # Playable = first save written after the first 3D scene (the mission-start autosave).
    if ($saveBase -and $t.cutscene -and -not $t.jogavel -and $agora -ge $proximaChecagemSave) {
        $proximaChecagemSave = $agora + 3
        $ult = (Get-ChildItem -LiteralPath $SavesDir -Recurse -File | Measure-Object LastWriteTime -Maximum).Maximum
        if ($ult -gt $saveBase) { $t.jogavel = $agora; Write-Marco 'PLAYABLE: first save written after the 3D scene' -Progresso }
    }
    if ($vivo) {
        $fechar = $null
        if ($MedirJogavelS -gt 0 -and $t.jogavel -and $agora -ge $t.jogavel + $MedirJogavelS) { $fechar = "measured $MedirJogavelS s after playable" }
        elseif ($MaxMinutos -gt 0 -and $agora -ge $MaxMinutos * 60) { $fechar = "$MaxMinutos min limit" }
        elseif ($SemProgressoMin -gt 0 -and $agora -ge $script:ultimoMarco + $SemProgressoMin * 60) { $fechar = "no new milestone for $SemProgressoMin min" }
        if ($fechar) { $motivoFim = $fechar; Write-Marco "closing the game: $fechar"; Stop-Process -Id $ProcessId -ErrorAction SilentlyContinue }
    }
    if (-not $vivo) { break }
    Start-Sleep -Milliseconds 250
}
if ($reader) { $reader.Dispose() }
Write-Marco 'the game closed; computing the score'

$amostras | Export-Csv -LiteralPath "$OutBase.amostras.csv" -NoTypeInformation -Encoding utf8

function Get-Mediana($v) { $s = @($v | Sort-Object); if (-not $s.Count) { return $null }; $s[[int][math]::Floor(($s.Count - 1) / 2)] }
function Get-P95($v) { $s = @($v | Sort-Object); if (-not $s.Count) { return $null }; $s[[math]::Min($s.Count - 1, [math]::Ceiling($s.Count * 0.95) - 1)] }
# Drops: frame windows (~5 s each) far above the phase median, and hitches above 1 s per frame.
function Get-Quedas($lista) {
    $med = Get-Mediana $lista.ms
    if ($null -eq $med) { return [ordered]@{ janelas = 0; quedas_2x = 0; travadas_1s = 0; pct_quedas = $null; pior_ms = $null } }
    $q = @($lista | Where-Object { $_.ms -gt 2 * $med }).Count
    [ordered]@{
        janelas = $lista.Count; quedas_2x = $q; travadas_1s = @($lista | Where-Object { $_.ms -gt 1000 }).Count
        pct_quedas = [math]::Round(100 * $q / $lista.Count, 1); pior_ms = ($lista.ms | Measure-Object -Maximum).Maximum
    }
}

$mundo = @($amostras | Where-Object { $_.draws -gt $MundoDraws })
$fimCutscene = if ($t.jogavel) { $t.jogavel } else { [double]::MaxValue }
$naCutscene = @($mundo | Where-Object { $_.t -lt $fimCutscene })
$jogando = @($mundo | Where-Object { $_.t -ge $fimCutscene })
$antes = @($amostras | Where-Object { -not $t.cutscene -or $_.t -lt $t.cutscene })
$descarte = Get-Mediana @($mundo | ForEach-Object { if ($_.draws) { $_.dropped / $_.draws } else { 0 } })
$quedasMundo = Get-Quedas $mundo

$fpsJogo = if ($jogando.Count) { Get-Mediana $jogando.fps } elseif ($naCutscene.Count) { Get-Mediana $naCutscene.fps } else { $null }
$comp = [ordered]@{}
# progresso (progress): image 10, Enter accepted 30, first 3D scene 50, playable 100.
$comp.progresso = if ($t.jogavel) { 100 } elseif ($t.cutscene) { 50 } elseif ($t.enterAceito) { 30 } elseif ($t.primeiroQuadro) { 10 } else { 0 }
# velocidade (speed): median FPS in play (or in the cutscene) against the 30 FPS goal.
$comp.velocidade = if ($null -ne $fpsJogo) { [math]::Round([math]::Min(100, $fpsJogo / 30 * 100), 1) } else { 0 }
# carregamento (loading): first 3D scene at 60 s = 100; at 20 min = 0.
$comp.carregamento = if ($t.cutscene) { [math]::Round([math]::Max(0, [math]::Min(100, (1 - ($t.cutscene - 60) / (1200 - 60)) * 100)), 1) } else { 0 }
# estabilidade (stability) in the world: each 1% of drop windows costs 2 points, each hitch > 1 s costs 5, a lost GPU zeroes it.
$comp.estabilidade = if ($removido) { 0 } elseif ($quedasMundo.janelas) { [math]::Round([math]::Max(0, 100 - 2 * $quedasMundo.pct_quedas - 5 * $quedasMundo.travadas_1s), 1) } else { $null }
$comp.shaders = if ($null -ne $descarte) { [math]::Round((1 - $descarte) * 100, 1) } else { $null }
$comp.imagem = if ($ImagemScore -ge 0) { $ImagemScore } else { $null }
$pesos = [ordered]@{ progresso = 25; velocidade = 20; carregamento = 20; estabilidade = 15; shaders = 10; imagem = 10 }
$soma = 0; $pesoUsado = 0
foreach ($k in $comp.Keys) { if ($null -ne $comp[$k]) { $soma += $comp[$k] * $pesos[$k]; $pesoUsado += $pesos[$k] } }
$total = if ($pesoUsado) { [math]::Round($soma / $pesoUsado, 1) } else { 0 }

$res = [ordered]@{
    score_total = $total
    pesos = $pesos
    componentes = $comp
    tempos_s = [ordered]@{
        primeiro_quadro = $t.primeiroQuadro; primeiro_enter = $t.primeiroEnter; enter_aceito = $t.enterAceito; enters = $enters
        primeira_cena_3d = $t.cutscene; jogavel = $t.jogavel
        cena_ate_jogavel = $(if ($t.jogavel -and $t.cutscene) { [math]::Round($t.jogavel - $t.cutscene, 1) } else { $null })
        duracao_total = Get-Agora
    }
    fps = [ordered]@{
        carregamento_mediana = Get-Mediana $antes.fps
        cutscene_mediana = Get-Mediana $naCutscene.fps; cutscene_ms_p95 = Get-P95 $naCutscene.ms
        jogavel_mediana = Get-Mediana $jogando.fps; jogavel_ms_p95 = Get-P95 $jogando.ms
        mundo_mediana = Get-Mediana $mundo.fps; mundo_ms_p95 = Get-P95 $mundo.ms
        amostras_mundo = $mundo.Count
    }
    quedas_mundo = $quedasMundo
    shaders = [ordered]@{ traduzidos_na_rodada = $shaders; pipelines_recusados_distintos = $recusados.Count; descarte_mediano_por_quadro = $descarte }
    gpu_perdida = $removido
    fim = $motivoFim
    log = (Split-Path -Leaf $Stderr)   # file name only: the local path does not go into a published score
}
$res | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$OutBase.score.json" -Encoding utf8
@(
    "# Run score: $total / 100"
    ''
    '| Component | Score | Weight |'
    '|---|---|---|'
    ($comp.Keys | ForEach-Object { "| $_ | $(if ($null -ne $comp[$_]) { $comp[$_] } else { 'no data' }) | $($pesos[$_]) |" })
    ''
    '| Milestone | Time (s) |'
    '|---|---|'
    ($res.tempos_s.Keys | ForEach-Object { "| $_ | $($res.tempos_s[$_]) |" })
    ''
    "Median FPS: loading $($res.fps.carregamento_mediana), cutscene $($res.fps.cutscene_mediana) (p95 $($res.fps.cutscene_ms_p95) ms), playable $($res.fps.jogavel_mediana) (p95 $($res.fps.jogavel_ms_p95) ms)."
    "World drops: $($quedasMundo.quedas_2x) of $($quedasMundo.janelas) windows above 2x the median ($($quedasMundo.pct_quedas)%), $($quedasMundo.travadas_1s) hitches above 1 s, worst $($quedasMundo.pior_ms) ms."
    "Shaders translated: $shaders; distinct refused pipelines: $($recusados.Count); GPU lost: $removido. End: $motivoFim."
    ''
    'Playable = first save written after the first 3D scene. Enter accepted = the screen changed after the Enter. Weights and scales are conventions of this test.'
    'Keys: progresso = progress, velocidade = speed, carregamento = loading, estabilidade = stability, imagem = image.'
) | Set-Content -LiteralPath "$OutBase.score.md" -Encoding utf8
Write-Marco "SCORE $total"
