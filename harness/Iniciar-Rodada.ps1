<#
.SYNOPSIS
  VIctory automated test: starts a run, opens the watcher and produces the score.

.DESCRIPTION
  Generalized from the candidate 4 launcher. No hard-coded paths: everything
  comes from parameters or from a harness.toml (see harness.example.toml).
  Requires a blocking outbound firewall rule for the runtime and for the
  title (the title runs offline). Run it in PowerShell as administrator.

  Required runtime patches: see harness/patches/README.md.
  Parameter names are kept in Portuguese for compatibility with earlier
  runs; harness/README.md explains each one.

.EXAMPLE
  .\Iniciar-Rodada.ps1 -Config D:\tests\harness.toml -Rapido -MapOnly
.EXAMPLE
  .\Iniciar-Rodada.ps1 -Config D:\tests\harness.toml -Rapido -FecharAposJogavelS 120
#>
[CmdletBinding()]
param(
    # Simple TOML file (key = 'value') with runtime_exe, runtime_sha256, title_exe, run_dir.
    [string]$Config = '',
    [string]$RuntimeExe = '',
    [string]$RuntimeSha256 = '',
    [string]$TitleExe = '',
    # Run folder: logs, cache, data, data-semente. Must be outside the repository.
    [string]$RunDir = '',
    # Quick test: Series S, 1280x720 mode reported to the game, automatic Enter, seed save, score.
    [switch]$Rapido,
    [ValidateSet('', 'series-x', 'series-s')][string]$Console = '',
    # Display mode reported to the game (VICTORY_DISPLAY_MODE, e.g. 1280x720). '' = runtime default.
    [string]$DisplayMode = '',
    # Automatic Enter through the menus until the first 3D scene (VICTORY_KEYS_FILE + Vigiar-Rodada.ps1).
    [switch]$AutoEnter,
    [int]$EnterApos = 20,
    [int]$EnterIntervalo = 6,
    # Simultaneous DirectStorage reads (VICTORY_DSTORAGE_WORKERS). 0 = default (one per core).
    [ValidateRange(0, 64)][int]$DiscoWorkers = 0,
    # Close the game N s after F9 (playable). 0 = do not close.
    [int]$FecharAposJogavelS = 0,
    [int]$MaxMinutos = 0,
    # Do not restore data\ from data-semente\ (continue from the previous run's save).
    [switch]$SemSemente,
    # Do not open the watcher (no automatic Enter, no score).
    [switch]$SemVigia,
    # Axes from earlier candidates (defaults = control profile):
    [ValidateSet(0, 1)][int]$Fila = 0,
    [ValidateSet(0, 1)][int]$Worker = 0,
    [ValidateSet(0, 1)][int]$Mips = 1,
    [ValidateRange(0, 1024)][int]$PequenosMB = 0,
    [ValidateRange(-1, 8192)][int]$ReservaAlvosMB = -1,
    [ValidateRange(-1, 6144)][int]$PisoTexturasMB = -1,
    [switch]$TexturaAuto,
    [switch]$SemContadores,
    [switch]$Capturar,
    [switch]$MapOnly
)

$ErrorActionPreference = 'Stop'
$harnessDir = $PSScriptRoot
$repoRoot = Split-Path -Parent $harnessDir

