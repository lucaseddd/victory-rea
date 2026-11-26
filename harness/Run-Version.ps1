<#
.SYNOPSIS
  Run step: runs one version unattended, scores it, checks for FPS drops and updates the scoreboard.

.DESCRIPTION
  Copies the version to work_dir\runtime\ (one fixed path, so one firewall rule covers every
  version), restores the seed save, starts the title, presses Enter in the menus, records the
  milestones, closes the game at the end, computes the score, compares it with the previous
  warm-cache run of the same mode and updates scoreboard.csv / scoreboard.md.
  No key presses are needed. Run in PowerShell as administrator (firewall rules are read).

.EXAMPLE
  .\Run-Version.ps1 -Version v001-cand4-series-s-2ffd8cb5
.EXAMPLE
  .\Run-Version.ps1 -Version latest -Extra @{ VICTORY_QUEUE2 = '1' }
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Version,                   # id under versions\ (or 'latest')
    [ValidateSet('quick', 'series-x')][string]$Mode = 'quick', # quick = Series S + 1280x720; series-x = reference
    [int]$DiskWorkers = 0,                                    # VICTORY_DSTORAGE_WORKERS (0 = default)
    [hashtable]$Extra = @{},                                  # extra VICTORY_* settings, e.g. @{ VICTORY_QUEUE2 = '1' }
    [int]$MeasurePlayableS = 120,                             # seconds measured after "playable", then close
    [int]$MaxMinutes = 45,                                    # hard time limit
    [int]$NoProgressMin = 12,                                 # close after this many minutes without a new milestone
    [switch]$MapOnly,                                         # map without running
    [string]$Config = ''                                      # harness.toml (default: next to this script)
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$cfg = Get-HarnessConfig $Config $PSScriptRoot
$workDir = $cfg['work_dir']
$titleExe = $cfg['title_exe']
if (-not $titleExe -or -not (Test-Path -LiteralPath $titleExe -PathType Leaf)) { throw "title_exe in harness.toml does not point to a file" }
$runtime = Join-Path $workDir 'runtime'
$runtimeExe = Join-Path $runtime 'victory.exe'
foreach ($d in 'runtime', 'runs', 'cache') { $p = Join-Path $workDir $d; if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p | Out-Null } }

if ($Version -eq 'latest') { $Version = (Get-ChildItem -LiteralPath "$workDir\versions" -Directory -Filter 'v*' | Sort-Object Name | Select-Object -Last 1).Name }
$versionDir = Join-Path $workDir "versions\$Version"
$manifest = Get-Content -LiteralPath "$versionDir\manifest.json" -Raw | ConvertFrom-Json
if ((Get-FileHash -LiteralPath "$versionDir\victory.exe").Hash -ne $manifest.exe_sha256) { throw "versions\$Version\victory.exe does not match its manifest" }

if (Get-Process -Name victory -ErrorAction SilentlyContinue) { throw 'Another VIctory session is already running.' }
$fwProfiles = @(Get-NetFirewallProfile -PolicyStore ActiveStore)
if ($fwProfiles.Count -ne 3 -or @($fwProfiles | Where-Object Enabled -ne 'True').Count) { throw 'Windows Firewall must be enabled for all three profiles.' }
Assert-OutboundBlock $titleExe
Assert-OutboundBlock $runtimeExe

# Deploy the version to the fixed path (only files that changed).
robocopy $versionDir $runtime victory.exe victory.pdb /COPY:DAT /NFL /NDL /NJH /NJS /NP | Out-Null
robocopy "$versionDir\D3D12" "$runtime\D3D12" /MIR /COPY:DAT /NFL /NDL /NJH /NJS /NP | Out-Null
if ((Get-FileHash -LiteralPath $runtimeExe).Hash -ne $manifest.exe_sha256) { throw 'runtime\victory.exe does not match the version' }

