[CmdletBinding()]
param(
    [Parameter(Mandatory)][int]$GamePid,
    [Parameter(Mandatory)][long]$StartTicks,
    [Parameter(Mandatory)][string]$Log,
    [Parameter(Mandatory)][string]$Keys,
    [ValidateRange(0,60)][int]$TempoInicialS=8,
    [ValidateRange(1,60)][int]$IntervaloS=5,
    [ValidateRange(1,1800)][int]$LimiteS=720
)
$ErrorActionPreference='Stop'
$p=Get-Process -Id $GamePid -ErrorAction SilentlyContinue
if (!$p -or $p.StartTime.ToUniversalTime().Ticks -ne $StartTicks) { return }
$ansi='\x1b\[[0-?]*[ -/]*[@-~]'
# O log pode vir em ISO (2026-11-27T16:41:29Z) ou no formato local do runtime (27/11/2026 14:52:11, hora local).
$pattern='^(?<ts>\d{4}-\d{2}-\d{2}T\S+|\d{2}/\d{2}/\d{4} \d{2}:\d{2}:\d{2})\s+.*?\b\d+(?:\.\d+)? fps, \d+(?:\.\d+)? ms/frame.*?\b(?<draws>\d+) draws/frame'
$clock=[Diagnostics.Stopwatch]::StartNew()
$lastSent=[double]::NegativeInfinity
$lastSample=''
$seq=0
while ($clock.Elapsed.TotalSeconds -lt $LimiteS -and !$p.HasExited) {
    if ([IO.File]::Exists($Log)) {
        $samples=@(Get-Content -LiteralPath $Log -Tail 1000 -ErrorAction SilentlyContinue |
            ForEach-Object {[regex]::Match(($_ -replace $ansi,''),$pattern)} |
            Where-Object Success)
        if (@($samples | Where-Object {[int]$_.Groups['draws'].Value -ge 100}).Count) { return }
        if ($samples.Count) {
            $sample=$samples[-1]
            $stamp=$sample.Groups['ts'].Value
            $draws=[int]$sample.Groups['draws'].Value
            $at=[DateTimeOffset]::MinValue
            $now=[DateTimeOffset]::UtcNow
            $valid=[DateTimeOffset]::TryParseExact($stamp,'dd/MM/yyyy HH:mm:ss',[Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AssumeLocal,[ref]$at)
            if (!$valid) {
                $valid=[DateTimeOffset]::TryParse($stamp,[Globalization.CultureInfo]::InvariantCulture,
                    [Globalization.DateTimeStyles]::None,[ref]$at)
            }
            if ($valid -and $at.UtcDateTime.Ticks -ge $StartTicks -and
                ($now-$at).TotalSeconds -ge 0 -and ($now-$at).TotalSeconds -le 12 -and
                ($now.UtcDateTime.Ticks-$StartTicks)/[TimeSpan]::TicksPerSecond -ge $TempoInicialS -and
                $draws -gt 0 -and $draws -le 50 -and $stamp -ne $lastSample -and
                $clock.Elapsed.TotalSeconds-$lastSent -ge $IntervaloS) {
                $seq++
                [IO.File]::AppendAllText($Keys,"$seq Enter"+[Environment]::NewLine,[Text.Encoding]::ASCII)
                $lastSent=$clock.Elapsed.TotalSeconds
                $lastSample=$stamp
            }
        }
    }
    Start-Sleep -Milliseconds 800
}
