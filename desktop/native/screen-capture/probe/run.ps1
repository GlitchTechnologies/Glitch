param(
    [ValidateSet('all', 'both', 'baseline', 'wgc', 'dxgi', 'dxgi-preview', 'dxgi-compare', 'dxgi-send-only', 'dxgi-send-compare', 'dxgi-profile', 'dxgi-timing', 'dxgi-gpu-suite', 'dxgi-nv12', 'dxgi-nv12-compare', 'dxgi-buffers')]
    [string] $Mode = 'all'
)

$ErrorActionPreference = 'Stop'
$desktop = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$engine = Join-Path $desktop 'node_modules\.bin\electron.cmd'
$main = Join-Path $PSScriptRoot 'main.cjs'
if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) {
    throw 'Electron executable wrapper not found. Install desktop dependencies first.'
}

function Invoke-CaptureProbe {
    param([string] $CaptureMode, [string] $DisabledFeatures, [string[]] $ProbeArgs)
    & $engine $main "--capture-probe-mode=$CaptureMode" "--disable-features=$DisabledFeatures" @ProbeArgs
    if ($LASTEXITCODE -ne 0) { throw "Capture probe failed ($CaptureMode, exit $LASTEXITCODE)." }
}

if ($Mode -eq 'dxgi-gpu-suite') {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Open PowerShell as administrator to record the Windows GPU queue.'
    }
    $wpr = (Get-Command wpr.exe -ErrorAction Stop).Source
    $profile = Join-Path $PSScriptRoot 'gpu-queue.wprp'
    if (-not (Test-Path -LiteralPath $profile -PathType Leaf)) { throw "Missing WPR profile: $profile" }
}

if ($Mode -ne 'baseline') {
    & (Join-Path $PSScriptRoot '..\build.ps1') -Probe
}

if ($Mode -eq 'dxgi-gpu-suite') {
    $instance = 'GlitchGpu-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $traceRoot = Join-Path $desktop 'build\capture-probe-reports'
    $output = Join-Path $traceRoot $instance
    New-Item -ItemType Directory -Path $output -Force | Out-Null
    $failed = [System.Collections.Generic.List[string]]::new()
    $disabled = 'WebRtcAllowWgcUsingTexture,BreakoutBoxEagerConversion'
    $baseArgs = @('--capture-probe-timing')

    Write-Host "1/3: GPU queue trace, priority 0. Start the sample in the probe."
    try {
        & $wpr -start GPU -start "${profile}!GlitchGpuQueue" -filemode -recordtempto $output -instancename $instance
        if ($LASTEXITCODE -ne 0) { throw "WPR did not start (exit $LASTEXITCODE)." }
        try {
            $reportPath = Join-Path $output 'gpu-queue.json'
            Invoke-CaptureProbe -CaptureMode dxgi-preview -DisabledFeatures $disabled -ProbeArgs (
                $baseArgs + @('--capture-probe-priority=0', '--capture-probe-queue', "--capture-probe-report=$reportPath")
            )
        } finally {
            $tracePath = Join-Path $output 'gpu-queue.etl'
            try {
                & $wpr -status -instancename $instance | Out-File -LiteralPath (Join-Path $output 'wpr-status.txt') -Encoding UTF8
            } finally {
                & $wpr -stop $tracePath -instancename $instance
                $stopCode = $LASTEXITCODE
                if ($stopCode -ne 0 -or -not (Test-Path -LiteralPath $tracePath -PathType Leaf)) {
                    & $wpr -cancel -instancename $instance
                    $failed.Add("GPU queue trace was not saved (WPR stop exit $stopCode).")
                }
            }
        }
    } catch {
        $failed.Add("GPU queue: $($_.Exception.Message)")
        Write-Warning ($failed[$failed.Count - 1])
    }

    foreach ($priority in @(0, 1)) {
        Write-Host ("{0}/3: GPU priority {1}. Start the sample in the probe." -f ($priority + 2), $priority)
        $reportPath = Join-Path $output "gpu-priority-$priority.json"
        try {
            Invoke-CaptureProbe -CaptureMode dxgi-preview -DisabledFeatures $disabled -ProbeArgs (
                $baseArgs + @('--capture-probe-autostart', "--capture-probe-priority=$priority", "--capture-probe-report=$reportPath")
            )
        } catch {
            $failed.Add("GPU priority ${priority}: $($_.Exception.Message)")
            Write-Warning ($failed[$failed.Count - 1])
        }
    }
    Write-Host "Reports: $output"
    if ($failed.Count) {
        $failed | Set-Content -LiteralPath (Join-Path $output 'errors.txt') -Encoding UTF8
        throw "Some diagnostics failed. Reports and errors: $output"
    }
    return
}

$modes = switch ($Mode) {
    'all' { 'baseline', 'wgc', 'dxgi' }
    'both' { 'baseline', 'wgc' }
    'dxgi-compare' { 'dxgi-preview', 'dxgi' }
    'dxgi-send-compare' { 'dxgi', 'dxgi-send-only' }
    'dxgi-profile' { 'profile-default', 'profile-deferred' }
    'dxgi-nv12-compare' { 'profile-deferred', 'dxgi-nv12' }
    'dxgi-buffers' { 'buffers-4', 'buffers-6' }
    default { $Mode }
}
foreach ($case in $modes) {
    $captureMode = $case
    $disabledFeatures = 'WebRtcAllowWgcUsingTexture'
    $probeArgs = @()
    if ($case -eq 'dxgi-timing') {
        $captureMode = 'dxgi-preview'
        $disabledFeatures += ',BreakoutBoxEagerConversion'
        $probeArgs += '--capture-probe-timing'
    }
    if ($case -in 'buffers-4', 'buffers-6') {
        $captureMode = 'dxgi-send-only'
        $disabledFeatures += ',BreakoutBoxEagerConversion'
        $slots = $case.Substring('buffers-'.Length)
        $probeArgs += "--capture-probe-slots=$slots"
        Write-Host "DXGI BGRA: $slots texture buffers"
    }
    if ($case -in 'profile-default', 'profile-deferred') {
        $captureMode = 'dxgi-send-only'
    }
    if ($case -in 'profile-default', 'profile-deferred', 'dxgi-nv12') {
        $probeArgs += '--capture-probe-trace'
        if ($case -ne 'profile-default') {
            $disabledFeatures += ',BreakoutBoxEagerConversion'
        }
    }
    Invoke-CaptureProbe -CaptureMode $captureMode -DisabledFeatures $disabledFeatures -ProbeArgs $probeArgs
}