$console = if ($Mode -eq 'quick') { 'series-s' } else { 'series-x' }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$base = Join-Path $workDir "runs\$Version-$Mode-$stamp"
$keysFile = "$base.keys.txt"
if (-not $MapOnly) {
    $seed = Join-Path $workDir 'seed-data'
    if (-not (Test-Path -LiteralPath $seed)) { throw "Missing $seed (the starting save)" }
    robocopy $seed (Join-Path $workDir 'data') /MIR /COPY:DAT /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw 'Failed to restore the seed save' }
}
$warmCache = @(Get-ChildItem -LiteralPath "$workDir\cache\pipelines" -File -ErrorAction SilentlyContinue).Count -gt 0

$settings = @{
    VICTORY_CACHE_DIR = Join-Path $workDir 'cache'; VICTORY_DATA_DIR = Join-Path $workDir 'data'; VICTORY_LOG = 'info'
    VICTORY_CARD_SYNC_BATCH = '1'; VICTORY_COPY_CHANGED = '1'; VICTORY_CARD_BUFFERS_MB = '256'; VICTORY_CARD_WINDOWS_MB = '0'
    VICTORY_LATE_WAIT = '1'; VICTORY_ASYNC_SUBMIT = '1'; VICTORY_ASYNC_PRESENT = '0'; VICTORY_JOIN_PARTS = '1'
    VICTORY_BACK_OWN_VIEW = '1'; VICTORY_INDIRECT_WINDOW = '1'; VICTORY_INDIRECT_GATHER = '1'; VICTORY_CARD_REHASH_RUNS = '1'
    VICTORY_TEXTURE_DROP_MIPS = '0'; VICTORY_TEXTURE_STAGE_MS = '120'; VICTORY_RELAY = '2'; VICTORY_CARD_FETCH_INFLIGHT = '0'
    VICTORY_QUEUE2_REFETCH = '1'; VICTORY_HEAP_LOCKS = '0'; VICTORY_TABLE_STAGES = '0'; VICTORY_QUEUE2 = '0'
    VICTORY_HEAP_WORKER = '0'; VICTORY_LEVELS_ON_DEMAND = '1'; VICTORY_TEXTURE_AUTO_VRAM = '0'
    VICTORY_FRAME_LOG = '1'; VICTORY_DSTORAGE_STATS = '1'
}
if ($Mode -eq 'quick') { $settings.VICTORY_DISPLAY_MODE = '1280x720' }
if ($DiskWorkers -gt 0) { $settings.VICTORY_DSTORAGE_WORKERS = [string]$DiskWorkers }
if (-not $MapOnly) { $settings.VICTORY_KEYS_FILE = $keysFile }
foreach ($k in $Extra.Keys) { if ($k -notmatch '^VICTORY_[A-Z0-9_]+$') { throw "Invalid Extra key: $k" }; $settings[$k] = [string]$Extra[$k] }

