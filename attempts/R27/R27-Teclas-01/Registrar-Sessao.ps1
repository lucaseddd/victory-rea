param(
    [Parameter(Mandatory)][int]$GamePid,
    [Parameter(Mandatory)][long]$StartTicks,
    [Parameter(Mandatory)][string]$Log,
    [Parameter(Mandatory)][string]$Settings,
    [Parameter(Mandatory)][string]$Exe,
    [string]$Historico = 'D:\codex\2026-11-22\new-chat-9\historico'
)
# Espera o jogo fechar e grava a nota da sessao (0-100) e a versao da build no historico.
# Nota: desempenho 60 (FPS mediano 40 + 10% piores 20, sobre 30 FPS), estabilidade 25
# (sem quedas abaixo de 3 FPS 15 + sem erro/crash 10), carregamento 15 (300 s ou menos ate o mundo = cheio).
$ErrorActionPreference = 'Continue'
# Ponto decimal sempre (o CSV usa virgula como separador).
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
$p = if ($GamePid -gt 0) { Get-Process -Id $GamePid -ErrorAction SilentlyContinue } else { $null }
if ($p -and $p.StartTime -and $p.StartTime.ToUniversalTime().Ticks -eq $StartTicks) { $p.WaitForExit() }
Start-Sleep -Seconds 2
New-Item -ItemType Directory -Force (Join-Path $Historico 'builds') | Out-Null

$inicio = [DateTime]::new($StartTicks, [DateTimeKind]::Utc).ToLocalTime()
$rx = '^(?<d>\d\d/\d\d/\d{4}) (?<t>\d\d:\d\d:\d\d) .*host: (?<fps>[\d.]+) fps, (?<ms>[\d.]+) ms/frame.* (?<dr>\d+) draws/frame'
$mundo = New-Object System.Collections.Generic.List[object]
$primeiro = $null; $vram = @(); $erros = 0; $removido = $false; $fechouJanela = $false
foreach ($linha in [IO.File]::ReadLines($Log)) {
    $m = [regex]::Match($linha, $rx)
    if ($m.Success) {
        if ([int]$m.Groups['dr'].Value -ge 1000) {
            $mundo.Add([pscustomobject]@{ fps = [double]$m.Groups['fps'].Value; ms = [double]$m.Groups['ms'].Value })
            if (-not $primeiro) { $primeiro = [DateTime]::ParseExact("$($m.Groups['d'].Value) $($m.Groups['t'].Value)", 'dd/MM/yyyy HH:mm:ss', $null) }
        }
        continue
    }
    if ($linha.Contains(' ERROR ')) { $erros++ }
    if ($linha.Contains('device removed') -or $linha.Contains('0x887A0005') -or $linha.Contains('0x887A0006')) { $removido = $true }
    if ($linha.Contains('window closed')) { $fechouJanela = $true }
    $v = [regex]::Match($linha, "the card's own: budget (?<b>\d+) MB, in use (?<u>\d+) MB")
    if ($v.Success -and [double]$v.Groups['b'].Value -gt 0) { $vram += 100 * [double]$v.Groups['u'].Value / [double]$v.Groups['b'].Value }
}
$fimLog = (Get-Item -LiteralPath $Log).LastWriteTime
$crash = @(Get-ChildItem (Join-Path (Split-Path $Log) 'data\7952987A\temp') -Filter '*.crash.log' -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $inicio -and $_.LastWriteTime -le $fimLog.AddMinutes(1) }).Count -gt 0

function Pct([double[]]$xs, [double]$q) { if (-not $xs.Count) { return $null }; $s = $xs | Sort-Object; $s[[int][math]::Floor(($s.Count - 1) * $q)] }
$fps = [double[]]@($mundo | ForEach-Object fps); $ms = [double[]]@($mundo | ForEach-Object ms)
$med = Pct $fps 0.5; $p10 = Pct $fps 0.1
$media = if ($fps.Count) { ($fps | Measure-Object -Average).Average } else { $null }
$msMed = Pct $ms 0.5
$abaixo3 = if ($fps.Count) { 100.0 * @($fps | Where-Object { $_ -lt 3 }).Count / $fps.Count } else { $null }
$ate3d = if ($primeiro) { [int]($primeiro - $inicio).TotalSeconds } else { $null }
$vramMed = if ($vram.Count) { [math]::Round(($vram | Measure-Object -Average).Average) } else { $null }
$duracao = [int]($fimLog - $inicio).TotalMinutes

