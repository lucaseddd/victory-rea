<#
.SYNOPSIS
  Recusa conteudo proibido no repositorio (politica de dados do VIctory).

.DESCRIPTION
  Modo arvore (padrao): verifica todos os arquivos sob -Path, exceto .git.
    - extensao fora da lista de permissao, ou na lista de proibidas
      (.exe, .dll, .pdb, .rpf, imagens, videos, *.stderr, ...);
    - arquivo maior que -MaxBytes (512 KiB);
    - conteudo binario (byte NUL, assinatura conhecida, UTF-8 invalido);
    - sequencias longas de hex (> 64) ou base64 (>= 100);
    - dump de bytes em hex e listagens de disassembly;
    - e-mails e caminhos de perfil de usuario do Windows.
  Modo historico (-GitRange): verifica tamanho e extensao de todo blob
  introduzido no intervalo de commits (usado no CI).

  Compativel com Windows PowerShell 5.1 e PowerShell 7 (Windows e Linux).
  Este arquivo e so ASCII de proposito (o 5.1 le .ps1 sem BOM como ANSI).

.EXAMPLE
  pwsh -File scripts/Test-RepoContent.ps1
.EXAMPLE
  pwsh -File scripts/Test-RepoContent.ps1 -GitRange origin/main..HEAD
#>
[CmdletBinding()]
param(
    [string]$Path,
    [int]$MaxBytes = 524288,
    [string]$GitRange
)

