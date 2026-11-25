param([switch] $Probe)

$ErrorActionPreference = 'Stop'
$cargo = (Get-Command cargo.exe -ErrorAction SilentlyContinue).Source
if (-not $cargo) { throw 'Rust x64 MSVC toolchain not found. Install Rust from https://rustup.rs/.' }

$desktop = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$target = Join-Path $desktop 'build\screen-capture'
$features = @()
if ($Probe) {
    $target = Join-Path $desktop 'build\screen-capture-probe'
    $features = @('--features', 'capture-probe')
}
$triple = 'x86_64-pc-windows-msvc'
& $cargo build --manifest-path (Join-Path $PSScriptRoot 'Cargo.toml') --target-dir $target --target $triple --release --locked @features
if ($LASTEXITCODE -ne 0) { throw 'Native screen capture build failed.' }

$release = Join-Path $target "$triple\release"
Copy-Item -LiteralPath (Join-Path $release 'glitch_screen_capture.dll') -Destination (Join-Path $release 'glitch_screen_capture.node') -Force
