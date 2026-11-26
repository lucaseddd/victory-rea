<#
.SYNOPSIS
  Disk pre-warm: reads the ranges the game read in earlier runs, in file order, so Windows' file cache is warm.

.DESCRIPTION
  Reads the read lists (VICTORY_DSTORAGE_TRACE, one per run) of previous runs, merges ranges
  closer than -JoinKB into one read, and reads everything in file order into the file cache
  before the game opens. On a hard disk this replaces thousands of scattered small reads with
  sequential ones. Read-only: the game package is never changed.
  Measured on the author's machine: 926 MB at 53 MB/s, against 2.5-6 MB/s for the game's own
  scattered reads; with the cache already warm, 0.3 s.

.EXAMPLE
  .\Pre-Warm.ps1 -Trace 'D:\victory\pipeline\reads\run1.tsv' -GameDir 'D:\dump\title'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$Trace,        # read lists (VICTORY_DSTORAGE_TRACE) from earlier runs
    [Parameter(Mandatory)][string]$GameDir,        # the game's package folder (read only)
    [int]$JoinKB = 2048,                           # ranges less than this far apart become one read
    [int]$MaxGB = 10                               # cap on how much is read (the test machine has 32 GB of RAM)
)

$ErrorActionPreference = 'Stop'
$started = Get-Date
$byFile = @{}
foreach ($t in $Trace) {
    if (-not (Test-Path -LiteralPath $t)) { continue }
    foreach ($line in [IO.File]::ReadLines($t)) {
        $c = $line.Split("`t")
        if ($c.Count -ne 3 -or $c[0] -notmatch '^[A-Za-z]:\\(.+)$') { continue }
        $real = Join-Path $GameDir $matches[1]
        if (-not $byFile.ContainsKey($real)) { $byFile[$real] = New-Object System.Collections.Generic.List[object] }
        $byFile[$real].Add([long[]]@([long]$c[1], [long]$c[2]))
    }
}
if (-not $byFile.Count) {
    Write-Host 'Pre-warm: no read lists yet (the first run writes one).'
    return [pscustomobject]@{ mb = 0; seconds = 0 }
}

$join = [long]$JoinKB * 1024
$plans = foreach ($file in $byFile.Keys) {
    $ranges = $byFile[$file] | Sort-Object { $_[0] }
    $start = -1L; $end = -1L
    foreach ($r in $ranges) {
        $a = $r[0]; $b = $r[0] + $r[1]
        if ($start -ge 0 -and $a -le $end + $join) { if ($b -gt $end) { $end = $b } }
        else { if ($start -ge 0) { [pscustomobject]@{ file = $file; start = $start; end = $end } }; $start = $a; $end = $b }
    }
    if ($start -ge 0) { [pscustomobject]@{ file = $file; start = $start; end = $end } }
}
$cap = [long]$MaxGB * 1GB
$buffer = New-Object byte[] (4MB)
$readBytes = 0L
foreach ($group in ($plans | Group-Object file)) {
    if ($readBytes -ge $cap) { break }
    $fs = New-Object IO.FileStream($group.Name, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read, 1MB, [IO.FileOptions]::SequentialScan)
    try {
        foreach ($p in ($group.Group | Sort-Object start)) {
            $fs.Position = $p.start
            $left = $p.end - $p.start
            while ($left -gt 0 -and $readBytes -lt $cap) {
                $n = $fs.Read($buffer, 0, [int][math]::Min($buffer.Length, $left))
                if ($n -le 0) { break }
                $left -= $n; $readBytes += $n
            }
        }
    } finally { $fs.Dispose() }
}
$seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
$mb = [math]::Round($readBytes / 1MB, 1)
Write-Host ("Pre-warm: {0} MB in {1} ranges of {2} files, {3} s ({4} MB/s)" -f $mb, @($plans).Count, $byFile.Count, $seconds, $(if ($seconds) { [math]::Round($mb / $seconds, 1) } else { 0 }))
[pscustomobject]@{ mb = $mb; seconds = $seconds; ranges = @($plans).Count }
