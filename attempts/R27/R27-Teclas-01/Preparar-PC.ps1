# Libera GPU, VRAM e RAM antes de jogar: fecha mineradores e apps que desenham pela GPU.
# Nao toca no Windows, no driver do mouse (LGHUB), no Claude/Codex nem no Explorer.
# O servico do Salad e parado so nesta sessao (volta no proximo boot).
$alvos = 'Kryptex', 'Salad', 'Salad.Bowl.Service', 'Salad.Bootstrapper', 'NiceHashMiner', 'excavator', 'xmrig',
    'firefox', 'brave', 'chrome', 'msedge', 'opera', 'Discord', 'DiscordSystemHelper', 'steam', 'steamwebhelper',
    'JellyfinMediaPlayer', 'WhatsApp', 'WhatsApp.Root', 'EpicGamesLauncher', 'Battle.net', 'RiotClientServices',
    'Spotify', 'NVIDIA Overlay', 'ChatGPT', 'Blitz', 'Go Live', 'flux', 'RobloxPlayerBeta'
$abertos = Get-Process | Where-Object { $alvos -contains $_.ProcessName }
Write-Output ("Fechando: " + ((($abertos | Group-Object ProcessName | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', ')))
$abertos | Where-Object { $_.MainWindowHandle -ne 0 } | ForEach-Object { [void]$_.CloseMainWindow() }
Start-Sleep -Seconds 3
foreach ($round in 1..3) {
    Get-Process | Where-Object { $alvos -contains $_.ProcessName } | Stop-Process -Force -ErrorAction SilentlyContinue
    if (Get-Service SaladBowl -ErrorAction SilentlyContinue) { Stop-Service SaladBowl -Force -NoWait -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
}
$resto = Get-Process | Where-Object { $alvos -contains $_.ProcessName } | ForEach-Object ProcessName | Sort-Object -Unique
Write-Output ("Ainda abertos: " + $(if ($resto) { $resto -join ', ' } else { 'nenhum' }))
$smi = 'C:\Windows\System32\nvidia-smi.exe'
if (Test-Path $smi) { Write-Output ("GPU: " + (& $smi --query-gpu=memory.used,memory.total,utilization.gpu --format=csv,noheader)) }
$os = Get-CimInstance Win32_OperatingSystem
Write-Output ("RAM livre: {0:N1} de {1:N1} GB" -f ($os.FreePhysicalMemory / 1MB), ($os.TotalVisibleMemorySize / 1MB))
