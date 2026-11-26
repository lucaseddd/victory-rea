<#
.SYNOPSIS
  FPS-drop checker between two runs (two score.json files of the same mode and console).

.DESCRIPTION
  Returns an object with the verdict (OK or REGRESSION) and the list of findings, and sets
  exit code 1 on regression. Only compares what both runs measured. A regression is:
  median world or playable FPS down more than -FpsDropPct; world p95 ms/frame worse than
  -P95WorsePct; drop windows (> 2x the median) up more than -DropPoints points; more than
  -ExtraHitches additional hitches > 1 s; a lost GPU; or the run getting less far (progress).

.EXAMPLE
  .\Compare-Runs.ps1 -Current new.score.json -Previous old.score.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Current,     # score.json of the new version
    [Parameter(Mandatory)][string]$Previous,    # score.json of the reference version (same mode and console)
    [double]$FpsDropPct = 10,                   # median world FPS may drop up to this (%)
    [double]$P95WorsePct = 15,                  # world p95 ms may get worse up to this (%)
    [double]$DropPoints = 5,                    # % of drop windows may rise up to this (percentage points)
    [int]$ExtraHitches = 1                      # hitches > 1 s may increase up to this
)

$a = Get-Content -LiteralPath $Current -Raw | ConvertFrom-Json
$b = Get-Content -LiteralPath $Previous -Raw | ConvertFrom-Json
$findings = New-Object System.Collections.Generic.List[string]
$regression = $false

function Test-Worse([string]$label, $new, $old, [double]$limitPct, [switch]$HigherIsBetter) {
    if ($null -eq $new -or $null -eq $old -or $old -eq 0) { return }
    $delta = 100 * ($new - $old) / $old
    $worse = if ($HigherIsBetter) { -$delta } else { $delta }
    $txt = '{0}: {1} -> {2} ({3:+0.0;-0.0}%)' -f $label, $old, $new, $delta
    if ($worse -gt $limitPct) { $script:regression = $true; $findings.Add("REGRESSION $txt") } else { $findings.Add("ok $txt") }
}

if ($a.components.progress -lt $b.components.progress) {
    $regression = $true; $findings.Add("REGRESSION progress: got less far ($($b.components.progress) -> $($a.components.progress))")
}
if ($a.gpu_lost -gt $b.gpu_lost) { $regression = $true; $findings.Add("REGRESSION GPU lost: $($b.gpu_lost) -> $($a.gpu_lost)") }
Test-Worse 'median world FPS' $a.fps.world_median $b.fps.world_median $FpsDropPct -HigherIsBetter
Test-Worse 'world p95 ms' $a.fps.world_ms_p95 $b.fps.world_ms_p95 $P95WorsePct
Test-Worse 'median playable FPS' $a.fps.playable_median $b.fps.playable_median $FpsDropPct -HigherIsBetter
Test-Worse 'time to first 3D scene (s)' $a.times_s.first_3d_scene $b.times_s.first_3d_scene 15
if ($null -ne $a.world_drops.drop_pct -and $null -ne $b.world_drops.drop_pct) {
    $d = $a.world_drops.drop_pct - $b.world_drops.drop_pct
    $txt = 'drop windows (>2x median): {0}% -> {1}%' -f $b.world_drops.drop_pct, $a.world_drops.drop_pct
    if ($d -gt $DropPoints) { $regression = $true; $findings.Add("REGRESSION $txt") } else { $findings.Add("ok $txt") }
}
if ($null -ne $a.world_drops.hitches_1s -and $null -ne $b.world_drops.hitches_1s) {
    $txt = 'hitches > 1 s: {0} -> {1}' -f $b.world_drops.hitches_1s, $a.world_drops.hitches_1s
    if ($a.world_drops.hitches_1s - $b.world_drops.hitches_1s -gt $ExtraHitches) { $regression = $true; $findings.Add("REGRESSION $txt") } else { $findings.Add("ok $txt") }
}
$findings.Add(('score: {0} -> {1}' -f $b.score_total, $a.score_total))

$verdict = if ($regression) { 'REGRESSION' } else { 'OK' }
[pscustomobject]@{ verdict = $verdict; findings = @($findings) }
if ($regression) { $global:LASTEXITCODE = 1 } else { $global:LASTEXITCODE = 0 }
