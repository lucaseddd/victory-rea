param(
    [Parameter(Mandatory)][int]$GamePid,
    [Parameter(Mandatory)][long]$StartTicks,
    [Parameter(Mandatory)][string]$Log,
    [Parameter(Mandatory)][string]$Settings,
    [Parameter(Mandatory)][string]$Exe,
    # Where the history goes; set it to a folder of your own.
    [string]$History = (Join-Path $PSScriptRoot 'history'),
    # The game's data folder (where crash logs go); default: data\ beside the log.
    [string]$DataDir = ''
)
# Waits for the game to close, then records the session's score (0-100) and archives the build that ran.
# Score: performance 60 (median fps 40 + worst-10% fps 20, against 30 fps), stability 25 (no drops under
# 3 fps 15 + no error/crash 10), loading 15 (300 s or less to the world = full).
$ErrorActionPreference = 'Continue'
# Always a decimal point (the CSV separates fields with commas).
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
$p = if ($GamePid -gt 0) { Get-Process -Id $GamePid -ErrorAction SilentlyContinue } else { $null }
if ($p -and $p.StartTime -and $p.StartTime.ToUniversalTime().Ticks -eq $StartTicks) { $p.WaitForExit() }
Start-Sleep -Seconds 2
New-Item -ItemType Directory -Force (Join-Path $History 'builds') | Out-Null

$start = [DateTime]::new($StartTicks, [DateTimeKind]::Utc).ToLocalTime()
# Local time (27/11/2026 14:52:11) or ISO in UTC (2026-11-27T19:55:40.000630Z), as different forks log it.
$rx = '^(?:(?<d>\d\d/\d\d/\d{4}) (?<t>\d\d:\d\d:\d\d)|(?<iso>\d{4}-\d\d-\d\dT\S+Z)) .*host: (?<fps>[\d.]+) fps, (?<ms>[\d.]+) ms/frame.* (?<dr>\d+) draws/frame'
$world = New-Object System.Collections.Generic.List[object]
$first = $null; $vram = @(); $errors = 0; $removed = $false; $windowClosed = $false
foreach ($line in [IO.File]::ReadLines($Log)) {
    $m = [regex]::Match($line, $rx)
    if ($m.Success) {
        if ([int]$m.Groups['dr'].Value -ge 1000) {
            $world.Add([pscustomobject]@{ fps = [double]$m.Groups['fps'].Value; ms = [double]$m.Groups['ms'].Value })
            if (-not $first) {
                $first = if ($m.Groups['iso'].Success) { [DateTimeOffset]::Parse($m.Groups['iso'].Value).LocalDateTime }
                    else { [DateTime]::ParseExact("$($m.Groups['d'].Value) $($m.Groups['t'].Value)", 'dd/MM/yyyy HH:mm:ss', $null) }
            }
        }
        continue
    }
    # Streamline's "presentCommon was not observed" is logged as an error but is harmless.
    if ($line.Contains(' ERROR ') -and -not $line.Contains('presentCommon')) { $errors++ }
    if ($line.Contains('device removed') -or $line.Contains('0x887A0005') -or $line.Contains('0x887A0006')) { $removed = $true }
    if ($line.Contains('window closed')) { $windowClosed = $true }
    $v = [regex]::Match($line, "the card's own: budget (?<b>\d+) MB, in use (?<u>\d+) MB")
    if ($v.Success -and [double]$v.Groups['b'].Value -gt 0) { $vram += 100 * [double]$v.Groups['u'].Value / [double]$v.Groups['b'].Value }
}
$logEnd = (Get-Item -LiteralPath $Log).LastWriteTime
$data = if ($DataDir) { $DataDir } else { Join-Path (Split-Path $Log) 'data' }
$crash = @(Get-ChildItem (Join-Path $data '7952987A\temp') -Filter '*.crash.log' -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $start -and $_.LastWriteTime -le $logEnd.AddMinutes(1) }).Count -gt 0

