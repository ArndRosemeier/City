# Build the City voxel GDExtension (Windows x64).
# Requires: Rust stable + Visual Studio with C++ (MSVC).
$ErrorActionPreference = "Stop"
$env:Path = "$env:USERPROFILE\.cargo\bin;" + $env:Path
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
  throw "cargo not found. Install Rust from https://rustup.rs/ and reopen the shell."
}

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
  Write-Host @"
MSVC not found. Install Visual Studio with 'Desktop development with C++'.
Until then the game uses the GDScript OfflineVoxelVolume fallback.
"@
  exit 1
}

$root = Split-Path -Parent $PSScriptRoot
$crate = Join-Path $root "native\city_voxel"
$outDir = Join-Path $root "addons\city_voxel\bin"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$bat = Join-Path $env:TEMP "city_voxel_build.bat"
@"
@echo off
call "$vcvars" >nul
cd /d "$crate"
set CARGO_TARGET_DIR=$crate\target
cargo build --release
if errorlevel 1 exit /b 1
copy /Y "$crate\target\release\city_voxel.dll" "$outDir\city_voxel.dll"
"@ | Set-Content -Path $bat -Encoding ASCII

cmd /c "`"$bat`""
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "Installed $outDir\city_voxel.dll"