$ErrorActionPreference = 'Stop'
if (-not $Path) { $Path = Split-Path -Parent $PSScriptRoot }
$root = (Resolve-Path -LiteralPath $Path).ProviderPath.TrimEnd('\', '/')

$allowedExt   = @('.md', '.yml', '.yaml', '.json', '.csv', '.ps1', '.py', '.toml')
$allowedNames = @('.gitignore', '.gitattributes', 'LICENSE')
$deniedExt = @(
    '.exe', '.dll', '.pdb', '.lib', '.obj', '.sys', '.so', '.dylib',
    '.rpf', '.xex', '.xvd', '.msixvc', '.bin', '.pak', '.dds', '.bcpack',
    '.stderr', '.stdout', '.log', '.etl', '.dmp', '.rdc',
    '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.tga', '.webp', '.tif', '.tiff', '.ico', '.exr', '.hdr',
    '.mp4', '.mkv', '.mov', '.avi', '.webm', '.wmv', '.flv', '.wav', '.mp3', '.ogg', '.flac',
    '.zip', '.7z', '.rar', '.gz', '.tar', '.cab'
)

# Assinaturas binarias (inicio do arquivo).
$magics = @(
    @{ Name = 'PE/MZ';  Bytes = [byte[]](0x4D, 0x5A) },
    @{ Name = 'PNG';    Bytes = [byte[]](0x89, 0x50, 0x4E, 0x47) },
    @{ Name = 'JPEG';   Bytes = [byte[]](0xFF, 0xD8, 0xFF) },
    @{ Name = 'GIF';    Bytes = [byte[]](0x47, 0x49, 0x46, 0x38) },
    @{ Name = 'DDS';    Bytes = [byte[]](0x44, 0x44, 0x53, 0x20) },
    @{ Name = 'RIFF';   Bytes = [byte[]](0x52, 0x49, 0x46, 0x46) },
    @{ Name = 'ZIP';    Bytes = [byte[]](0x50, 0x4B, 0x03, 0x04) },
    @{ Name = '7z';     Bytes = [byte[]](0x37, 0x7A, 0xBC, 0xAF) },
    @{ Name = 'MKV';    Bytes = [byte[]](0x1A, 0x45, 0xDF, 0xA3) },
    @{ Name = 'MSF/PDB'; Bytes = [byte[]](0x4D, 0x69, 0x63, 0x72, 0x6F, 0x73, 0x6F, 0x66, 0x74, 0x20, 0x43, 0x2F, 0x43) }
)

$rxHexRun   = [regex]'[0-9A-Fa-f]{65,}'
$rxB64Run   = [regex]'[A-Za-z0-9+/]{100,}={0,2}'
$rxHexDump  = [regex]'(?:\b[0-9A-Fa-f]{2}[ \t]){16,}'
$rxEmail    = [regex]'[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}'
$rxUserPath = [regex]'(?i)\b[A-Z]:[\\/]+Users[\\/]+[^\\/\s`]+'
$mn = '(?:mov|movzx|movsx|lea|call|jmp|j[a-z]{1,3}|cmp|test|push|pop|add|sub|xor|and|or|shl|shr|sar|imul|ret|nop|lock|xchg|cmov[a-z]{1,3}|set[a-z]{1,3}|inc|dec)'
# Linha de listagem: endereco + bytes + mnemonico (dumpbin, Ghidra, objdump).
$rxAsmListing = [regex]('(?im)^\s*(?:0x)?[0-9A-Fa-f]{6,16}:?\s+(?:[0-9A-Fa-f]{2}\s){1,15}\s*' + $mn + '\b')
# Linha de instrucao sozinha com operando de registrador.
$rxAsmBare = [regex]('(?im)^\s*(?:[0-9A-Fa-f]{6,16}:?\s+)?' + $mn + '\s+(?:byte|word|dword|qword|[re]?[a-d]x|[re]?[sd]i|[re]?[sb]p|r\d{1,2}[dwb]?|[xy]mm\d+|\[)')

$failures = New-Object System.Collections.Generic.List[string]
function Add-Failure([string]$rel, [string]$why) { $failures.Add(('{0}: {1}' -f $rel, $why)) }

function Test-NameRule([string]$rel) {
    $name = [System.IO.Path]::GetFileName($rel)
    $ext  = [System.IO.Path]::GetExtension($rel).ToLowerInvariant()
    if ($allowedNames -contains $name) { return }
    if ($name -eq 'harness.toml' -or $name -eq 'victory.toml') { Add-Failure $rel 'configuracao local com caminhos da maquina (use *.example.toml)'; return }
    if ($rel -match '(?i)\.(stderr|stdout)(\.|$)') { Add-Failure $rel 'log bruto (*.stderr/*.stdout)'; return }
    if ($deniedExt -contains $ext) { Add-Failure $rel ('extensao proibida ' + $ext); return }
    if (-not ($allowedExt -contains $ext)) { Add-Failure $rel ('extensao fora da lista de permissao: "' + $ext + '"') }
}

if ($GitRange) {
    $lines = & git rev-list --objects $GitRange
    if ($LASTEXITCODE -ne 0) { throw "git rev-list falhou para '$GitRange'" }
    $batch = $lines | & git cat-file '--batch-check=%(objecttype) %(objectsize) %(rest)'
    if ($LASTEXITCODE -ne 0) { throw 'git cat-file falhou' }
    $count = 0
    foreach ($l in $batch) {
        $parts = $l -split ' ', 3
        if ($parts.Count -lt 3 -or $parts[0] -ne 'blob' -or -not $parts[2]) { continue }
        $count++
        $size = [int64]$parts[1]; $rel = $parts[2]
        if ($size -gt $MaxBytes) { Add-Failure $rel ('blob de {0} bytes no historico (limite {1})' -f $size, $MaxBytes) }
        Test-NameRule $rel
    }
    if ($failures.Count -gt 0) {
        Write-Host ('FALHOU: {0} problema(s) nos commits {1}' -f $failures.Count, $GitRange)
        $failures | Sort-Object -Unique | ForEach-Object { Write-Host ('  - ' + $_) }
        exit 1
    }
    Write-Host ('OK: {0} blob(s) verificados em {1}' -f $count, $GitRange)
    exit 0
}

$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$files = Get-ChildItem -LiteralPath $root -Recurse -File -Force |
    Where-Object { $_.FullName.Substring($root.Length) -notmatch '[\\/]\.git([\\/]|$)' }

foreach ($f in $files) {
    $rel = $f.FullName.Substring($root.Length).TrimStart('\', '/') -replace '\\', '/'
    Test-NameRule $rel

    if ($f.Length -gt $MaxBytes) { Add-Failure $rel ('{0} bytes (limite {1})' -f $f.Length, $MaxBytes); continue }
    if ($f.Length -eq 0) { continue }

    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    foreach ($m in $magics) {
        $sig = $m.Bytes
        if ($bytes.Length -ge $sig.Length) {
            $same = $true
            for ($i = 0; $i -lt $sig.Length; $i++) { if ($bytes[$i] -ne $sig[$i]) { $same = $false; break } }
            if ($same) { Add-Failure $rel ('assinatura binaria ' + $m.Name) }
        }
    }
    if ([System.Array]::IndexOf($bytes, [byte]0) -ge 0) { Add-Failure $rel 'conteudo binario (byte NUL)'; continue }

    try { $text = $utf8Strict.GetString($bytes) }
    catch { Add-Failure $rel 'nao e UTF-8 valido'; continue }

    if ($rxHexRun.IsMatch($text))  { Add-Failure $rel 'sequencia hex com mais de 64 digitos' }
    if ($rxB64Run.IsMatch($text))  { Add-Failure $rel 'sequencia base64 longa (>= 100)' }
    if ($rxHexDump.IsMatch($text)) { Add-Failure $rel 'dump de bytes em hex (16+ bytes seguidos)' }
    $nList = $rxAsmListing.Matches($text).Count
    if ($nList -ge 3) { Add-Failure $rel ('listagem de disassembly ({0} linhas endereco+bytes+instrucao)' -f $nList) }
    $nBare = $rxAsmBare.Matches($text).Count
    if ($nBare -ge 6) { Add-Failure $rel ('bloco de instrucoes assembly ({0} linhas)' -f $nBare) }
    if ($rxEmail.IsMatch($text))    { Add-Failure $rel ('e-mail: ' + $rxEmail.Match($text).Value.Substring(0, 1) + '***') }
    if ($rxUserPath.IsMatch($text)) { Add-Failure $rel 'caminho de perfil de usuario do Windows' }
}

if ($failures.Count -gt 0) {
    Write-Host ('FALHOU: {0} problema(s) em {1}' -f $failures.Count, $root)
    $failures | ForEach-Object { Write-Host ('  - ' + $_) }
    exit 1
}
Write-Host ('OK: {0} arquivo(s) verificados em {1}' -f $files.Count, $root)
exit 0
