<#
.SYNOPSIS
  Run step: runs one version unattended, scores it, checks for FPS drops and updates the scoreboard.

.DESCRIPTION
  Copies the version to work_dir\runtime\ (one fixed path, so one firewall rule covers every
  version), restores the seed save, starts the title, presses Enter in the menus, records the
  milestones, closes the game at the end, computes the score, compares it with the previous
  warm-cache run of the same profile and updates placar.csv / placar.md.
  No key presses are needed. Run in PowerShell as administrator (firewall rules are read).

.EXAMPLE
  .\Rodar-Versao.ps1 -Versao v001-cand4-series-s-2ffd8cb5
.EXAMPLE
  .\Rodar-Versao.ps1 -Versao ultima -Extra @{ VICTORY_QUEUE2 = '1' }
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Versao,                    # id under versoes\ (or 'ultima' = latest)
    [ValidateSet('rapido', 'series-x')][string]$Perfil = 'rapido',   # rapido = quick (Series S); series-x = reference
    [int]$DiscoWorkers = 0,                                   # VICTORY_DSTORAGE_WORKERS (0 = default)
    [hashtable]$Extra = @{},                                  # extra VICTORY_* settings, e.g. @{ VICTORY_QUEUE2 = '1' }
    [int]$MedirJogavelS = 120,                                # seconds measured after "playable", then close
    [int]$MaxMinutos = 45,                                    # hard time limit
    [int]$SemProgressoMin = 12,                               # close after this many minutes without a new milestone
    [switch]$MapOnly,                                         # map without running
    [string]$Config = ''                                      # harness.toml (default: next to this script)
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$cfg = Get-HarnessConfig $Config $PSScriptRoot
$raiz = $cfg['work_dir']
$titleExe = $cfg['title_exe']
if (-not $titleExe -or -not (Test-Path -LiteralPath $titleExe -PathType Leaf)) { throw "title_exe in harness.toml does not point to a file" }
$runtime = Join-Path $raiz 'runtime'
$runtimeExe = Join-Path $runtime 'victory.exe'
foreach ($d in 'runtime', 'rodadas', 'cache') { $p = Join-Path $raiz $d; if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p | Out-Null } }

if ($Versao -eq 'ultima') { $Versao = (Get-ChildItem -LiteralPath "$raiz\versoes" -Directory -Filter 'v*' | Sort-Object Name | Select-Object -Last 1).Name }
$pasta = Join-Path $raiz "versoes\$Versao"
$manifesto = Get-Content -LiteralPath "$pasta\manifesto.json" -Raw | ConvertFrom-Json
if ((Get-FileHash -LiteralPath "$pasta\victory.exe").Hash -ne $manifesto.exe_sha256) { throw "versoes\$Versao\victory.exe does not match its manifest" }

if (Get-Process -Name victory -ErrorAction SilentlyContinue) { throw 'Another VIctory session is already running.' }
$profiles = @(Get-NetFirewallProfile -PolicyStore ActiveStore)
if ($profiles.Count -ne 3 -or @($profiles | Where-Object Enabled -ne 'True').Count) { throw 'Windows Firewall must be enabled for all three profiles.' }
Assert-OutboundBlock $titleExe
Assert-OutboundBlock $runtimeExe

# Deploy the version to the fixed path (only files that changed).
robocopy $pasta $runtime victory.exe victory.pdb /COPY:DAT /NFL /NDL /NJH /NJS /NP | Out-Null
robocopy "$pasta\D3D12" "$runtime\D3D12" /MIR /COPY:DAT /NFL /NDL /NJH /NJS /NP | Out-Null
if ((Get-FileHash -LiteralPath $runtimeExe).Hash -ne $manifesto.exe_sha256) { throw 'runtime\victory.exe does not match the version' }

$console = if ($Perfil -eq 'rapido') { 'series-s' } else { 'series-x' }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$base = Join-Path $raiz "rodadas\$Versao-$Perfil-$stamp"
$keysFile = "$base.teclas.txt"
if (-not $MapOnly) {
    $semente = Join-Path $raiz 'dados-semente'
    if (-not (Test-Path -LiteralPath $semente)) { throw "Missing $semente (the starting save)" }
    robocopy $semente (Join-Path $raiz 'dados') /MIR /COPY:DAT /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw 'Failed to restore the seed save' }
}
$cacheQuente = @(Get-ChildItem -LiteralPath "$raiz\cache\pipelines" -File -ErrorAction SilentlyContinue).Count -gt 0

$settings = @{
    VICTORY_CACHE_DIR = Join-Path $raiz 'cache'; VICTORY_DATA_DIR = Join-Path $raiz 'dados'; VICTORY_LOG = 'info'
    VICTORY_CARD_SYNC_BATCH = '1'; VICTORY_COPY_CHANGED = '1'; VICTORY_CARD_BUFFERS_MB = '256'; VICTORY_CARD_WINDOWS_MB = '0'
    VICTORY_LATE_WAIT = '1'; VICTORY_ASYNC_SUBMIT = '1'; VICTORY_ASYNC_PRESENT = '0'; VICTORY_JOIN_PARTS = '1'
    VICTORY_BACK_OWN_VIEW = '1'; VICTORY_INDIRECT_WINDOW = '1'; VICTORY_INDIRECT_GATHER = '1'; VICTORY_CARD_REHASH_RUNS = '1'
    VICTORY_TEXTURE_DROP_MIPS = '0'; VICTORY_TEXTURE_STAGE_MS = '120'; VICTORY_RELAY = '2'; VICTORY_CARD_FETCH_INFLIGHT = '0'
    VICTORY_QUEUE2_REFETCH = '1'; VICTORY_HEAP_LOCKS = '0'; VICTORY_TABLE_STAGES = '0'; VICTORY_QUEUE2 = '0'
    VICTORY_HEAP_WORKER = '0'; VICTORY_LEVELS_ON_DEMAND = '1'; VICTORY_TEXTURE_AUTO_VRAM = '0'
    VICTORY_FRAME_LOG = '1'; VICTORY_DSTORAGE_STATS = '1'
}
if ($Perfil -eq 'rapido') { $settings.VICTORY_DISPLAY_MODE = '1280x720' }
if ($DiscoWorkers -gt 0) { $settings.VICTORY_DSTORAGE_WORKERS = [string]$DiscoWorkers }
if (-not $MapOnly) { $settings.VICTORY_KEYS_FILE = $keysFile }
foreach ($k in $Extra.Keys) { if ($k -notmatch '^VICTORY_[A-Z0-9_]+$') { throw "Invalid Extra key: $k" }; $settings[$k] = [string]$Extra[$k] }