$nota = 0.0
if ($fps.Count) {
    $nota += [math]::Min(1, $med / 30) * 40 + [math]::Min(1, $p10 / 30) * 20
    $nota += (1 - $abaixo3 / 100) * 15
    if ($ate3d) { $nota += [math]::Min(1, 300.0 / [math]::Max(1, $ate3d)) * 15 }
}
if (-not $removido -and -not $crash -and $erros -eq 0) { $nota += 10 }
$nota = [math]::Round($nota, 1)
$fim = if ($removido) { 'GPU removida (crash)' } elseif ($crash) { 'crash do jogo' } elseif ($fechouJanela) { 'janela fechada' } else { 'encerrado' }

# Versao da build: arquivada uma vez por hash.
$sha = (Get-FileHash -LiteralPath $Exe -Algorithm SHA256).Hash
$pasta = Join-Path $Historico "builds\$($sha.Substring(0, 12))"
if (-not (Test-Path $pasta)) {
    New-Item -ItemType Directory -Force $pasta | Out-Null
    Copy-Item -LiteralPath $Exe $pasta
    $pdb = [IO.Path]::ChangeExtension($Exe, '.pdb'); if (Test-Path $pdb) { Copy-Item -LiteralPath $pdb $pasta }
    $bj = Join-Path (Split-Path (Split-Path $Exe)) 'build.json'; if (Test-Path $bj) { Copy-Item -LiteralPath $bj $pasta }
}
Copy-Item -LiteralPath $Settings (Join-Path $pasta ("config-" + $inicio.ToString('yyyyMMdd-HHmmss') + '.txt')) -ErrorAction SilentlyContinue

$f = { param($x, $d = 1) if ($null -eq $x) { '' } else { [math]::Round([double]$x, $d) } }
$csv = Join-Path $Historico 'historico.csv'
if (-not (Test-Path $csv)) { 'inicio,build,nota,fim,duracao_min,ate_mundo_s,amostras_mundo,fps_media,fps_mediana,fps_p10,ms_mediana,pct_abaixo_3fps,vram_pct_orcamento,erros,log' | Set-Content $csv -Encoding utf8 }
(@($inicio.ToString('yyyy-MM-dd HH:mm:ss'), $sha.Substring(0, 12), $nota, $fim, $duracao, $ate3d, $fps.Count, (& $f $media), (& $f $med), (& $f $p10), (& $f $msMed 0), (& $f $abaixo3 0), $vramMed, $erros, $Log) -join ',') |
    Add-Content $csv -Encoding utf8
$md = Join-Path $Historico 'historico.md'
if (-not (Test-Path $md)) { "# Historico de sessoes`n`nNota 0-100: desempenho 60 (FPS mediano 40 + 10% piores 20, sobre 30 FPS), estabilidade 25 (sem quedas abaixo de 3 FPS 15 + sem erro/crash 10), carregamento 15 (ate 300 s ate o mundo).`n" | Set-Content $md -Encoding utf8 }
@"

## $($inicio.ToString('dd/MM/yyyy HH:mm')) - nota $nota / 100
- Build: ``$($sha.Substring(0, 12))`` (arquivada em ``builds\$($sha.Substring(0, 12))``)
- Fim: $fim apos $duracao min; ate o mundo: $(if ($ate3d) { "$ate3d s" } else { 'nao chegou' })
- FPS no mundo ($($fps.Count) amostras de 5 s): media $(& $f $media), mediana $(& $f $med), 10% piores $(& $f $p10), $(& $f $msMed 0) ms por quadro
- Quedas abaixo de 3 FPS: $(& $f $abaixo3 0)%; VRAM: $vramMed% do orcamento; erros no log: $erros
"@ | Add-Content $md -Encoding utf8
