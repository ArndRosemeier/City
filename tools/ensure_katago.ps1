# Download KataGo Windows engines + a dan-capable network into tools/katago/.
#
#   powershell -File tools\ensure_katago.ps1
#
# Binaries and nets are gitignored. Phase-1 smoke uses the Eigen build (no OpenCL
# autotune); OpenCL is fetched for the later GPU path.
param(
	[string]$Root = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
	$Root = Split-Path -Parent $PSScriptRoot
}
$Root = (Resolve-Path $Root).Path
$OutDir = Join-Path $Root "tools\katago"
$Version = "v1.16.5"
$Base = "https://github.com/lightvector/KataGo/releases/download/$Version"
## Strong self-play net (optional / analysis); Gaming play uses Human-SL below.
$NetworkUrl = "https://media.katagotraining.org/uploaded/networks/models/kata1/kata1-b18c384nbt-s9996604416-d4316597426.bin.gz"
$NetworkName = "kata1-b18c384nbt.bin.gz"
## Official Human-SL net — rank_20k … rank_9d via humanSLProfile (KataGo v1.15+).
$HumanNetworkUrl = "https://github.com/lightvector/KataGo/releases/download/v1.15.0/b18c384nbt-humanv0.bin.gz"
$HumanNetworkName = "b18c384nbt-humanv0.bin.gz"

$engines = @(
	@{
		Zip = "katago-v1.16.5-eigenavx2-windows-x64.zip"
		Dir = "eigen"
	},
	@{
		Zip = "katago-v1.16.5-opencl-windows-x64.zip"
		Dir = "opencl"
	}
)

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Get-File([string]$Url, [string]$Dest) {
	if ((Test-Path -LiteralPath $Dest) -and ((Get-Item -LiteralPath $Dest).Length -gt 1MB)) {
		Write-Host "OK (cached): $(Split-Path -Leaf $Dest)"
		return
	}
	Write-Host "Downloading $Url"
	$tmp = "$Dest.download"
	Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing
	Move-Item -Force $tmp $Dest
	Write-Host ("  -> {0} ({1:N1} MB)" -f (Split-Path -Leaf $Dest), ((Get-Item $Dest).Length / 1MB))
}

foreach ($eng in $engines) {
	$zipPath = Join-Path $OutDir $eng.Zip
	Get-File "$Base/$($eng.Zip)" $zipPath
	$engDir = Join-Path $OutDir $eng.Dir
	$exePath = Join-Path $engDir "katago.exe"
	if (-not (Test-Path -LiteralPath $exePath)) {
		if (Test-Path $engDir) {
			Remove-Item -Recurse -Force $engDir
		}
		New-Item -ItemType Directory -Force -Path $engDir | Out-Null
		## Full extract — Windows builds ship OpenSSL / VC runtime DLLs beside the exe.
		tar -xf $zipPath -C $engDir
		if (-not (Test-Path -LiteralPath $exePath)) {
			throw "No katago.exe after extracting $($eng.Zip)"
		}
		Write-Host "Installed $($eng.Dir)/katago.exe (+ DLLs)"
	}
	else {
		Write-Host "OK (cached): $($eng.Dir)/katago.exe"
	}
}

## Remove legacy single-exe copies from the first ensure script revision.
foreach ($legacy in @("katago_eigen.exe", "katago_opencl.exe")) {
	$p = Join-Path $OutDir $legacy
	if (Test-Path $p) {
		Remove-Item -Force $p
	}
}

$netPath = Join-Path $OutDir $NetworkName
Get-File $NetworkUrl $netPath
$humanPath = Join-Path $OutDir $HumanNetworkName
Get-File $HumanNetworkUrl $humanPath

## Upstream default_gtp.cfg has every required key; smoke overrides visits on the CLI.
$cfgSrc = Join-Path $OutDir "eigen\default_gtp.cfg"
$cfgPath = Join-Path $OutDir "smoke.cfg"
if (-not (Test-Path -LiteralPath $cfgSrc)) {
	throw "Missing $cfgSrc after eigen extract"
}
Copy-Item -Force $cfgSrc $cfgPath

Write-Host ""
Write-Host "KataGo ready under $OutDir"
Write-Host "  eigen:   $(Join-Path $OutDir 'eigen\katago.exe')"
Write-Host "  opencl:  $(Join-Path $OutDir 'opencl\katago.exe')"
Write-Host "  network: $netPath"
Write-Host "  human:   $humanPath"
Write-Host "  config:  $cfgPath"
