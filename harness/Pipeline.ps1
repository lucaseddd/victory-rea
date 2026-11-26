<#
.SYNOPSIS
  Everything in one call: build and version -> unattended run -> score -> FPS-drop check -> scoreboard.

.EXAMPLE
  .\Pipeline.ps1 -Source D:\victory\cand4 -Name my-change -Notes 'what changed'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Source,      # VIctory source folder
    [Parameter(Mandatory)][string]$Name,        # short label for the version
    [string]$Notes = '',                        # notes for the manifest and the scoreboard
    [string]$Base = '',                         # base commit
    [ValidateSet('quick', 'series-x')][string]$Mode = 'quick',
    [hashtable]$Extra = @{},                    # extra VICTORY_* settings for the run
    [switch]$SkipTests,
    [string]$Config = ''                        # harness.toml (default: next to the scripts)
)

$ErrorActionPreference = 'Stop'
$id = & (Join-Path $PSScriptRoot 'Build-Version.ps1') -Source $Source -Name $Name -Notes $Notes -Base $Base -SkipTests:$SkipTests -Config $Config | Select-Object -Last 1
& (Join-Path $PSScriptRoot 'Run-Version.ps1') -Version $id -Mode $Mode -Extra $Extra -Config $Config
