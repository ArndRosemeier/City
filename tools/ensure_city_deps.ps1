# Ensures City runtime deps are present (Godot + Voxel Tools engine).
# city_voxel.dll is shipped in-repo under addons/city_voxel/bin/.
# Safe to call repeatedly. Used by install_city.bat / pack scripts.
param(
	[string]$Root = ""
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
	# stderr so batch callers can parse stdout as the engine path only
	[Console]::Error.WriteLine($msg)
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


function Assert-NativeDll {
	if ((Test-Path $NativeDll) -and ((Get-Item $NativeDll).Length -gt 10KB)) {
		Write-Step ("Native city_voxel.dll OK: " + $NativeDll)
		return
	}
	Write-Step ("WARNING: city_voxel.dll missing at " + $NativeDll)
	Write-Step "Rebuild with tools\build_city_voxel.ps1 if you need the fast native bake path."
	Write-Step "Game still runs with the GDScript OfflineVoxelVolume fallback."
}


$exePath = Install-GodotVoxel
Assert-NativeDll

# Emit path for batch callers: last line is the engine path.
Write-Output $exePath
exit 0
