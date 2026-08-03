# Fetch sources needed to build the in-process KataGo GDExtension.
# Does not fetch neural nets — use tools/ensure_katago.ps1 for those.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$deps = Join-Path $root "native\katago_deps"
$third = Join-Path $root "native\third_party"
New-Item -ItemType Directory -Force -Path $deps, $third | Out-Null

function Get-Zip($url, $outFile) {
  if (Test-Path $outFile) { return }
  Write-Host "Downloading $url"
  Invoke-WebRequest -Uri $url -OutFile $outFile -UseBasicParsing
}

# Eigen 3.4.0 (header-only)
$eigenZip = Join-Path $deps "eigen.zip"
$eigenDir = Join-Path $deps "eigen"
if (-not (Test-Path (Join-Path $eigenDir "Eigen\Core"))) {
  Get-Zip "https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.zip" $eigenZip
  $tmp = Join-Path $deps "_eigen_unpack"
  if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
  Expand-Archive -Path $eigenZip -DestinationPath $tmp -Force
  $inner = Get-ChildItem $tmp | Select-Object -First 1
  if (Test-Path $eigenDir) { Remove-Item -Recurse -Force $eigenDir }
  Move-Item $inner.FullName $eigenDir
  Remove-Item -Recurse -Force $tmp
  Write-Host "Eigen ready at $eigenDir"
}

# zlib 1.3.1 sources
$zlibTg = Join-Path $deps "zlib.tar.gz"
$zlibDir = Join-Path $deps "zlib"
if (-not (Test-Path (Join-Path $zlibDir "CMakeLists.txt"))) {
  Get-Zip "https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz" $zlibTg
  # tar is available on modern Windows
  $tmp = Join-Path $deps "_zlib_unpack"
  if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  tar -xf $zlibTg -C $tmp
  $inner = Get-ChildItem $tmp | Select-Object -First 1
  if (Test-Path $zlibDir) { Remove-Item -Recurse -Force $zlibDir }
  Move-Item $inner.FullName $zlibDir
  Remove-Item -Recurse -Force $tmp
  Write-Host "zlib ready at $zlibDir"
}

# KataGo v1.16.5
$kata = Join-Path $third "KataGo"
if (-not (Test-Path (Join-Path $kata "cpp\CMakeLists.txt"))) {
  if (Test-Path $kata) { Remove-Item -Recurse -Force $kata }
  Write-Host "Cloning KataGo v1.16.5 (shallow)..."
  git clone --depth 1 --branch v1.16.5 https://github.com/lightvector/KataGo.git $kata
  Write-Host "KataGo ready at $kata"
}

Write-Host "OK - embed deps present. Next: tools\build_city_katago.ps1"
