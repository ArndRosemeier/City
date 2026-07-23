# Ensures City runtime deps are present (Godot + Voxel Tools engine, optional native bake DLL).
# Safe to call repeatedly. Used by install_city.bat / pack scripts.
param(
	[string]$Root = "",
	[switch]$RequireNativeDll
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
	$Root = Split-Path -Parent $PSScriptRoot
}
$Root = (Resolve-Path $Root).Path

$GodotDir = Join-Path $Root "tools\godot"
$GodotExe = Join-Path $GodotDir "Godot_v4.6-voxel_win64.exe"
$GodotZipUrl = "https://github.com/Zylann/godot_voxel/releases/download/v1.6/godot.windows.editor.x86_64.exe.zip"
$GodotZipNameInArchive = "godot.windows.editor.x86_64.exe"
$MinGodotBytes = 50MB

$NativeDll = Join-Path $Root "addons\city_voxel\bin\city_voxel.dll"


function Write-Step([string]$msg) {
	Write-Host $msg
}


function Get-RemoteFile([string]$Url, [string]$OutFile) {
	$dir = Split-Path -Parent $OutFile
	if (-not (Test-Path $dir)) {
		New-Item -ItemType Directory -Force -Path $dir | Out-Null
	}
	$curl = Get-Command curl.exe -ErrorAction SilentlyContinue
	if ($null -ne $curl) {
		Write-Step ("  curl " + $Url)
		& curl.exe -L --fail --retry 3 --retry-delay 2 -o $OutFile $Url
		if ($LASTEXITCODE -ne 0) {
			throw ("curl failed (" + $LASTEXITCODE + ") downloading " + $Url)
		}
		return
	}
	Write-Step ("  Invoke-WebRequest " + $Url)
	Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
}


function Install-GodotVoxel {
	if ((Test-Path $GodotExe) -and ((Get-Item $GodotExe).Length -ge $MinGodotBytes)) {
		Write-Step ("Godot voxel engine OK: " + $GodotExe)
		return $GodotExe
	}

	Write-Step "Downloading Godot 4.6 + Voxel Tools 1.6 (~80 MB zip)..."
	New-Item -ItemType Directory -Force -Path $GodotDir | Out-Null
	$tmp = Join-Path $env:TEMP ("city_godot_voxel_" + [guid]::NewGuid().ToString("N"))
	New-Item -ItemType Directory -Force -Path $tmp | Out-Null
	$zip = Join-Path $tmp "godot_voxel.zip"
	try {
		Get-RemoteFile -Url $GodotZipUrl -OutFile $zip
		Write-Step "Extracting..."
		Expand-Archive -Path $zip -DestinationPath $tmp -Force
		$extracted = Get-ChildItem -Path $tmp -Recurse -Filter "*.exe" |
			Where-Object { $_.Name -eq $GodotZipNameInArchive -or $_.Name -like "godot*.exe" } |
			Sort-Object Length -Descending |
			Select-Object -First 1
		if ($null -eq $extracted) {
			throw "No Godot .exe found inside downloaded zip."
		}
		Copy-Item -Force $extracted.FullName $GodotExe
		if ((Get-Item $GodotExe).Length -lt $MinGodotBytes) {
			throw ("Downloaded Godot looks too small: " + $GodotExe)
		}
		Write-Step ("Installed engine -> " + $GodotExe)
	}
	finally {
		Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
	}
	return $GodotExe
}


function Install-NativeDll {
	if ((Test-Path $NativeDll) -and ((Get-Item $NativeDll).Length -gt 10KB)) {
		Write-Step ("Native city_voxel.dll OK: " + $NativeDll)
		return $true
	}

	$buildScript = Join-Path $PSScriptRoot "build_city_voxel.ps1"
	if (-not (Test-Path $buildScript)) {
		Write-Step "WARNING: city_voxel.dll missing and build script not found (GDScript bake fallback)."
		return (-not $RequireNativeDll.IsPresent)
	}

	Write-Step "city_voxel.dll missing - trying local Rust build (optional, faster baking)..."
	try {
		& powershell -NoProfile -ExecutionPolicy Bypass -File $buildScript
		if ((Test-Path $NativeDll) -and ((Get-Item $NativeDll).Length -gt 10KB)) {
			Write-Step ("Built native DLL -> " + $NativeDll)
			return $true
		}
	}
	catch {
		Write-Step ("WARNING: native build failed: " + $_.Exception.Message)
	}

	Write-Step "Continuing without city_voxel.dll (GDScript OfflineVoxelVolume fallback)."
	if ($RequireNativeDll.IsPresent) {
		return $false
	}
	return $true
}


$exePath = Install-GodotVoxel
if (-not (Install-NativeDll)) {
	exit 2
}

# Emit path for batch callers: last line is the engine path.
Write-Output $exePath
exit 0
