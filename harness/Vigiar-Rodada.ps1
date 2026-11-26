[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Stderr,          # log do victory.exe desta rodada
    [Parameter(Mandatory)][int]$ProcessId,          # PID do victory.exe
    [Parameter(Mandatory)][string]$OutBase,         # prefixo dos arquivos de saida (.marcos.log, .score.json, .score.md)
    [string]$KeysFile = '',                         # VICTORY_KEYS_FILE da rodada ('' = sem Enter automatico)
    [string]$SavesDir = '',                         # pasta dos saves (detecta o primeiro autosave depois da cutscene)
    [int]$EnterApos = 20,                           # segundos antes do primeiro Enter
    [int]$EnterIntervalo = 6,                       # segundos entre Enters enquanto o jogo esta em menu/loading
    [int]$MundoDraws = 1000,                        # draws por quadro a partir dos quais e cena 3D (cutscene/mundo)
    [int]$FecharAposJogavelS = 0,                   # >0: fecha o jogo N s depois do F9 (jogavel), para medir e encerrar sozinho
    [int]$MaxMinutos = 0,                           # >0: fecha o jogo depois desse tempo total
    [double]$ImagemScore = -1                       # nota 0-100 do cutscene-lab (opcional, pode ser dada depois)
)

# So le o log e o relogio; a unica acao sobre o jogo e escrever o arquivo de teclas
# (o runtime segura a tecla 0,2 s) e, se pedido, fechar o processo no fim.

Add-Type -Namespace Vigia -Name Teclas -MemberDefinition '[DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);'
$esc = [char]27
$inicio = Get-Date
$marcos = "$OutBase.marcos.log"
function Get-Agora { [math]::Round(((Get-Date) - $inicio).TotalSeconds, 1) }
function Write-Marco([string]$texto) {
    $linha = '{0,7:N1} s  {1}' -f (Get-Agora), $texto
    Add-Content -LiteralPath $marcos -Value $linha -Encoding utf8
    Write-Host $linha
}
if ($KeysFile) { Set-Content -LiteralPath $KeysFile -Value '' -Encoding ascii -NoNewline }

Write-Host '=== Vigia da rodada ==='
Write-Host 'Aperte F9 quando o jogo ficar JOGAVEL (fim da cutscene, controle do personagem).'
Write-Host 'Aperte F10 para marcar qualquer outro momento (anotado no log de marcos).'
Write-Marco "inicio; log $Stderr"

$amostras = New-Object System.Collections.Generic.List[object]
$stream = $null; $reader = $null; $parcial = ''
$t = @{ primeiroQuadro = $null; primeiroEnter = $null; ultimoEnter = $null; cutscene = $null; jogavel = $null; autosave = $null }
$enters = 0; $ultimoEnterEm = -999; $ultimoDraws = 0; $f9 = $false; $f10 = $false
$shaders = 0; $recusados = @{}; $removido = 0
$saveBase = $null
if ($SavesDir -and (Test-Path -LiteralPath $SavesDir)) {
    $saveBase = (Get-ChildItem -LiteralPath $SavesDir -Recurse -File | Measure-Object LastWriteTime -Maximum).Maximum
}
$proximaChecagemSave = 0

