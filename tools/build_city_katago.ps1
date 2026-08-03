# Build in-process KataGo GDExtension (Windows x64).
# Produces:
#   addons/city_katago/bin/city_katago_native.dll  (C++ Eigen embed)
#   addons/city_katago/bin/city_katago.dll         (Rust Godot binding)
#
# Requires: VS 2022 C++, CMake (VS-bundled ok), Rust stable, fetched deps:
#   native/third_party/KataGo (tag v1.16.5)
#   native/katago_deps/eigen + zlib
#   tools/katago/*.bin.gz model for smoke (via ensure_katago.ps1)
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsPath = $null
if (Test-Path $vswhere) {
  $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  if (-not $vsPath) {
    $vsPath = & $vswhere -latest -products * -property installationPath
  }
}
$vcvars = $null
if ($vsPath) {
  $candidate = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
  if (Test-Path $candidate) { $vcvars = $candidate }
}
if (-not $vcvars) {
  Write-Host "MSVC not found. Install Visual Studio with 'Desktop development with C++'."
  exit 1
}

$cmakeCandidates = @(
  (Join-Path $vsPath "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"),
  "${env:ProgramFiles}\CMake\bin\cmake.exe",
  "${env:ProgramFiles(x86)}\CMake\bin\cmake.exe"
)
$cmake = $cmakeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $cmake) {
  $cmd = Get-Command cmake -ErrorAction SilentlyContinue
  if ($cmd) { $cmake = $cmd.Source }
}
if (-not $cmake) {
  Write-Host "cmake not found (install VS CMake component or CMake)."
  exit 1
}

$env:Path = "$env:USERPROFILE\.cargo\bin;" + $env:Path
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
  throw "cargo not found. Install Rust from https://rustup.rs/"
}

$embed = Join-Path $root "native\katago_embed"
$buildDir = Join-Path $embed "build"
$crate = Join-Path $root "native\city_katago"
$outDir = Join-Path $root "addons\city_katago\bin"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

$bat = Join-Path $env:TEMP "city_katago_build.bat"
@"
@echo off
setlocal
call "$vcvars" >nul
if errorlevel 1 exit /b 1

echo === Configure city_katago_embed ===
"$cmake" -S "$embed" -B "$buildDir" -G "Visual Studio 17 2022" -A x64
if errorlevel 1 exit /b 1

echo === Build city_katago_native (RelWithDebInfo) ===
"$cmake" --build "$buildDir" --config RelWithDebInfo --target city_katago_native -j
if errorlevel 1 exit /b 1

set CITY_KATAGO_NATIVE_LIB_DIR=$buildDir\RelWithDebInfo
copy /Y "%CITY_KATAGO_NATIVE_LIB_DIR%\city_katago_native.dll" "$outDir\city_katago_native.dll"
if errorlevel 1 exit /b 1

echo === Build city_katago Rust GDExtension ===
cd /d "$crate"
set CARGO_TARGET_DIR=$crate\target
cargo build --release
if errorlevel 1 exit /b 1
copy /Y "$crate\target\release\city_katago.dll" "$outDir\city_katago.dll"
if errorlevel 1 exit /b 1

echo Installed:
echo   $outDir\city_katago_native.dll
echo   $outDir\city_katago.dll
"@ | Set-Content -Path $bat -Encoding ASCII

Write-Host "Running build via $bat"
cmd /c "`"$bat`""
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Headless Godot only loads extensions listed here; editor regenerates on open.
$extList = Join-Path $root ".godot\extension_list.cfg"
$extEntry = "res://addons/city_katago/city_katago.gdextension"
if (Test-Path (Split-Path -Parent $extList)) {
  $lines = @()
  if (Test-Path $extList) {
    $lines = @(Get-Content $extList | Where-Object { $_.Trim() -ne "" })
  }
  if ($lines -notcontains $extEntry) {
    $lines += $extEntry
    Set-Content -Path $extList -Value (($lines -join "`n") + "`n") -NoNewline
    Write-Host "Registered $extEntry in .godot/extension_list.cfg"
  }
}

Write-Host "OK"
