<#
.SYNOPSIS
  Everything in one call: build and version -> unattended run -> score -> FPS-drop check -> scoreboard.

.EXAMPLE
  .\Pipeline.ps1 -Fonte D:\victory\cand4 -Nome my-change -Notas 'what changed'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Fonte,       # VIctory source folder
    [Parameter(Mandatory)][string]$Nome,        # short label for the version
    [string]$Notas = '',                        # notes for the manifest and the scoreboard
    [string]$Base = '',                         # base commit
    [ValidateSet('rapido', 'series-x')][string]$Perfil = 'rapido',
    [hashtable]$Extra = @{},                    # extra VICTORY_* settings for the run
    [switch]$SemTestes,                         # skip the tests
    [string]$Config = ''                        # harness.toml (default: next to the scripts)
)

$ErrorActionPreference = 'Stop'
$id = & (Join-Path $PSScriptRoot 'Construir-Versao.ps1') -Fonte $Fonte -Nome $Nome -Notas $Notas -Base $Base -SemTestes:$SemTestes -Config $Config | Select-Object -Last 1
& (Join-Path $PSScriptRoot 'Rodar-Versao.ps1') -Versao $id -Perfil $Perfil -Extra $Extra -Config $Config
