# Frees the GPU, VRAM and RAM before playing: closes GPU miners and apps that draw through the GPU.
# Leaves Windows, the mouse driver (LGHUB), AI assistants and Explorer alone.
# The Salad service is stopped for this session only (it starts again at the next boot).
$targets = 'Kryptex', 'Salad', 'Salad.Bowl.Service', 'Salad.Bootstrapper', 'NiceHashMiner', 'excavator', 'xmrig',
    'firefox', 'brave', 'chrome', 'msedge', 'opera', 'Discord', 'DiscordSystemHelper', 'steam', 'steamwebhelper',
    'JellyfinMediaPlayer', 'WhatsApp', 'WhatsApp.Root', 'EpicGamesLauncher', 'Battle.net', 'RiotClientServices',
    'Spotify', 'NVIDIA Overlay', 'ChatGPT', 'Blitz', 'Go Live', 'flux', 'RobloxPlayerBeta'
$open = Get-Process | Where-Object { $targets -contains $_.ProcessName }
Write-Output ("Closing: " + ((($open | Group-Object ProcessName | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', ')))
$open | Where-Object { $_.MainWindowHandle -ne 0 } | ForEach-Object { [void]$_.CloseMainWindow() }
Start-Sleep -Seconds 3
foreach ($round in 1..3) {
    Get-Process | Where-Object { $targets -contains $_.ProcessName } | Stop-Process -Force -ErrorAction SilentlyContinue
    if (Get-Service SaladBowl -ErrorAction SilentlyContinue) { Stop-Service SaladBowl -Force -NoWait -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
}
$left = Get-Process | Where-Object { $targets -contains $_.ProcessName } | ForEach-Object ProcessName | Sort-Object -Unique
Write-Output ("Still open: " + $(if ($left) { $left -join ', ' } else { 'none' }))
$smi = 'C:\Windows\System32\nvidia-smi.exe'
if (Test-Path $smi) { Write-Output ("GPU: " + (& $smi --query-gpu=memory.used,memory.total,utilization.gpu --format=csv,noheader)) }
$os = Get-CimInstance Win32_OperatingSystem
Write-Output ("Free RAM: {0:N1} of {1:N1} GB" -f ($os.FreePhysicalMemory / 1MB), ($os.TotalVisibleMemorySize / 1MB))
