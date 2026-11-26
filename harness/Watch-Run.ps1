<#
.SYNOPSIS
  Watcher: follows a run's log, drives the menus, records milestones, closes the game and scores the run.

.DESCRIPTION
  Fully automatic: reads the log and the clock, writes the key file (the runtime holds the key
  for 0.2 s, VICTORY_KEYS_FILE) and closes the process at the end. No user key presses.
  "Playable" = the first save written after the first 3D scene.
  Outputs: <OutBase>.milestones.log, .samples.csv, .score.json, .score.md.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Stderr,          # victory.exe log for this run
    [Parameter(Mandatory)][int]$ProcessId,          # victory.exe PID
    [Parameter(Mandatory)][string]$OutBase,         # output prefix: .milestones.log .samples.csv .score.json .score.md
    [string]$KeysFile = '',                         # VICTORY_KEYS_FILE ('' = no automatic Enter)
    [string]$SavesDir = '',                         # saves folder: the first save after the 3D scene = playable
    [int]$EnterAfter = 20,                          # seconds before the first Enter
    [int]$EnterInterval = 6,                        # seconds between Enters, only on light screens and before the 3D scene
    [int]$WorldDraws = 1000,                        # draws/frame from which a frame counts as a 3D scene
    [int]$MeasurePlayableS = 120,                   # seconds measured after playable, then close the game (0 = do not close)
    [int]$MaxMinutes = 45,                          # close the game after this (0 = no limit)
    [int]$NoProgressMin = 12,                       # close if no new milestone for this long (0 = never)
    [double]$ImageScore = -1                        # 0-100 score from cutscene-lab, if available
)

$esc = [char]27
$startTime = Get-Date
$milestonesLog = "$OutBase.milestones.log"
function Get-Now { [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1) }
$script:lastMilestone = 0
function Write-Milestone([string]$text, [switch]$Progress) {
    $line = '{0,7:N1} s  {1}' -f (Get-Now), $text
    Add-Content -LiteralPath $milestonesLog -Value $line -Encoding utf8
    Write-Host $line
    if ($Progress) { $script:lastMilestone = Get-Now }
}
if ($KeysFile) { Set-Content -LiteralPath $KeysFile -Value '' -Encoding ascii -NoNewline }
Write-Milestone "start; log $(Split-Path -Leaf $Stderr)" -Progress

$samples = New-Object System.Collections.Generic.List[object]
$reader = $null; $partial = ''
$t = [ordered]@{ firstFrame = $null; firstEnter = $null; enterAccepted = $null; scene3d = $null; playable = $null }
$enters = 0; $lastEnterAt = -999; $lastDraws = 0
$pendingEnter = $null   # Enter waiting for confirmation: (time, draws at that moment)
$shaders = 0; $refused = @{}; $gpuLost = 0; $endReason = 'the game closed'
$saveBaseline = $null
if ($SavesDir -and (Test-Path -LiteralPath $SavesDir)) {
    $saveBaseline = (Get-ChildItem -LiteralPath $SavesDir -Recurse -File | Measure-Object LastWriteTime -Maximum).Maximum
}
$nextSaveCheck = 0

