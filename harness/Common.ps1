# Shared helpers for the harness scripts (dot-sourced). ASCII only on purpose.

function Read-FlatToml([string]$path) {
    # Minimal TOML reader: top-level key = 'literal' or key = "basic" lines only.
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

function Get-HarnessConfig([string]$Config, [string]$ScriptDir) {
    if (-not $Config) { $Config = Join-Path $ScriptDir 'harness.toml' }
    if (-not (Test-Path -LiteralPath $Config)) { throw "Missing $Config (copy harness.example.toml to harness.toml and edit it)" }
    $c = Read-FlatToml $Config
    if (-not $c['work_dir']) { throw "work_dir is not set in $Config" }
    if (-not (Test-Path -LiteralPath $c['work_dir'])) { throw "work_dir does not exist: $($c['work_dir'])" }
    $c['work_dir'] = (Resolve-Path -LiteralPath $c['work_dir']).ProviderPath.TrimEnd('\', '/')
    # Nothing derived from the game may land inside the repository.
    $repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $ScriptDir)).ProviderPath
    if ($c['work_dir'].StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "work_dir ($($c['work_dir'])) is inside the repository. Use a folder outside it."
    }
    if (-not $c['rust_toolchain']) { $c['rust_toolchain'] = '1.98.1' }
    if (-not $c['game_dir'] -and $c['title_exe']) { $c['game_dir'] = Split-Path -Parent $c['title_exe'] }
    $c
}

function Assert-OutboundBlock([string]$ProgramPath) {
    # Finds the rule by program path, whatever its display name. Needs an elevated shell.
    $rules = Get-NetFirewallApplicationFilter -PolicyStore ActiveStore -Program $ProgramPath -ErrorAction SilentlyContinue |
        Get-NetFirewallRule -ErrorAction SilentlyContinue |
        Where-Object { $_.Enabled -eq 'True' -and $_.Direction -eq 'Outbound' -and $_.Action -eq 'Block' -and $_.Profile -eq 'Any' }
    if (-not $rules) {
        throw "No blocking outbound firewall rule (Profile Any) for $ProgramPath. Run as administrator and create it (see harness/README.md)."
    }
}