$previous = @{}
try {
    foreach ($name in @([Environment]::GetEnvironmentVariables('Process').Keys)) {
        if ($name -like 'VICTORY_*' -and -not $settings.ContainsKey($name)) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process'); [Environment]::SetEnvironmentVariable($name, $null, 'Process') }
    }
    foreach ($key in $settings.Keys) { $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process'); [Environment]::SetEnvironmentVariable($key, $settings[$key], 'Process') }
    ($settings.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" }) + "versao=$Versao" + "console=$console" + "cache_quente=$cacheQuente" |
        Set-Content -LiteralPath "$base.settings.txt" -Encoding utf8
    $arguments = 'run --console {0} "{1}"' -f $console, $titleExe
    if (-not $MapOnly) { $arguments = $arguments.Insert(4, '--execute ') }
    $params = @{ FilePath = $runtimeExe; ArgumentList = $arguments; WorkingDirectory = $raiz; RedirectStandardOutput = "$base.stdout"; RedirectStandardError = "$base.stderr"; PassThru = $true }
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
Write-Host "Running $Versao ($Perfil, $console, $(if ($cacheQuente) { 'warm' } else { 'cold' }) cache). PID $($proc.Id). Nothing to do: the test ends by itself."
& (Join-Path $PSScriptRoot 'Vigiar-Rodada.ps1') -Stderr "$base.stderr" -ProcessId $proc.Id -OutBase $base -KeysFile $keysFile `
    -SavesDir (Join-Path $raiz 'dados') -MedirJogavelS $MedirJogavelS -MaxMinutos $MaxMinutos -SemProgressoMin $SemProgressoMin

# Scoreboard and FPS-drop check against the previous run of the same profile (warm cache on both).
$score = Get-Content -LiteralPath "$base.score.json" -Raw | ConvertFrom-Json
$csv = Join-Path $raiz 'placar.csv'
$anterior = if (Test-Path -LiteralPath $csv) {
    Import-Csv -LiteralPath $csv | Where-Object { $_.perfil -eq $Perfil -and $_.cache_quente -eq 'True' -and $_.versao -ne $Versao } | Select-Object -Last 1
}
$cmp = $null
if ($anterior -and $cacheQuente) {
    $cmp = & (Join-Path $PSScriptRoot 'Comparar-Rodadas.ps1') -Atual "$base.score.json" -Anterior $anterior.score_json
    $cmp.achados | Set-Content -LiteralPath "$base.comparacao.txt" -Encoding utf8
}
# Scoreboard columns keep their Portuguese names for compatibility with existing placar.csv files.
[pscustomobject]@{
    quando = (Get-Date).ToString('s'); versao = $Versao; notas = $manifesto.notas; perfil = $Perfil; cache_quente = $cacheQuente
    score = $score.score_total; progresso = $score.componentes.progresso; fps_mundo = $score.fps.mundo_mediana; ms_p95_mundo = $score.fps.mundo_ms_p95
    primeira_cena_3d_s = $score.tempos_s.primeira_cena_3d; jogavel_s = $score.tempos_s.jogavel; quedas_pct = $score.quedas_mundo.pct_quedas
    travadas_1s = $score.quedas_mundo.travadas_1s; gpu_perdida = $score.gpu_perdida
    regressao = $(if ($cmp) { $cmp.veredito } elseif (-not $cacheQuente) { 'cold cache (not compared)' } else { 'first run of this profile' })
    comparada_com = $(if ($anterior) { $anterior.versao } else { '' }); score_json = "$base.score.json"
} | Export-Csv -LiteralPath $csv -NoTypeInformation -Append -Encoding utf8

$linhas = Import-Csv -LiteralPath $csv
@(
    '# Version scoreboard'
    ''
    '| When | Version | Profile | Score | Progress | World FPS | p95 ms | First 3D scene (s) | Playable (s) | Drops % | Hitches > 1 s | Drop check |'
    '|---|---|---|---|---|---|---|---|---|---|---|---|'
    ($linhas | ForEach-Object { "| $($_.quando) | $($_.versao) | $($_.perfil) | $($_.score) | $($_.progresso) | $($_.fps_mundo) | $($_.ms_p95_mundo) | $($_.primeira_cena_3d_s) | $($_.jogavel_s) | $($_.quedas_pct) | $($_.travadas_1s) | $($_.regressao) $(if ($_.comparada_com) { "vs $($_.comparada_com)" }) |" })
) | Set-Content -LiteralPath (Join-Path $raiz 'placar.md') -Encoding utf8
Write-Host "Score $($score.score_total). Scoreboard: $(Join-Path $raiz 'placar.md')"
if ($cmp) { Write-Host "FPS-drop check: $($cmp.veredito)"; $cmp.achados | ForEach-Object { Write-Host "  $_" } }
