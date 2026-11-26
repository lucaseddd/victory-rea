<#
.SYNOPSIS
  Build step: compiles VIctory, runs the tests and creates a numbered version.

.DESCRIPTION
  Release build (diagnostics + Agility SDK exports), tests for victory-gpu and
  victory-hle, then versoes\vNNN-<name>-<sha8>\ under work_dir with the exe,
  pdb, D3D12\ and manifesto.json (base, notes, hashes, shader-translator hash,
  test results, build log). Prints the version id last.
  Paths come from harness.toml (see harness.example.toml).

.EXAMPLE
  .\Construir-Versao.ps1 -Fonte D:\victory\cand4 -Nome series-s-planes -Notas 'two-plane composition'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Fonte,       # VIctory source folder (with Cargo.toml)
    [Parameter(Mandatory)][string]$Nome,        # short label for the change, e.g. 'series-s-planes'
    [string]$Notas = '',                        # what this version changes (goes to the manifest and the scoreboard)
    [string]$Base = '',                         # base commit (default: the source's .victory-base file, if any)
    [switch]$SemTestes,                         # skip the tests
    [string]$Config = ''                        # harness.toml (default: next to this script)
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$cfg = Get-HarnessConfig $Config $PSScriptRoot
$raiz = $cfg['work_dir']
$agility = $cfg['agility_bin']
$toolchain = '+' + $cfg['rust_toolchain']
if (-not $agility -or -not (Test-Path -LiteralPath "$agility\D3D12Core.dll")) { throw "agility_bin in harness.toml must point to the folder with D3D12Core.dll" }
if (-not (Test-Path -LiteralPath "$Fonte\Cargo.toml")) { throw "No Cargo.toml in $Fonte" }
if ($Nome -notmatch '^[a-z0-9][a-z0-9-]{0,30}$') { throw 'Nome: lower-case letters, digits and hyphens (up to 31)' }
$versoes = Join-Path $raiz 'versoes'
if (-not (Test-Path -LiteralPath $versoes)) { New-Item -ItemType Directory -Path $versoes | Out-Null }

if ($cfg['vcvars']) {
    if (-not (Test-Path -LiteralPath $cfg['vcvars'])) { throw "vcvars not found: $($cfg['vcvars'])" }
    cmd /c "`"$($cfg['vcvars'])`" >nul 2>nul && set" | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process') }
    }
}
$log = Join-Path $versoes "build-$Nome-$(Get-Date -Format yyyyMMdd-HHmmss).log"
Push-Location $Fonte
try {
    $ErrorActionPreference = 'Continue'
    $inicio = Get-Date
    & cargo $toolchain rustc --offline --locked --release --features diagnostics -p victory --bin victory -- `
        -C 'link-arg=/EXPORT:D3D12SDKPath,DATA' -C 'link-arg=/EXPORT:D3D12SDKVersion,DATA' 2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $log | Select-String '^error' | ForEach-Object { Write-Host $_ }
    $build = $LASTEXITCODE
    $segundos = [int]((Get-Date) - $inicio).TotalSeconds
    if ($build -ne 0) { throw "Build failed (exit $build); log at $log" }
    $testes = [ordered]@{}
    if (-not $SemTestes) {
        foreach ($pkg in 'victory-gpu', 'victory-hle') {
            $saida = & cargo $toolchain test --offline --locked --release -p $pkg --lib -- --test-threads=1 2>&1 | ForEach-Object { "$_" }
            $saida | Add-Content -LiteralPath $log
            $r = $saida | Select-String 'test result: \w+\. (\d+) passed; (\d+) failed' | Select-Object -Last 1
            $falhas = @($saida | Select-String '^test (\S+) \.\.\. FAILED' | ForEach-Object { $_.Matches[0].Groups[1].Value })
            $testes[$pkg] = [ordered]@{
                passaram = $(if ($r) { [int]$r.Matches[0].Groups[1].Value } else { $null })
                falharam = $(if ($r) { [int]$r.Matches[0].Groups[2].Value } else { $null })
                falhas = $falhas
            }
        }
    }
} finally {
    $ErrorActionPreference = 'Stop'
    Pop-Location
}

$exe = Join-Path $Fonte 'target\release\victory.exe'
$sha = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
$n = @(Get-ChildItem -LiteralPath $versoes -Directory -Filter 'v*').Count + 1
$id = 'v{0:D3}-{1}-{2}' -f $n, $Nome, $sha.Substring(0, 8).ToLower()
$destino = Join-Path $versoes $id
New-Item -ItemType Directory -Path "$destino\D3D12" | Out-Null
Copy-Item -LiteralPath $exe, (Join-Path $Fonte 'target\release\victory.pdb') -Destination $destino
Copy-Item -LiteralPath "$agility\D3D12Core.dll", "$agility\d3d12SDKLayers.dll" -Destination "$destino\D3D12"

# Shader-translator hash: versions with the same hash translate identically (the cache is safe either way).
$shaderSrc = Join-Path $Fonte 'crates\victory-shader\src'
$partes = Get-ChildItem -LiteralPath $shaderSrc -Recurse -File | Sort-Object FullName | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName).Hash }
$tradutor = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::ASCII.GetBytes(($partes -join '')))).Replace('-', '').Substring(0, 16)
if (-not $Base -and (Test-Path -LiteralPath "$Fonte\.victory-base")) { $Base = (Get-Content -LiteralPath "$Fonte\.victory-base" -Raw).Trim() }

# Manifest keys are kept in Portuguese for compatibility with existing versions.
# It holds local paths (fonte, log_build): it stays in work_dir and is not published as-is.
$manifesto = [ordered]@{
    versao = $id; nome = $Nome; notas = $Notas; base = $(if ($Base) { $Base } else { 'unknown' })
    fonte = $Fonte; construida_em = (Get-Date).ToString('s'); build_segundos = $segundos
    exe_sha256 = $sha; pdb_sha256 = (Get-FileHash -LiteralPath "$destino\victory.pdb").Hash
    tradutor_shaders = $tradutor; testes = $testes; log_build = $log
}
$manifesto | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$destino\manifesto.json" -Encoding utf8
Write-Host "Version $id ready in $destino (build $segundos s)"
foreach ($k in $testes.Keys) { Write-Host ("  tests {0}: {1} passed, {2} failed {3}" -f $k, $testes[$k].passaram, $testes[$k].falharam, ($testes[$k].falhas -join ', ')) }
$id
