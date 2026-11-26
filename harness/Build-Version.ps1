<#
.SYNOPSIS
  Build step: compiles VIctory, runs the tests and creates a numbered version.

.DESCRIPTION
  Release build (diagnostics + Agility SDK exports), tests for victory-gpu and
  victory-hle, then versions\vNNN-<name>-<sha8>\ under work_dir with the exe,
  pdb, D3D12\ and manifest.json (base, notes, hashes, shader-translator hash,
  test results, build log). Prints the version id last.
  Paths come from harness.toml (see harness.example.toml).

.EXAMPLE
  .\Build-Version.ps1 -Source D:\victory\cand4 -Name series-s-planes -Notes 'two-plane composition'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Source,      # VIctory source folder (with Cargo.toml)
    [Parameter(Mandatory)][string]$Name,        # short label for the change, e.g. 'series-s-planes'
    [string]$Notes = '',                        # what this version changes (goes to the manifest and the scoreboard)
    [string]$Base = '',                         # base commit (default: the source's .victory-base file, if any)
    [switch]$SkipTests,
    [string]$Config = ''                        # harness.toml (default: next to this script)
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$cfg = Get-HarnessConfig $Config $PSScriptRoot
$workDir = $cfg['work_dir']
$agility = $cfg['agility_bin']
$toolchain = '+' + $cfg['rust_toolchain']
if (-not $agility -or -not (Test-Path -LiteralPath "$agility\D3D12Core.dll")) { throw "agility_bin in harness.toml must point to the folder with D3D12Core.dll" }
if (-not (Test-Path -LiteralPath "$Source\Cargo.toml")) { throw "No Cargo.toml in $Source" }
if ($Name -notmatch '^[a-z0-9][a-z0-9-]{0,30}$') { throw 'Name: lower-case letters, digits and hyphens (up to 31)' }
$versionsDir = Join-Path $workDir 'versions'
if (-not (Test-Path -LiteralPath $versionsDir)) { New-Item -ItemType Directory -Path $versionsDir | Out-Null }

if ($cfg['vcvars']) {
    if (-not (Test-Path -LiteralPath $cfg['vcvars'])) { throw "vcvars not found: $($cfg['vcvars'])" }
    cmd /c "`"$($cfg['vcvars'])`" >nul 2>nul && set" | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process') }
    }
}
$log = Join-Path $versionsDir "build-$Name-$(Get-Date -Format yyyyMMdd-HHmmss).log"
Push-Location $Source
try {
    $ErrorActionPreference = 'Continue'
    $started = Get-Date
    & cargo $toolchain rustc --offline --locked --release --features diagnostics -p victory --bin victory -- `
        -C 'link-arg=/EXPORT:D3D12SDKPath,DATA' -C 'link-arg=/EXPORT:D3D12SDKVersion,DATA' 2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $log | Select-String '^error' | ForEach-Object { Write-Host $_ }
    $buildExit = $LASTEXITCODE
    $seconds = [int]((Get-Date) - $started).TotalSeconds
    if ($buildExit -ne 0) { throw "Build failed (exit $buildExit); log at $log" }
    $tests = [ordered]@{}
    if (-not $SkipTests) {
        foreach ($pkg in 'victory-gpu', 'victory-hle') {
            $output = & cargo $toolchain test --offline --locked --release -p $pkg --lib -- --test-threads=1 2>&1 | ForEach-Object { "$_" }
            $output | Add-Content -LiteralPath $log
            $r = $output | Select-String 'test result: \w+\. (\d+) passed; (\d+) failed' | Select-Object -Last 1
            $failures = @($output | Select-String '^test (\S+) \.\.\. FAILED' | ForEach-Object { $_.Matches[0].Groups[1].Value })
            $tests[$pkg] = [ordered]@{
                passed = $(if ($r) { [int]$r.Matches[0].Groups[1].Value } else { $null })
                failed = $(if ($r) { [int]$r.Matches[0].Groups[2].Value } else { $null })
                failures = $failures
            }
        }
    }
} finally {
    $ErrorActionPreference = 'Stop'
    Pop-Location
}

$exe = Join-Path $Source 'target\release\victory.exe'
$sha = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
$n = @(Get-ChildItem -LiteralPath $versionsDir -Directory -Filter 'v*').Count + 1
$id = 'v{0:D3}-{1}-{2}' -f $n, $Name, $sha.Substring(0, 8).ToLower()
$target = Join-Path $versionsDir $id
New-Item -ItemType Directory -Path "$target\D3D12" | Out-Null
Copy-Item -LiteralPath $exe, (Join-Path $Source 'target\release\victory.pdb') -Destination $target
Copy-Item -LiteralPath "$agility\D3D12Core.dll", "$agility\d3d12SDKLayers.dll" -Destination "$target\D3D12"

# Shader-translator hash: versions with the same hash translate identically (the cache is safe either way).
$shaderSrc = Join-Path $Source 'crates\victory-shader\src'
$parts = Get-ChildItem -LiteralPath $shaderSrc -Recurse -File | Sort-Object FullName | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName).Hash }
$translator = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::ASCII.GetBytes(($parts -join '')))).Replace('-', '').Substring(0, 16)
if (-not $Base -and (Test-Path -LiteralPath "$Source\.victory-base")) { $Base = (Get-Content -LiteralPath "$Source\.victory-base" -Raw).Trim() }

# The manifest holds local paths (source, build_log): it stays in work_dir and is not published as-is.
$manifest = [ordered]@{
    version = $id; name = $Name; notes = $Notes; base = $(if ($Base) { $Base } else { 'unknown' })
    source = $Source; built_at = (Get-Date).ToString('s'); build_seconds = $seconds
    exe_sha256 = $sha; pdb_sha256 = (Get-FileHash -LiteralPath "$target\victory.pdb").Hash
    shader_translator = $translator; tests = $tests; build_log = $log
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$target\manifest.json" -Encoding utf8
Write-Host "Version $id ready in $target (build $seconds s)"
foreach ($k in $tests.Keys) { Write-Host ("  tests {0}: {1} passed, {2} failed {3}" -f $k, $tests[$k].passed, $tests[$k].failed, ($tests[$k].failures -join ', ')) }
$id