function Pct([double[]]$xs, [double]$q) { if (-not $xs.Count) { return $null }; $s = $xs | Sort-Object; $s[[int][math]::Floor(($s.Count - 1) * $q)] }
$fps = [double[]]@($world | ForEach-Object fps); $ms = [double[]]@($world | ForEach-Object ms)
$median = Pct $fps 0.5; $p10 = Pct $fps 0.1
$mean = if ($fps.Count) { ($fps | Measure-Object -Average).Average } else { $null }
$msMedian = Pct $ms 0.5
$under3 = if ($fps.Count) { 100.0 * @($fps | Where-Object { $_ -lt 3 }).Count / $fps.Count } else { $null }
$toWorld = if ($first) { [int]($first - $start).TotalSeconds } else { $null }
$vramMean = if ($vram.Count) { [math]::Round(($vram | Measure-Object -Average).Average) } else { $null }
$minutes = [int]($logEnd - $start).TotalMinutes

$score = 0.0
if ($fps.Count) {
    $score += [math]::Min(1.0, $median / 30) * 40 + [math]::Min(1.0, $p10 / 30) * 20
    $score += (1 - $under3 / 100) * 15
    if ($toWorld) { $score += [math]::Min(1.0, 300.0 / [math]::Max(1, $toWorld)) * 15 }
}
if (-not $removed -and -not $crash -and $errors -eq 0) { $score += 10 }
$score = [math]::Round($score, 1)
$ending = if ($removed) { 'GPU removed (crash)' } elseif ($crash) { 'game crash' } elseif ($windowClosed) { 'window closed' } else { 'ended' }

# The build that ran: archived once per hash.
$sha = (Get-FileHash -LiteralPath $Exe -Algorithm SHA256).Hash
$folder = Join-Path $History "builds\$($sha.Substring(0, 12))"
if (-not (Test-Path $folder)) {
    New-Item -ItemType Directory -Force $folder | Out-Null
    Copy-Item -LiteralPath $Exe $folder
    $pdb = [IO.Path]::ChangeExtension($Exe, '.pdb'); if (Test-Path $pdb) { Copy-Item -LiteralPath $pdb $folder }
    $manifest = Join-Path (Split-Path (Split-Path $Exe)) 'build.json'; if (Test-Path $manifest) { Copy-Item -LiteralPath $manifest $folder }
}
Copy-Item -LiteralPath $Settings (Join-Path $folder ("config-" + $start.ToString('yyyyMMdd-HHmmss') + '.txt')) -ErrorAction SilentlyContinue

$f = { param($x, $d = 1) if ($null -eq $x) { '' } else { [math]::Round([double]$x, $d) } }
$csv = Join-Path $History 'history.csv'
if (-not (Test-Path $csv)) { 'start,build,score,ending,minutes,to_world_s,world_samples,fps_mean,fps_median,fps_p10,ms_median,pct_under_3fps,vram_pct_budget,errors,log' | Set-Content $csv -Encoding utf8 }
(@($start.ToString('yyyy-MM-dd HH:mm:ss'), $sha.Substring(0, 12), $score, $ending, $minutes, $toWorld, $fps.Count, (& $f $mean), (& $f $median), (& $f $p10), (& $f $msMedian 0), (& $f $under3 0), $vramMean, $errors, $Log) -join ',') |
    Add-Content $csv -Encoding utf8
$md = Join-Path $History 'history.md'
if (-not (Test-Path $md)) { "# Session history`n`nScore 0-100: performance 60 (median fps 40 + worst-10% fps 20, against 30 fps), stability 25 (no drops under 3 fps 15 + no error/crash 10), loading 15 (up to 300 s to the world).`n" | Set-Content $md -Encoding utf8 }
@"

## $($start.ToString('yyyy-MM-dd HH:mm')) - score $score / 100
- Build: ``$($sha.Substring(0, 12))`` (archived in ``builds\$($sha.Substring(0, 12))``)
- Ending: $ending after $minutes min; to the world: $(if ($toWorld) { "$toWorld s" } else { 'not reached' })
- World fps ($($fps.Count) samples of 5 s): mean $(& $f $mean), median $(& $f $median), worst 10% $(& $f $p10), $(& $f $msMedian 0) ms a frame
- Drops under 3 fps: $(& $f $under3 0)%; VRAM: $vramMean% of the budget; errors in the log: $errors
"@ | Add-Content $md -Encoding utf8
