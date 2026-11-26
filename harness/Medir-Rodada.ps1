[CmdletBinding()]
param(
    # Um ou mais .stderr de rodadas (aceita curinga). So le os logs.
    [Parameter(Mandatory)][string[]]$Log,
    # Amostras de mundo: linhas de quadro com mais draws que isto.
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
    # A causa da cutscene preta (R13): texturas do titulo vivas, em MB, e o piso efetivo.
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
    '  mundo: {0} amostras; ms/quadro mediana {1} p95 {2}; espera da submissao pela GPU mediana {3}; copy-back mediana {4} ms' -f `
        $ms.Count, (Get-Pct $ms 50), (Get-Pct $ms 95), (Get-Pct $gpu 50), (Get-Pct $back 50)
    if ($vram.Count) {
        '  VRAM: propria max {0} MB; orcamento min {1} MB; acima do orcamento em {2}/{3} linhas; compartilhada max {4} MB' -f `
            ($vram.Uso | Measure-Object -Maximum).Maximum, ($vram.Orc | Measure-Object -Minimum).Minimum,
            @($vram | Where-Object { $_.Uso -gt $_.Orc }).Count, $vram.Count, ($vram.Comp | Measure-Object -Maximum).Maximum
    }
    if ($tiles) {
        $g = $tiles.Matches[0].Groups
        '  mips sob demanda (ultima linha): {0} texturas vivas, tiles atribuidos {1} MB a {2} niveis, heaps do pool {3} MB' -f $g[1].Value, $g[2].Value, $g[3].Value, $g[4].Value
    }
    if ($small) { '  ' + $small.Matches[0].Value.Substring(0, [math]::Min(400, $small.Matches[0].Value.Length)) }
    '  fila COPY: {0} linhas; ultima: {1}' -f $q2.Count, $(if ($q2.Count) { "$($q2[-1].Matches[0].Groups[1].Value) jobs, $($q2[-1].Matches[0].Groups[2].Value) MB por quadro" } else { 'nenhuma (fila nao usada)' })
    '  worker de texturas: {0} linhas; mediana em trabalho {1} ms/quadro' -f $worker.Count,
        (Get-Pct @($worker | ForEach-Object { [double]$_.Matches[0].Groups[1].Value } | Sort-Object) 50)
    '  DirectStorage: {0} janelas de 5 s; ultima: {1}' -f $ds.Count, $(if ($ds.Count) { $ds[-1].Matches[0].Value.Substring(0, [math]::Min(600, $ds[-1].Matches[0].Value.Length)) } else { '-' })
    '  texturas do titulo vivas: mediana {0} MB, max {1} MB; piso efetivo: {2}; quadros pretos detectados: {3}' -f `
        (Get-Pct $fills 50), (Get-Pct $fills 100), $(if ($floorLine) { "$($floorLine.Matches[0].Groups[1].Value) MB" } else { 'nao registrado (build sem a linha)' }), $black
    '  recusas de textura: {0}; device removed/lost: {1}' -f $refused, $removed
}
