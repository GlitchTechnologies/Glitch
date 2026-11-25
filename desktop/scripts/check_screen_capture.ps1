#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$AppPath
)

$ErrorActionPreference = 'Stop'
$sampleSeconds = 15
$countdownSeconds = 5

function Get-Percentile95 {
    param([System.Collections.Generic.List[int]]$Values)

    if ($Values.Count -eq 0) { return '—' }
    $sorted = @($Values | Sort-Object)
    $index = [int][Math]::Ceiling($sorted.Count * 0.95) - 1
    return $sorted[$index]
}

function Get-CaptureSample {
    param(
        [string]$LogPath,
        [datetime]$From,
        [datetime]$Until
    )

    if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
        throw "Glitch не создал журнал $LogPath. Проверьте, что предыдущая копия программы была полностью закрыта."
    }

    $culture = [Globalization.CultureInfo]::InvariantCulture
    $startStamp = $From.ToString('MMdd/HHmmss.fff', $culture)
    $endStamp = $Until.ToString('MMdd/HHmmss.fff', $culture)
    $yearChanged = [string]::CompareOrdinal($startStamp, $endStamp) -gt 0
    $results = 0
    $unchanged = 0
    $errors = 0
    $durations = [System.Collections.Generic.List[int]]::new()
    $periods = [System.Collections.Generic.List[int]]::new()

    # Chromium продолжает писать в журнал, пока идёт демонстрация.
    $stream = [IO.File]::Open($LogPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $reader = [IO.StreamReader]::new($stream)
    $requestedFps = '—'
    try {
        while ($null -ne ($line = $reader.ReadLine())) {
            if ($line -notmatch ':(?<stamp>\d{4}/\d{6}\.\d{3}):VERBOSE[12]:.*desktop_capture_device\.cc:\d+\]\s*(?<message>.*)$') {
                continue
            }
            $stamp = $Matches.stamp
            $message = $Matches.message
            $afterStart = [string]::CompareOrdinal($stamp, $startStamp) -ge 0
            $beforeEnd = [string]::CompareOrdinal($stamp, $endStamp) -lt 0
            $inSample = ($afterStart -and $beforeEnd) -or ($yearChanged -and ($afterStart -or $beforeEnd))
            if ($message -match 'requested_frame_rate=([0-9.]+)') {
                if ($inSample -and $results -gt 0) {
                    throw 'Демонстрация перезапустилась во время замера. Повторите проверку с одним источником.'
                }
                $requestedFps = $Matches[1]
            }
            if (-not $inSample) {
                # Журнал идёт по времени. Последующие попытки в замер не входят.
                if ($results -gt 0) { break }
                continue
            }

            if ($message -match '^OnCaptureResult\s+\[(SUCCESS|ERROR)\]') {
                $results++
                if ($message -match '\[0Hz\]') {
                    $unchanged++
                } elseif ($message -match '\[ERROR\]') {
                    $errors++
                }
            } elseif ($message -match 'last_capture_duration=(\d+)') {
                $durations.Add([int]$Matches[1])
            } elseif ($message -match '^capture_period=(\d+)') {
                $periods.Add([int]$Matches[1])
            }
        }
    } finally {
        $reader.Dispose()
    }

    if ($results -eq 0) {
        throw "В интервале замера нет событий захвата. Повторите запуск сценария и держите демонстрацию включённой до сигнала. Журнал: $LogPath"
    }

    $seconds = ($Until - $From).TotalSeconds
    return [pscustomobject]@{
        RequestedFps = $requestedFps
        AttemptsPerSecond = [Math]::Round($results / $seconds, 1)
        FramesPerSecond = [Math]::Round(($results - $unchanged - $errors) / $seconds, 1)
        Unchanged = $unchanged
        Errors = $errors
        Results = $results
        Duration95 = Get-Percentile95 -Values $durations
        Period95 = Get-Percentile95 -Values $periods
    }
}

