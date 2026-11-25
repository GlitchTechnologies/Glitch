#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Откройте новый PowerShell через Пуск обычным запуском. Повышенные права могут мешать захвату окна игры.'
}
$version = '44.7.0'
$cpu = $env:PROCESSOR_ARCHITEW6432
if (-not $cpu) { $cpu = $env:PROCESSOR_ARCHITECTURE }
$architecture = switch ($cpu) {
    'AMD64' { 'x64' }
    'ARM64' { 'arm64' }
    default { throw 'This benchmark supports 64-bit Windows (x64 / ARM64).' }
}
$launcher = Join-Path $PSScriptRoot 'benchmark_screen_capture.cjs'
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
    throw 'Put benchmark_screen_capture.cjs next to this script.'
}

$root = Join-Path $env:TEMP ('glitch-gpu-benchmark-' + [guid]::NewGuid().ToString('N'))
$runtime = Join-Path $root 'electron'
$asset = "electron-v$version-win32-$architecture.zip"
$zip = Join-Path $root $asset
$checksumFile = Join-Path $root 'SHASUMS256.txt'
$release = "https://github.com/electron/electron/releases/download/v$version"
$report = Join-Path $PSScriptRoot ('glitch-capture-report-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')

try {
    [void](New-Item -ItemType Directory -Path $root)
    Write-Host "Загрузка Electron $version…"
    Invoke-WebRequest -UseBasicParsing -Uri "$release/SHASUMS256.txt" -OutFile $checksumFile
    $checksums = Get-Content -LiteralPath $checksumFile -Raw -Encoding UTF8
    $pattern = '(?im)^([0-9a-f]{64})[ \t]+\*?' + [regex]::Escape($asset) + '[ \t]*\r?$'
    if ($checksums -notmatch $pattern) { throw "Checksum not found for $asset." }
    $hash = $Matches[1]
    Invoke-WebRequest -UseBasicParsing -Uri "$release/$asset" -OutFile $zip
    if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $hash) {
        throw "Electron ZIP checksum mismatch."
    }
    Expand-Archive -LiteralPath $zip -DestinationPath $runtime

    $env:GLITCH_CAPTURE_BENCHMARK = $root
    $runs = foreach ($mode in @('baseline', 'texture')) {
        $env:GLITCH_CAPTURE_MODE = $mode
        Write-Host "Замер: $mode"
        $proc = Start-Process -FilePath (Join-Path $runtime 'electron.exe') `
            -ArgumentList ('"{0}"' -f $launcher) -PassThru -Wait
        $result = Join-Path $root "$mode.json"
        if ($proc.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $result -PathType Leaf)) {
            throw "The $mode measurement did not finish. Close the window only after it closes automatically."
        }
        Get-Content -LiteralPath $result -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    ConvertTo-Json -InputObject @($runs) -Depth 8 | Set-Content -LiteralPath $report -Encoding UTF8
    Write-Host "Пришлите отчёт: $report"
} finally {
    Remove-Item Env:GLITCH_CAPTURE_BENCHMARK, Env:GLITCH_CAPTURE_MODE -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
