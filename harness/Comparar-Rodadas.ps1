<#
.SYNOPSIS
  FPS-drop checker between two runs (two score.json files of the same profile and console).

.DESCRIPTION
  Returns an object with the verdict (OK or REGRESSION) and the list of findings, and sets
  exit code 1 on regression. Only compares what both runs measured. A regression is:
  median world or playable FPS down more than -FpsQuedaPct; world p95 ms/frame worse than
  -P95PioraPct; drop windows (> 2x the median) up more than -QuedasPontos points; more than
  -TravadasMais extra hitches > 1 s; a lost GPU; or the run getting less far (progress).

.EXAMPLE
  .\Comparar-Rodadas.ps1 -Atual new.score.json -Anterior old.score.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Atual,       # score.json of the new version
    [Parameter(Mandatory)][string]$Anterior,    # score.json of the reference version (same profile and console)
    [double]$FpsQuedaPct = 10,                  # median world FPS may drop up to this (%)
    [double]$P95PioraPct = 15,                  # world p95 ms may get worse up to this (%)
    [double]$QuedasPontos = 5,                  # % of drop windows may rise up to this (percentage points)
    [int]$TravadasMais = 1                      # hitches > 1 s may increase up to this
)

$a = Get-Content -LiteralPath $Atual -Raw | ConvertFrom-Json
$b = Get-Content -LiteralPath $Anterior -Raw | ConvertFrom-Json
$achados = New-Object System.Collections.Generic.List[string]
$regressao = $false

function Test-Pior([string]$nome, $novo, $velho, [double]$limitePct, [switch]$MaiorMelhor) {
    if ($null -eq $novo -or $null -eq $velho -or $velho -eq 0) { return }
    $delta = 100 * ($novo - $velho) / $velho
    $piorou = if ($MaiorMelhor) { -$delta } else { $delta }
    $txt = '{0}: {1} -> {2} ({3:+0.0;-0.0}%)' -f $nome, $velho, $novo, $delta
    if ($piorou -gt $limitePct) { $script:regressao = $true; $achados.Add("REGRESSION $txt") } else { $achados.Add("ok $txt") }
}

if ($a.componentes.progresso -lt $b.componentes.progresso) {
    $regressao = $true; $achados.Add("REGRESSION progress: got less far ($($b.componentes.progresso) -> $($a.componentes.progresso))")
}
if ($a.gpu_perdida -gt $b.gpu_perdida) { $regressao = $true; $achados.Add("REGRESSION GPU lost: $($b.gpu_perdida) -> $($a.gpu_perdida)") }
Test-Pior 'median world FPS' $a.fps.mundo_mediana $b.fps.mundo_mediana $FpsQuedaPct -MaiorMelhor
Test-Pior 'world p95 ms' $a.fps.mundo_ms_p95 $b.fps.mundo_ms_p95 $P95PioraPct
Test-Pior 'median playable FPS' $a.fps.jogavel_mediana $b.fps.jogavel_mediana $FpsQuedaPct -MaiorMelhor
Test-Pior 'time to first 3D scene (s)' $a.tempos_s.primeira_cena_3d $b.tempos_s.primeira_cena_3d 15
if ($null -ne $a.quedas_mundo.pct_quedas -and $null -ne $b.quedas_mundo.pct_quedas) {
    $d = $a.quedas_mundo.pct_quedas - $b.quedas_mundo.pct_quedas
    $txt = 'drop windows (>2x median): {0}% -> {1}%' -f $b.quedas_mundo.pct_quedas, $a.quedas_mundo.pct_quedas
    if ($d -gt $QuedasPontos) { $regressao = $true; $achados.Add("REGRESSION $txt") } else { $achados.Add("ok $txt") }
}
if ($null -ne $a.quedas_mundo.travadas_1s -and $null -ne $b.quedas_mundo.travadas_1s) {
    $txt = 'hitches > 1 s: {0} -> {1}' -f $b.quedas_mundo.travadas_1s, $a.quedas_mundo.travadas_1s
    if ($a.quedas_mundo.travadas_1s - $b.quedas_mundo.travadas_1s -gt $TravadasMais) { $regressao = $true; $achados.Add("REGRESSION $txt") } else { $achados.Add("ok $txt") }
}
$achados.Add(('score: {0} -> {1}' -f $b.score_total, $a.score_total))

$veredito = if ($regressao) { 'REGRESSION' } else { 'OK' }
[pscustomobject]@{ veredito = $veredito; achados = @($achados) }
if ($regressao) { $global:LASTEXITCODE = 1 } else { $global:LASTEXITCODE = 0 }