function Start-GlitchForSample {
    param(
        [string]$LogPath,
        [switch]$Texture
    )

    while (Get-Process -Name $processName -ErrorAction SilentlyContinue) {
        [void](Read-Host 'Полностью закройте Glitch через «Выйти» у значка рядом с часами и нажмите Enter')
    }

    $launchArgs = @(
        '--enable-logging=file'
        ('--log-file="{0}"' -f $LogPath)
        '--vmodule=desktop_capture_device=2'
    )
    if ($Texture) {
        $launchArgs += '--enable-features=WebRtcAllowWgcUsingTexture'
    }
    Start-Process -FilePath $AppPath -WorkingDirectory (Split-Path -Parent $AppPath) -ArgumentList $launchArgs
}

function Measure-Run {
    param(
        [string]$Name,
        [string]$LogPath
    )

    Write-Host ""
    Write-Host $Name
    [void](Read-Host 'Начните показ, затем нажмите Enter здесь и сразу вернитесь в игру')
    Write-Host "Через $countdownSeconds секунд начнётся замер. Двигайтесь в игре до сигнала"
    Start-Sleep -Seconds $countdownSeconds
    $start = Get-Date
    Start-Sleep -Seconds $sampleSeconds
    $end = $start.AddSeconds($sampleSeconds)
    try { [Console]::Beep(880, 300) } catch {}
    Write-Host 'Замер завершён. Можно остановить показ'

    $sample = Get-CaptureSample -LogPath $LogPath -From $start -Until $end
    $format = '{0} | Запрошено FPS: {1} | Попыток/с: {2} | Кадров/с после 0Hz: {3} | Неизменившихся: {4}/{5} | Ошибок: {6} | Захват p95, мс: {7} | Интервал p95, мс: {8}'
    $line = $format -f $Name, $sample.RequestedFps, $sample.AttemptsPerSecond, $sample.FramesPerSecond,
        $sample.Unchanged, $sample.Results, $sample.Errors, $sample.Duration95, $sample.Period95
    Write-Host $line
    return $line
}

if (-not $AppPath) {
    $AppPath = Get-Process -Name Glitch -ErrorAction SilentlyContinue |
        Where-Object { $_.Path } | Select-Object -First 1 -ExpandProperty Path
}
if (-not $AppPath) {
    $AppPath = Join-Path $env:LOCALAPPDATA 'Programs\Glitch\Glitch.exe'
}
if (-not (Test-Path -LiteralPath $AppPath -PathType Leaf)) {
    throw 'Glitch.exe не найден. Запустите установленный Glitch или укажите его путь параметром -AppPath.'
}
$AppPath = (Resolve-Path -LiteralPath $AppPath).Path
$processName = [IO.Path]::GetFileNameWithoutExtension($AppPath)

$folder = Join-Path $env:TEMP ('glitch-capture-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
[void](New-Item -ItemType Directory -Path $folder)
$baselineLog = Join-Path $folder 'baseline.log'
$textureLog = Join-Path $folder 'texture.log'
$reportPath = Join-Path $folder 'report.txt'

Write-Host 'Проверка FPS демонстрации Glitch'
Write-Host 'Используйте одну игру, один источник показа и одинаковое движение во всех трёх замерах.'
Write-Host 'Попросите зрителя держать стрим открытым крупным планом.'
$source = Read-Host 'Что показываете (Приложение или Экран)'
$quality = Read-Host 'Разрешение первого замера (Enter — 1080p)'
if (-not $quality) { $quality = '1080p' }
$report = @('Glitch — проверка захвата экрана', "Источник: $source", "Замер: $sampleSeconds с")
$report | Set-Content -LiteralPath $reportPath -Encoding UTF8

Start-GlitchForSample -LogPath $baselineLog
Measure-Run -Name "Обычный запуск, $quality / 60 FPS" -LogPath $baselineLog |
    Add-Content -LiteralPath $reportPath -Encoding UTF8
Measure-Run -Name 'Обычный запуск, 720p / 60 FPS' -LogPath $baselineLog |
    Add-Content -LiteralPath $reportPath -Encoding UTF8
Start-GlitchForSample -LogPath $textureLog -Texture
Measure-Run -Name "С флагом текстур видеокарты, $quality / 60 FPS" -LogPath $textureLog |
    Add-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host ""
Write-Host "Пришлите файл $reportPath. Журналы остаются в той же папке."
Write-Host 'Чтобы вернуться к обычному режиму, выйдите из Glitch и запустите его из ярлыка.'
