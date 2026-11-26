[CmdletBinding()]
param(
    # One or more run .stderr files (wildcards accepted). Only reads the logs.
    [Parameter(Mandatory)][string[]]$Log,
    # World samples: frame lines with more draws than this.
    [int]$MinDraws = 1000
)

function Get-Pct([double[]]$Sorted, [int]$P) {
    if (-not $Sorted.Count) { return $null }
    $Sorted[[math]::Min($Sorted.Count - 1, [math]::Ceiling($Sorted.Count * $P / 100) - 1)]
}

foreach ($path in (Resolve-Path $Log)) {
    $f = $path.Path
    $frame = Select-String -LiteralPath $f -Pattern '([\d.]+) fps, ([\d.]+) ms/frame \(([\d.]+) preparing.*?; ([\d.]+) on the GPU; ([\d.]+) copying back ([\d.]+) MB\), (\d+) draws/frame'
    $world = @($frame | Where-Object { [int]$_.Matches[0].Groups[7].Value -gt $MinDraws })
    $ms = @($world | ForEach-Object { [double]$_.Matches[0].Groups[2].Value } | Sort-Object)
    $back = @($world | ForEach-Object { [double]$_.Matches[0].Groups[5].Value } | Sort-Object)
    $gpu = @($world | ForEach-Object { [double]$_.Matches[0].Groups[4].Value } | Sort-Object)
    $vram = @(Select-String -LiteralPath $f -Pattern "card's own in use at most (\d+) MB, its budget at least (\d+) MB, the PC's shared in use at most (\d+) MB" |
        ForEach-Object { $g = $_.Matches[0].Groups; [pscustomobject]@{ Uso = [int]$g[1].Value; Orc = [int]$g[2].Value; Comp = [int]$g[3].Value } })
    $tiles = Select-String -LiteralPath $f -Pattern 'textures with levels on demand: (\d+) alive .*?, (\d+) MB of the card given to (\d+) levels .*?the pool''s heaps (\d+) MB' | Select-Object -Last 1
    $small = Select-String -LiteralPath $f -Pattern 'small levels on a full card since the start .*' | Select-Object -Last 1
    $q2 = @(Select-String -LiteralPath $f -Pattern 'the copy queues per frame \(VICTORY_QUEUE2=\d+\): fetches of what shaders wrote: ([\d.]+) jobs, ([\d.]+) MB')
    $worker = @(Select-String -LiteralPath $f -Pattern 'textures picked by index, their own thread \(VICTORY_HEAP_WORKER\), per frame: ([\d.]+) ms at work')
    $ds = @(Select-String -LiteralPath $f -Pattern 'dstorage per Submit .*')
    $refused = @(Select-String -LiteralPath $f -Pattern 'texture queue is refused').Count
    # Cause of the black cutscene (R13): the title's live textures, in MB, and the effective floor.
    $fills = @(Select-String -LiteralPath $f -Pattern 'host copies the title fills: (\d+) alive (\d+) MB' |
        ForEach-Object { [int]$_.Matches[0].Groups[2].Value } | Where-Object { $_ -gt 0 } | Sort-Object)
    $floorLine = Select-String -LiteralPath $f -Pattern 'floor_mb\S*?(\d+).*?made up to this floor' | Select-Object -First 1
    $black = @(Select-String -LiteralPath $f -Pattern 'a black frame after a frame').Count
    $removed = @(Select-String -LiteralPath $f -Pattern 'device (removed|lost|hung)|DEVICE_REMOVED').Count
    $settings = [IO.Path]::ChangeExtension($f, '.settings.txt')

    "=== $(Split-Path $f -Leaf)"
    if (Test-Path -LiteralPath $settings) {
        '  ' + ((Get-Content -LiteralPath $settings | Where-Object { $_ -match '^VICTORY_(QUEUE2|HEAP_WORKER|LEVELS_ON_DEMAND|TILES_SMALL_WHEN_FULL_MB|CARD_ROOM_FOR_TARGETS_MB|TEXTURE_AUTO_VRAM)=' }) -join ' ')
    }
    '  world: {0} samples; ms/frame median {1} p95 {2}; GPU wait for submission median {3}; copy-back median {4} ms' -f `
        $ms.Count, (Get-Pct $ms 50), (Get-Pct $ms 95), (Get-Pct $gpu 50), (Get-Pct $back 50)
    if ($vram.Count) {
        '  VRAM: own max {0} MB; budget min {1} MB; over budget in {2}/{3} lines; shared max {4} MB' -f `
            ($vram.Uso | Measure-Object -Maximum).Maximum, ($vram.Orc | Measure-Object -Minimum).Minimum,
            @($vram | Where-Object { $_.Uso -gt $_.Orc }).Count, $vram.Count, ($vram.Comp | Measure-Object -Maximum).Maximum
    }
    if ($tiles) {
        $g = $tiles.Matches[0].Groups
        '  mips on demand (last line): {0} live textures, tiles assigned {1} MB to {2} levels, pool heaps {3} MB' -f $g[1].Value, $g[2].Value, $g[3].Value, $g[4].Value
    }
    if ($small) { '  ' + $small.Matches[0].Value.Substring(0, [math]::Min(400, $small.Matches[0].Value.Length)) }
    '  COPY queue: {0} lines; last: {1}' -f $q2.Count, $(if ($q2.Count) { "$($q2[-1].Matches[0].Groups[1].Value) jobs, $($q2[-1].Matches[0].Groups[2].Value) MB per frame" } else { 'none (queue not used)' })
    '  texture worker: {0} lines; median at work {1} ms/frame' -f $worker.Count,
        (Get-Pct @($worker | ForEach-Object { [double]$_.Matches[0].Groups[1].Value } | Sort-Object) 50)
    '  DirectStorage: {0} 5 s windows; last: {1}' -f $ds.Count, $(if ($ds.Count) { $ds[-1].Matches[0].Value.Substring(0, [math]::Min(600, $ds[-1].Matches[0].Value.Length)) } else { '-' })
    '  title live textures: median {0} MB, max {1} MB; effective floor: {2}; black frames detected: {3}' -f `
        (Get-Pct $fills 50), (Get-Pct $fills 100), $(if ($floorLine) { "$($floorLine.Matches[0].Groups[1].Value) MB" } else { 'not logged (build without that line)' }), $black
    '  texture refusals: {0}; device removed/lost: {1}' -f $refused, $removed
}