while ($true) {
    $alive = [bool](Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
    if (-not $reader -and (Test-Path -LiteralPath $Stderr)) {
        $reader = New-Object IO.StreamReader([IO.File]::Open($Stderr, 'Open', 'Read', 'ReadWrite'))
    }
    if ($reader) {
        $new = $reader.ReadToEnd()
        if ($new) {
            $lines = ($partial + $new) -split "`n"
            $partial = $lines[-1]
            foreach ($l in $lines[0..($lines.Count - 2)]) {
                $s = $l -replace "$esc\[[0-9;]*m", ''
                if ($s -match '([\d.]+) fps, ([\d.]+) ms/frame .*?, (\d+) draws/frame(, dropped (\d+) without a host pipeline)?') {
                    $now = Get-Now
                    $draws = [int]$matches[3]
                    $samples.Add([pscustomobject]@{ t = $now; fps = [double]$matches[1]; ms = [double]$matches[2]; draws = $draws; dropped = $(if ($matches[5]) { [int]$matches[5] } else { 0 }) })
                    if (-not $t.firstFrame) { $t.firstFrame = $now; Write-Milestone 'first frame presented' -Progress }
                    # An Enter was accepted when the screen state changes (draws) within the next 3-15 s.
                    if ($pendingEnter -and -not $t.enterAccepted -and $now -ge $pendingEnter[0] + 3) {
                        if ($draws -ne $pendingEnter[1]) { $t.enterAccepted = $pendingEnter[0]; Write-Milestone ("Enter accepted (the screen went from {0} to {1} draws)" -f $pendingEnter[1], $draws) -Progress }
                        elseif ($now -gt $pendingEnter[0] + 15) { $pendingEnter = $null }
                    }
                    if (-not $t.scene3d -and $draws -gt $WorldDraws) {
                        $t.scene3d = $now
                        Write-Milestone "FIRST 3D SCENE: $draws draws/frame, $($matches[1]) fps; automatic Enter off" -Progress
                    }
                    $lastDraws = $draws
                }
                elseif ($s -match 'shader translated') { $shaders++ }
                elseif ($s -match 'without a host pipeline: refused \[(\w+) ([0-9a-f]+)\]') { $refused[$matches[2]] = $matches[1] }
                elseif ($s -match 'device (removed|lost|hung)|DEVICE_REMOVED') { $gpuLost++; Write-Milestone "GPU LOST: $($s.Trim())" }
            }
        }
    }
    $now = Get-Now
    if ($KeysFile -and -not $t.scene3d -and $now -ge $EnterAfter -and ($now - $lastEnterAt) -ge $EnterInterval -and $lastDraws -le 50 -and $t.firstFrame) {
        $enters++
        $lastEnterAt = $now
        Add-Content -LiteralPath $KeysFile -Value "$enters Enter" -Encoding ascii
        if (-not $t.firstEnter) { $t.firstEnter = $now; Write-Milestone 'first automatic Enter' }
        if (-not $t.enterAccepted -and -not $pendingEnter) { $pendingEnter = @($now, $lastDraws) }
    }
    # Playable = first save written after the first 3D scene (the mission-start autosave).
    if ($saveBaseline -and $t.scene3d -and -not $t.playable -and $now -ge $nextSaveCheck) {
        $nextSaveCheck = $now + 3
        $latest = (Get-ChildItem -LiteralPath $SavesDir -Recurse -File | Measure-Object LastWriteTime -Maximum).Maximum
        if ($latest -gt $saveBaseline) { $t.playable = $now; Write-Milestone 'PLAYABLE: first save written after the 3D scene' -Progress }
    }
    if ($alive) {
        $close = $null
        if ($MeasurePlayableS -gt 0 -and $t.playable -and $now -ge $t.playable + $MeasurePlayableS) { $close = "measured $MeasurePlayableS s after playable" }
        elseif ($MaxMinutes -gt 0 -and $now -ge $MaxMinutes * 60) { $close = "$MaxMinutes min limit" }
        elseif ($NoProgressMin -gt 0 -and $now -ge $script:lastMilestone + $NoProgressMin * 60) { $close = "no new milestone for $NoProgressMin min" }
        if ($close) { $endReason = $close; Write-Milestone "closing the game: $close"; Stop-Process -Id $ProcessId -ErrorAction SilentlyContinue }
    }
    if (-not $alive) { break }
    Start-Sleep -Milliseconds 250
}
if ($reader) { $reader.Dispose() }
Write-Milestone 'the game closed; computing the score'

$samples | Export-Csv -LiteralPath "$OutBase.samples.csv" -NoTypeInformation -Encoding utf8

function Get-Median($v) { $s = @($v | Sort-Object); if (-not $s.Count) { return $null }; $s[[int][math]::Floor(($s.Count - 1) / 2)] }
function Get-P95($v) { $s = @($v | Sort-Object); if (-not $s.Count) { return $null }; $s[[math]::Min($s.Count - 1, [math]::Ceiling($s.Count * 0.95) - 1)] }
# Drops: frame windows (~5 s each) far above the phase median, and hitches above 1 s per frame.
function Get-Drops($list) {
    $med = Get-Median $list.ms
    if ($null -eq $med) { return [ordered]@{ windows = 0; drops_2x = 0; hitches_1s = 0; drop_pct = $null; worst_ms = $null } }
    $d = @($list | Where-Object { $_.ms -gt 2 * $med }).Count
    [ordered]@{
        windows = $list.Count; drops_2x = $d; hitches_1s = @($list | Where-Object { $_.ms -gt 1000 }).Count
        drop_pct = [math]::Round(100 * $d / $list.Count, 1); worst_ms = ($list.ms | Measure-Object -Maximum).Maximum
    }
}

$world = @($samples | Where-Object { $_.draws -gt $WorldDraws })
$cutsceneEnd = if ($t.playable) { $t.playable } else { [double]::MaxValue }
$inCutscene = @($world | Where-Object { $_.t -lt $cutsceneEnd })
$playing = @($world | Where-Object { $_.t -ge $cutsceneEnd })
$beforeScene = @($samples | Where-Object { -not $t.scene3d -or $_.t -lt $t.scene3d })
$droppedShare = Get-Median @($world | ForEach-Object { if ($_.draws) { $_.dropped / $_.draws } else { 0 } })
$worldDrops = Get-Drops $world

$playFps = if ($playing.Count) { Get-Median $playing.fps } elseif ($inCutscene.Count) { Get-Median $inCutscene.fps } else { $null }
$comp = [ordered]@{}
# progress: image 10, Enter accepted 30, first 3D scene 50, playable 100.
$comp.progress = if ($t.playable) { 100 } elseif ($t.scene3d) { 50 } elseif ($t.enterAccepted) { 30 } elseif ($t.firstFrame) { 10 } else { 0 }
# speed: median FPS in play (or in the cutscene) against the 30 FPS goal.
$comp.speed = if ($null -ne $playFps) { [math]::Round([math]::Min(100, $playFps / 30 * 100), 1) } else { 0 }
# loading: first 3D scene at 60 s = 100; at 20 min = 0.
$comp.loading = if ($t.scene3d) { [math]::Round([math]::Max(0, [math]::Min(100, (1 - ($t.scene3d - 60) / (1200 - 60)) * 100)), 1) } else { 0 }
# stability in the world: each 1% of drop windows costs 2 points, each hitch > 1 s costs 5, a lost GPU zeroes it.
$comp.stability = if ($gpuLost) { 0 } elseif ($worldDrops.windows) { [math]::Round([math]::Max(0, 100 - 2 * $worldDrops.drop_pct - 5 * $worldDrops.hitches_1s), 1) } else { $null }
$comp.shaders = if ($null -ne $droppedShare) { [math]::Round((1 - $droppedShare) * 100, 1) } else { $null }
$comp.image = if ($ImageScore -ge 0) { $ImageScore } else { $null }
$weights = [ordered]@{ progress = 25; speed = 20; loading = 20; stability = 15; shaders = 10; image = 10 }
$sum = 0; $weightUsed = 0
foreach ($k in $comp.Keys) { if ($null -ne $comp[$k]) { $sum += $comp[$k] * $weights[$k]; $weightUsed += $weights[$k] } }
$total = if ($weightUsed) { [math]::Round($sum / $weightUsed, 1) } else { 0 }

$res = [ordered]@{
    score_total = $total
    weights = $weights
    components = $comp
    times_s = [ordered]@{
        first_frame = $t.firstFrame; first_enter = $t.firstEnter; enter_accepted = $t.enterAccepted; enters = $enters
        first_3d_scene = $t.scene3d; playable = $t.playable
        scene_to_playable = $(if ($t.playable -and $t.scene3d) { [math]::Round($t.playable - $t.scene3d, 1) } else { $null })
        total_duration = Get-Now
    }
    fps = [ordered]@{
        loading_median = Get-Median $beforeScene.fps
        cutscene_median = Get-Median $inCutscene.fps; cutscene_ms_p95 = Get-P95 $inCutscene.ms
        playable_median = Get-Median $playing.fps; playable_ms_p95 = Get-P95 $playing.ms
        world_median = Get-Median $world.fps; world_ms_p95 = Get-P95 $world.ms
        world_samples = $world.Count
    }
    world_drops = $worldDrops
    shaders = [ordered]@{ translated_in_run = $shaders; distinct_refused_pipelines = $refused.Count; median_dropped_share = $droppedShare }
    gpu_lost = $gpuLost
    end = $endReason
    log = (Split-Path -Leaf $Stderr)   # file name only: the local path does not go into a published score
}
$res | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$OutBase.score.json" -Encoding utf8
@(
    "# Run score: $total / 100"
    ''
    '| Component | Score | Weight |'
    '|---|---|---|'
    ($comp.Keys | ForEach-Object { "| $_ | $(if ($null -ne $comp[$_]) { $comp[$_] } else { 'no data' }) | $($weights[$_]) |" })
    ''
    '| Milestone | Time (s) |'
    '|---|---|'
    ($res.times_s.Keys | ForEach-Object { "| $_ | $($res.times_s[$_]) |" })
    ''
    "Median FPS: loading $($res.fps.loading_median), cutscene $($res.fps.cutscene_median) (p95 $($res.fps.cutscene_ms_p95) ms), playable $($res.fps.playable_median) (p95 $($res.fps.playable_ms_p95) ms)."
    "World drops: $($worldDrops.drops_2x) of $($worldDrops.windows) windows above 2x the median ($($worldDrops.drop_pct)%), $($worldDrops.hitches_1s) hitches above 1 s, worst $($worldDrops.worst_ms) ms."
    "Shaders translated: $shaders; distinct refused pipelines: $($refused.Count); GPU lost: $gpuLost. End: $endReason."
    ''
    'Playable = first save written after the first 3D scene. Enter accepted = the screen changed after the Enter. Weights and scales are conventions of this test.'
) | Set-Content -LiteralPath "$OutBase.score.md" -Encoding utf8
Write-Milestone "SCORE $total"