function Read-FlatToml([string]$path) {
    $map = @{}
    foreach ($line in Get-Content -LiteralPath $path) {
        $l = $line.Trim()
        if (-not $l -or $l.StartsWith('#') -or $l.StartsWith('[')) { continue }
        if ($l -match "^([A-Za-z0-9_]+)\s*=\s*(?:'([^']*)'|`"([^`"]*)`")\s*(#.*)?$") {
            # 'literal' is kept as is; "basic" undoes backslash escaping.
            $map[$matches[1]] = $(if ($null -ne $matches[2] -and $matches[2] -ne '') { $matches[2] } else { $matches[3] -replace '\\\\', '\' })
        }
    }
    $map
}

if ($Config) {
    $cfg = Read-FlatToml $Config
    if (-not $RuntimeExe)    { $RuntimeExe    = $cfg['runtime_exe'] }
    if (-not $RuntimeSha256) { $RuntimeSha256 = $cfg['runtime_sha256'] }
    if (-not $TitleExe)      { $TitleExe      = $cfg['title_exe'] }
    if (-not $RunDir)        { $RunDir        = $cfg['run_dir'] }
}
foreach ($pair in @(@('RuntimeExe', $RuntimeExe), @('TitleExe', $TitleExe), @('RunDir', $RunDir))) {
    if (-not $pair[1]) { throw "Missing $($pair[0]) (parameter or harness.toml)" }
}
$RunDir = (Resolve-Path -LiteralPath $RunDir).ProviderPath
# Nothing derived from the game may land inside the repository.
if ($RunDir.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "RunDir ($RunDir) is inside the repository. Use a folder outside it."
}

if ($Rapido) {
    if (-not $Console) { $Console = 'series-s' }
    if (-not $DisplayMode) { $DisplayMode = '1280x720' }
    if (-not $PSBoundParameters.ContainsKey('AutoEnter')) { $AutoEnter = $true }
}
if (-not $Console) { $Console = 'series-x' }
if ($DisplayMode -and $DisplayMode -notmatch '^\d{3,4}x\d{3,4}$') { throw "Invalid DisplayMode: $DisplayMode (use WIDTHxHEIGHT)" }

function Assert-OutboundBlock([string]$ProgramPath) {
    $rules = Get-NetFirewallApplicationFilter -PolicyStore ActiveStore -Program $ProgramPath -ErrorAction SilentlyContinue |
        Get-NetFirewallRule -ErrorAction SilentlyContinue |
        Where-Object { $_.Enabled -eq 'True' -and $_.Direction -eq 'Outbound' -and $_.Action -eq 'Block' -and $_.Profile -eq 'Any' }
    if (-not $rules) {
        throw "No blocking outbound firewall rule (Profile Any) for $ProgramPath. Run as administrator and create the rule (see harness/README.md)."
    }
}

foreach ($file in @($RuntimeExe, $TitleExe)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing executable: $file" }
}
$exeHash = (Get-FileHash -LiteralPath $RuntimeExe -Algorithm SHA256).Hash
if ($RuntimeSha256 -and $exeHash -ne $RuntimeSha256.ToUpperInvariant()) {
    throw "victory.exe has SHA-256 $exeHash, not the recorded one ($RuntimeSha256)."
}
if (Get-Process -Name victory -ErrorAction SilentlyContinue) { throw 'Another VIctory session is already running.' }
$profiles = @(Get-NetFirewallProfile -PolicyStore ActiveStore)
if ($profiles.Count -ne 3 -or @($profiles | Where-Object Enabled -ne 'True').Count) {
    throw 'Windows Firewall must be enabled for all profiles.'
}
Assert-OutboundBlock $TitleExe
Assert-OutboundBlock $RuntimeExe

$label = '{0}{1}-fila{2}-worker{3}-mips{4}-piso{5}-disco{6}{7}' -f $(if ($Rapido) { 'rapido-' } else { '' }), $Console, $Fila, $Worker, $Mips,
    $(if ($PisoTexturasMB -lt 0) { 'padrao' } else { $PisoTexturasMB }), $(if ($DiscoWorkers) { $DiscoWorkers } else { 'padrao' }),
    $(if ($DisplayMode) { "-$DisplayMode" } else { '' })
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$logBase = Join-Path $RunDir "$label-$stamp"

# Same save on every run: data\ is reset to a copy of data-semente\.
$semente = Join-Path $RunDir 'data-semente'
if (-not $SemSemente -and -not $MapOnly) {
    if (-not (Test-Path -LiteralPath $semente)) { throw "Missing $semente (or use -SemSemente)" }
    robocopy $semente (Join-Path $RunDir 'data') /MIR /COPY:DAT /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Failed to restore the seed save (robocopy $LASTEXITCODE)" }
}

$keysFile = if ($AutoEnter -and -not $SemVigia -and -not $MapOnly) { "$logBase.teclas.txt" } else { '' }
$settings = @{
    VICTORY_CACHE_DIR = Join-Path $RunDir 'cache'
    VICTORY_DATA_DIR = Join-Path $RunDir 'data'
    VICTORY_LOG = 'info'
    VICTORY_CARD_SYNC_BATCH = '1'
    VICTORY_COPY_CHANGED = '1'
    VICTORY_CARD_BUFFERS_MB = '256'
    VICTORY_CARD_WINDOWS_MB = '0'
    VICTORY_LATE_WAIT = '1'
    VICTORY_ASYNC_SUBMIT = '1'
    VICTORY_ASYNC_PRESENT = '0'
    VICTORY_JOIN_PARTS = '1'
    VICTORY_BACK_OWN_VIEW = '1'
    VICTORY_INDIRECT_WINDOW = '1'
    VICTORY_INDIRECT_GATHER = '1'
    VICTORY_CARD_REHASH_RUNS = '1'
    VICTORY_TEXTURE_DROP_MIPS = '0'
    VICTORY_TEXTURE_STAGE_MS = '120'
    VICTORY_RELAY = '2'
    VICTORY_CARD_FETCH_INFLIGHT = '0'
    VICTORY_QUEUE2_REFETCH = '1'
    VICTORY_HEAP_LOCKS = '0'
    VICTORY_TABLE_STAGES = '0'
    VICTORY_QUEUE2 = [string]$Fila
    VICTORY_HEAP_WORKER = [string]$Worker
    VICTORY_LEVELS_ON_DEMAND = [string]$Mips
    VICTORY_TILES_SMALL_WHEN_FULL_MB = [string]$PequenosMB
    VICTORY_TEXTURE_AUTO_VRAM = $(if ($TexturaAuto) { '1' } else { '0' })
    VICTORY_FRAME_LOG = $(if ($SemContadores) { '0' } else { '1' })
    VICTORY_DSTORAGE_STATS = $(if ($SemContadores) { '0' } else { '1' })
}
if ($ReservaAlvosMB -ge 0) { $settings.VICTORY_CARD_ROOM_FOR_TARGETS_MB = [string]$ReservaAlvosMB }
if ($PisoTexturasMB -ge 0) { $settings.VICTORY_TEXTURE_FLOOR_MB = [string]$PisoTexturasMB }
if ($DisplayMode) { $settings.VICTORY_DISPLAY_MODE = $DisplayMode }
if ($DiscoWorkers -gt 0) { $settings.VICTORY_DSTORAGE_WORKERS = [string]$DiscoWorkers }
if ($keysFile) { $settings.VICTORY_KEYS_FILE = $keysFile }
if ($Capturar) {
    $settings.VICTORY_CAPTURE = Join-Path $RunDir "captura-$label-$stamp"
    $settings.VICTORY_CAPTURE_WORLD = '1'
}

$previous = @{}
$arguments = 'run --console {0} "{1}"' -f $Console, $TitleExe
if (-not $MapOnly) { $arguments = $arguments.Insert(4, '--execute ') }

try {
    foreach ($name in @([Environment]::GetEnvironmentVariables('Process').Keys)) {
        if ($name -like 'VICTORY_*' -and -not $settings.ContainsKey($name)) {
            $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
            [Environment]::SetEnvironmentVariable($name, $null, 'Process')
        }
    }
    foreach ($key in $settings.Keys) {
        $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, $settings[$key], 'Process')
    }
    ($settings.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" }) +
        "console=$Console" + "exe_sha256=$exeHash" | Set-Content -LiteralPath "$logBase.settings.txt" -Encoding utf8
    if ($keysFile) { Set-Content -LiteralPath $keysFile -Value '' -Encoding ascii -NoNewline }
    $params = @{
        FilePath = $RuntimeExe
        ArgumentList = $arguments
        WorkingDirectory = $RunDir
        RedirectStandardOutput = "$logBase.stdout"
        RedirectStandardError = "$logBase.stderr"
        PassThru = $true
    }
    if ($MapOnly) { $params.WindowStyle = 'Hidden'; $params.Wait = $true }
    $process = Start-Process @params
    Write-Output "PID=$($process.Id) $label logs=$logBase"
    if ($MapOnly) {
        Get-Content -LiteralPath "$logBase.stdout" -Tail 12
        if ($process.ExitCode -ne 0) {
            Get-Content -LiteralPath "$logBase.stderr" -Tail 12
            throw "Mapping failed with exit code $($process.ExitCode)"
        }
        Write-Output 'Mapping completed with exit code 0.'
    } elseif (-not $SemVigia) {
        $vigia = @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f (Join-Path $harnessDir 'Vigiar-Rodada.ps1')),
            '-Stderr', ('"{0}.stderr"' -f $logBase), '-ProcessId', $process.Id, '-OutBase', ('"{0}"' -f $logBase),
            '-SavesDir', ('"{0}"' -f (Join-Path $RunDir 'data')),
            '-EnterApos', $EnterApos, '-EnterIntervalo', $EnterIntervalo,
            '-FecharAposJogavelS', $FecharAposJogavelS, '-MaxMinutos', $MaxMinutos
        )
        if ($keysFile) { $vigia += @('-KeysFile', ('"{0}"' -f $keysFile)) }
        Start-Process -FilePath 'powershell.exe' -ArgumentList $vigia -WorkingDirectory $RunDir | Out-Null
        Write-Output 'Watcher open: F9 = playable, F10 = mark. Score in <log>.score.md when the game closes.'
    }
} finally {
    foreach ($key in $previous.Keys) {
        [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process')
    }
}