$previous = @{}
try {
    foreach ($envName in @([Environment]::GetEnvironmentVariables('Process').Keys)) {
        if ($envName -like 'VICTORY_*' -and -not $settings.ContainsKey($envName)) { $previous[$envName] = [Environment]::GetEnvironmentVariable($envName, 'Process'); [Environment]::SetEnvironmentVariable($envName, $null, 'Process') }
    }
    foreach ($key in $settings.Keys) { $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process'); [Environment]::SetEnvironmentVariable($key, $settings[$key], 'Process') }
    ($settings.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" }) + "version=$Version" + "console=$console" + "warm_cache=$warmCache" |
        Set-Content -LiteralPath "$base.settings.txt" -Encoding utf8
    $arguments = 'run --console {0} "{1}"' -f $console, $titleExe
    if (-not $MapOnly) { $arguments = $arguments.Insert(4, '--execute ') }
    $params = @{ FilePath = $runtimeExe; ArgumentList = $arguments; WorkingDirectory = $workDir; RedirectStandardOutput = "$base.stdout"; RedirectStandardError = "$base.stderr"; PassThru = $true }
    if ($MapOnly) { $params.WindowStyle = 'Hidden'; $params.Wait = $true }
    $proc = Start-Process @params
} finally {
    foreach ($key in $previous.Keys) { [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process') }
}
if ($MapOnly) {
    Get-Content -LiteralPath "$base.stdout" | Select-String 'console|missing|not executing'
    if ($proc.ExitCode -ne 0) { throw "Mapping failed (exit $($proc.ExitCode))" }
    return
}
Write-Host "Running $Version ($Mode, $console, $(if ($warmCache) { 'warm' } else { 'cold' }) cache). PID $($proc.Id). Nothing to do: the test ends by itself."
& (Join-Path $PSScriptRoot 'Watch-Run.ps1') -Stderr "$base.stderr" -ProcessId $proc.Id -OutBase $base -KeysFile $keysFile `
    -SavesDir (Join-Path $workDir 'data') -MeasurePlayableS $MeasurePlayableS -MaxMinutes $MaxMinutes -NoProgressMin $NoProgressMin

# Scoreboard and FPS-drop check against the previous run of the same mode (warm cache on both).
$score = Get-Content -LiteralPath "$base.score.json" -Raw | ConvertFrom-Json
$csv = Join-Path $workDir 'scoreboard.csv'
$prior = if (Test-Path -LiteralPath $csv) {
    Import-Csv -LiteralPath $csv | Where-Object { $_.mode -eq $Mode -and $_.warm_cache -eq 'True' -and $_.version -ne $Version } | Select-Object -Last 1
}
$cmp = $null
if ($prior -and $warmCache) {
    $cmp = & (Join-Path $PSScriptRoot 'Compare-Runs.ps1') -Current "$base.score.json" -Previous $prior.score_json
    $cmp.findings | Set-Content -LiteralPath "$base.comparison.txt" -Encoding utf8
}
[pscustomobject]@{
    when = (Get-Date).ToString('s'); version = $Version; notes = $manifest.notes; mode = $Mode; warm_cache = $warmCache
    score = $score.score_total; progress = $score.components.progress; world_fps = $score.fps.world_median; world_ms_p95 = $score.fps.world_ms_p95
    first_3d_scene_s = $score.times_s.first_3d_scene; playable_s = $score.times_s.playable; drops_pct = $score.world_drops.drop_pct
    hitches_1s = $score.world_drops.hitches_1s; gpu_lost = $score.gpu_lost
    drop_check = $(if ($cmp) { $cmp.verdict } elseif (-not $warmCache) { 'cold cache (not compared)' } else { 'first run of this mode' })
    compared_with = $(if ($prior) { $prior.version } else { '' }); score_json = "$base.score.json"
} | Export-Csv -LiteralPath $csv -NoTypeInformation -Append -Encoding utf8

$rows = Import-Csv -LiteralPath $csv
@(
    '# Version scoreboard'
    ''
    '| When | Version | Mode | Score | Progress | World FPS | p95 ms | First 3D scene (s) | Playable (s) | Drops % | Hitches > 1 s | Drop check |'
    '|---|---|---|---|---|---|---|---|---|---|---|---|'
    ($rows | ForEach-Object { "| $($_.when) | $($_.version) | $($_.mode) | $($_.score) | $($_.progress) | $($_.world_fps) | $($_.world_ms_p95) | $($_.first_3d_scene_s) | $($_.playable_s) | $($_.drops_pct) | $($_.hitches_1s) | $($_.drop_check) $(if ($_.compared_with) { "vs $($_.compared_with)" }) |" })
) | Set-Content -LiteralPath (Join-Path $workDir 'scoreboard.md') -Encoding utf8
Write-Host "Score $($score.score_total). Scoreboard: $(Join-Path $workDir 'scoreboard.md')"
if ($cmp) { Write-Host "FPS-drop check: $($cmp.verdict)"; $cmp.findings | ForEach-Object { Write-Host "  $_" } }