while ($true) {
    $vivo = [bool](Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
    # Le as linhas novas do log (o runtime segue escrevendo).
    if (-not $reader -and (Test-Path -LiteralPath $Stderr)) {
        $stream = [IO.File]::Open($Stderr, 'Open', 'Read', 'ReadWrite')
        $reader = New-Object IO.StreamReader($stream)
    }
    if ($reader) {
        $novo = $reader.ReadToEnd()
        if ($novo) {
            $texto = $parcial + $novo
            $linhas = $texto -split "`n"
            $parcial = $linhas[-1]
            foreach ($l in $linhas[0..($linhas.Count - 2)]) {
                $s = $l -replace "$esc\[[0-9;]*m", ''
                if ($s -match '([\d.]+) fps, ([\d.]+) ms/frame .*?, (\d+) draws/frame(, dropped (\d+) without a host pipeline)?') {
                    $agora = Get-Agora
                    $draws = [int]$matches[3]
                    $amostra = [pscustomobject]@{ t = $agora; fps = [double]$matches[1]; ms = [double]$matches[2]; draws = $draws; dropped = $(if ($matches[5]) { [int]$matches[5] } else { 0 }) }
                    $amostras.Add($amostra)
                    $ultimoDraws = $draws
                    if (-not $t.primeiroQuadro) { $t.primeiroQuadro = $agora; Write-Marco 'primeiro quadro apresentado' }
                    if (-not $t.cutscene -and $draws -gt $MundoDraws) {
                        $t.cutscene = $agora
                        Write-Marco "PRIMEIRA CENA 3D (cutscene): $draws draws/quadro, $($amostra.fps) fps; Enter automatico desligado"
                    }
                }
                elseif ($s -match 'shader translated') { $shaders++ }
                elseif ($s -match 'without a host pipeline: refused \[(\w+) ([0-9a-f]+)\]') { $recusados[$matches[2]] = $matches[1] }
                elseif ($s -match 'device (removed|lost|hung)|DEVICE_REMOVED') { $removido++; Write-Marco "GPU PERDIDA: $($s.Trim())" }
                elseif ($s -match 'a scripted key from VICTORY_KEYS_FILE') { }
            }
        }
    }
    $agora = Get-Agora
    # Enter automatico: so antes da primeira cena 3D e com o jogo em tela leve (menu/loading).
    if ($KeysFile -and -not $t.cutscene -and $agora -ge $EnterApos -and ($agora - $ultimoEnterEm) -ge $EnterIntervalo -and $ultimoDraws -le 50 -and $t.primeiroQuadro) {
        $enters++
        $ultimoEnterEm = $agora
        Add-Content -LiteralPath $KeysFile -Value "$enters Enter" -Encoding ascii
        if (-not $t.primeiroEnter) { $t.primeiroEnter = $agora; Write-Marco 'primeiro Enter automatico' }
        $t.ultimoEnter = $agora
    }
    # Marcas manuais.
    $f9agora = ([Vigia.Teclas]::GetAsyncKeyState(0x78) -band 0x8000) -ne 0
    if ($f9agora -and -not $f9 -and -not $t.jogavel) { $t.jogavel = $agora; Write-Marco 'JOGAVEL (F9)' }
    $f9 = $f9agora
    $f10agora = ([Vigia.Teclas]::GetAsyncKeyState(0x79) -band 0x8000) -ne 0
    if ($f10agora -and -not $f10) { Write-Marco 'marca manual (F10)' }
    $f10 = $f10agora
    # Primeiro autosave depois da primeira cena 3D (indicio de jogo jogavel).
    if ($saveBase -and $t.cutscene -and -not $t.autosave -and $agora -ge $proximaChecagemSave) {
        $proximaChecagemSave = $agora + 5
        $ult = (Get-ChildItem -LiteralPath $SavesDir -Recurse -File | Measure-Object LastWriteTime -Maximum).Maximum
        if ($ult -gt $saveBase) { $t.autosave = $agora; Write-Marco 'primeiro save gravado depois da cena 3D' }
    }
    # Encerramentos opcionais.
    if ($vivo -and $FecharAposJogavelS -gt 0 -and $t.jogavel -and $agora -ge $t.jogavel + $FecharAposJogavelS) {
        Write-Marco "fechando o jogo: $FecharAposJogavelS s medidos depois do F9"; Stop-Process -Id $ProcessId -ErrorAction SilentlyContinue
    }
    if ($vivo -and $MaxMinutos -gt 0 -and $agora -ge $MaxMinutos * 60) {
        Write-Marco "fechando o jogo: limite de $MaxMinutos min"; Stop-Process -Id $ProcessId -ErrorAction SilentlyContinue
    }
    if (-not $vivo) { break }
    Start-Sleep -Milliseconds 200
}
if ($reader) { $reader.Dispose() }
Write-Marco 'o jogo fechou; calculando o score'

function Get-Mediana($v) { $s = @($v | Sort-Object); if (-not $s.Count) { return $null }; $s[[int][math]::Floor(($s.Count - 1) / 2)] }
function Get-P95($v) { $s = @($v | Sort-Object); if (-not $s.Count) { return $null }; $s[[math]::Min($s.Count - 1, [math]::Ceiling($s.Count * 0.95) - 1)] }

$mundo = @($amostras | Where-Object { $_.draws -gt $MundoDraws })
$fimCutscene = if ($t.jogavel) { $t.jogavel } else { [double]::MaxValue }
$naCutscene = @($mundo | Where-Object { $_.t -lt $fimCutscene })
$jogando = @($mundo | Where-Object { $_.t -ge $fimCutscene })
$antes = @($amostras | Where-Object { -not $t.cutscene -or $_.t -lt $t.cutscene })
$descartePorQuadro = Get-Mediana @($mundo | ForEach-Object { if ($_.draws) { $_.dropped / $_.draws } else { 0 } })

$fpsJogo = if ($jogando.Count) { Get-Mediana $jogando.fps } elseif ($naCutscene.Count) { Get-Mediana $naCutscene.fps } else { $null }
$comp = [ordered]@{}
# Progresso: chegou na primeira cena 3D (50) e ficou jogavel (100).
$comp.progresso = if ($t.jogavel) { 100 } elseif ($t.cutscene) { 50 } elseif ($t.primeiroQuadro) { 10 } else { 0 }
# Velocidade: FPS mediano no mundo contra a meta de 30.
$comp.velocidade = if ($null -ne $fpsJogo) { [math]::Round([math]::Min(100, $fpsJogo / 30 * 100), 1) } else { 0 }
# Carregamento: 60 s ate a primeira cena 3D = 100; 20 min = 0.
$comp.carregamento = if ($t.cutscene) { [math]::Round([math]::Max(0, [math]::Min(100, (1 - ($t.cutscene - 60) / (1200 - 60)) * 100)), 1) } else { 0 }
# Shaders: fracao de draws executados (nao descartados por falta de pipeline) no mundo.
$comp.shaders = if ($null -ne $descartePorQuadro) { [math]::Round((1 - $descartePorQuadro) * 100, 1) } else { $null }
$comp.imagem = if ($ImagemScore -ge 0) { $ImagemScore } else { $null }
$pesos = @{ progresso = 30; velocidade = 25; carregamento = 20; shaders = 15; imagem = 10 }
$soma = 0; $pesoUsado = 0
foreach ($k in $comp.Keys) { if ($null -ne $comp[$k]) { $soma += $comp[$k] * $pesos[$k]; $pesoUsado += $pesos[$k] } }
$total = if ($pesoUsado) { [math]::Round($soma / $pesoUsado, 1) } else { 0 }

$res = [ordered]@{
    score_total = $total
    pesos = $pesos
    componentes = $comp
    tempos_s = [ordered]@{
        primeiro_quadro = $t.primeiroQuadro; primeiro_enter = $t.primeiroEnter; ultimo_enter = $t.ultimoEnter; enters = $enters
        primeira_cena_3d = $t.cutscene; jogavel_f9 = $t.jogavel; primeiro_save_apos_cena = $t.autosave
        cena_ate_jogavel = $(if ($t.jogavel -and $t.cutscene) { [math]::Round($t.jogavel - $t.cutscene, 1) } else { $null })
    }
    fps = [ordered]@{
        carregamento_mediana = Get-Mediana $antes.fps
        cutscene_mediana = Get-Mediana $naCutscene.fps; cutscene_ms_p95 = Get-P95 $naCutscene.ms
        jogavel_mediana = Get-Mediana $jogando.fps; jogavel_ms_p95 = Get-P95 $jogando.ms
        amostras_mundo = $mundo.Count
    }
    shaders = [ordered]@{ traduzidos_na_rodada = $shaders; pipelines_recusados_distintos = $recusados.Count; descarte_mediano_por_quadro = $descartePorQuadro }
    gpu_perdida = $removido
    log = (Split-Path -Leaf $Stderr)   # so o nome: o caminho local nao vai para o score publicado
}
$res | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$OutBase.score.json" -Encoding utf8
@(
    "# Score da rodada: $total / 100"
    ''
    '| Componente | Nota | Peso |'
    '|---|---|---|'
    ($comp.Keys | ForEach-Object { "| $_ | $(if ($null -ne $comp[$_]) { $comp[$_] } else { 'sem dado' }) | $($pesos[$_]) |" })
    ''
    '| Marco | Tempo (s) |'
    '|---|---|'
    ($res.tempos_s.Keys | ForEach-Object { "| $_ | $($res.tempos_s[$_]) |" })
    ''
    "FPS mediano: carregamento $($res.fps.carregamento_mediana), cutscene $($res.fps.cutscene_mediana) (p95 $($res.fps.cutscene_ms_p95) ms), jogavel $($res.fps.jogavel_mediana) (p95 $($res.fps.jogavel_ms_p95) ms)."
    "Shaders traduzidos na rodada: $shaders; pipelines recusados distintos: $($recusados.Count); GPU perdida: $removido."
    ''
    'Pesos e escalas sao convencoes deste teste (ajuste em Vigiar-Rodada.ps1). A nota de imagem vem do cutscene-lab (score.py) quando informada.'
) | Set-Content -LiteralPath "$OutBase.score.md" -Encoding utf8
Write-Marco "SCORE $total (detalhes em $OutBase.score.md)"
Write-Host 'Pode fechar esta janela.'
