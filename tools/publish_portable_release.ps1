# Build a slim Windows player zip and upload it as a GitHub Release.
# Slim zip: game content + city_voxel.dll. Godot and .godot are fetched/imported by City.bat.
param(
	[string]$Root = "",
	[string]$Tag = "",
	[switch]$SkipUpload,
	[switch]$RebuildPortable
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
	$Root = Split-Path -Parent $PSScriptRoot
}
$Root = (Resolve-Path $Root).Path

$GodotName = "Godot_v4.6-voxel_win64.exe"
$DistDir = Join-Path $Root "dist"
$StageDir = Join-Path $DistDir "CityPortableSlim"
$ZipPath = Join-Path $DistDir "CityPortable-windows.zip"
$MaxZipBytes = 2GB - 1MB

if ([string]::IsNullOrWhiteSpace($Tag)) {
	$Tag = "portable-" + (Get-Date -Format "yyyyMMdd")
}

function Write-Step([string]$msg) {
	Write-Host $msg
}

function Assert-Command([string]$name) {
	if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
		throw "$name not found on PATH"
	}
}

function Write-CityLauncher([string]$outPath) {
	$contents = @"
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "GODOT_EXE=%ROOT%\tools\godot\$GodotName"

if not exist "%GODOT_EXE%" (
	if not exist "%ROOT%\tools\ensure_city_deps.ps1" (
		echo ERROR: Engine missing and tools\ensure_city_deps.ps1 not found.
		echo Place $GodotName in tools\godot\ or restore ensure_city_deps.ps1.
		pause
		exit /b 1
	)
	echo.
	echo Engine missing - downloading Godot 4.6 + Voxel Tools (~80 MB)...
	echo Internet required for this first-time step.
	echo.
	powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\ensure_city_deps.ps1" -Root "%ROOT%"
	if errorlevel 1 (
		echo ERROR: Could not download the Godot voxel engine.
		pause
		exit /b 1
	)
)
if not exist "%GODOT_EXE%" (
	echo ERROR: Engine still missing: %GODOT_EXE%
	pause
	exit /b 1
)
if not exist "%ROOT%\project.godot" (
	echo ERROR: project.godot missing in %ROOT%
	pause
	exit /b 1
)
if not exist "%ROOT%\addons\city_voxel\bin\city_voxel.dll" (
	echo ERROR: addons\city_voxel\bin\city_voxel.dll missing.
	echo This DLL ships with the release zip and is required to play.
	pause
	exit /b 1
)
if not exist "%ROOT%\.godot\global_script_class_cache.cfg" goto do_import
if not exist "%ROOT%\.godot\imported" goto do_import
goto launch

:do_import
echo.
echo First-time asset import - this can take several minutes. Please wait...
echo.
"%GODOT_EXE%" --headless --path "%ROOT%" --import
if errorlevel 1 (
	echo ERROR: Godot --import failed.
	pause
	exit /b 1
)
if not exist "%ROOT%\.godot\global_script_class_cache.cfg" (
	echo ERROR: Import finished but .godot class cache is still missing.
	pause
	exit /b 1
)
echo.

:launch
start "City" /MAX "%GODOT_EXE%" --path "%ROOT%" res://scenes/city_poc.tscn --maximized
endlocal
"@
	Set-Content -Path $outPath -Value $contents -Encoding ASCII
}

function Stage-SlimPortable {
	Write-Step "Staging slim portable at $StageDir ..."
	if (Test-Path $StageDir) {
		Remove-Item -Recurse -Force $StageDir
	}
	New-Item -ItemType Directory -Force -Path $StageDir | Out-Null
	New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

	# Absolute /XD paths — relative "tools\vendor" is ignored by robocopy.
	$xd = @(
		(Join-Path $Root ".git"),
		(Join-Path $Root ".godot"),
		(Join-Path $Root ".godot_check_out"),
		(Join-Path $Root "dist"),
		(Join-Path $Root "native"),
		(Join-Path $Root ".cursor"),
		(Join-Path $Root "tools\vendor"),
		(Join-Path $Root "tools\godot")
	)
	$xf = @("*.tmp", "*.log", "publish_portable_release.bat")
	$rcArgs = @(
		$Root, $StageDir, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/nc", "/ns", "/np",
		"/XD"
	) + $xd + @("/XF") + $xf + @("/R:2", "/W:2")
	& robocopy @rcArgs | Out-Null
	$rc = $LASTEXITCODE
	if ($rc -ge 8) {
		throw "robocopy failed with code $rc"
	}
	## Belt-and-suspenders: never ship Blender vendor trees or a local engine binary.
	foreach ($dead in @(
		(Join-Path $StageDir "tools\vendor"),
		(Join-Path $StageDir "tools\godot"),
		(Join-Path $StageDir ".godot")
	)) {
		if (Test-Path $dead) {
			Remove-Item -Recurse -Force $dead
		}
	}

	$dllSrc = Join-Path $Root "addons\city_voxel\bin\city_voxel.dll"
	$dllDstDir = Join-Path $StageDir "addons\city_voxel\bin"
	if (-not (Test-Path $dllSrc)) {
		throw "city_voxel.dll missing at $dllSrc - required in the release zip"
	}
	New-Item -ItemType Directory -Force -Path $dllDstDir | Out-Null
	Copy-Item -Force $dllSrc (Join-Path $dllDstDir "city_voxel.dll")

	$ensureSrc = Join-Path $Root "tools\ensure_city_deps.ps1"
	$ensureDstDir = Join-Path $StageDir "tools"
	New-Item -ItemType Directory -Force -Path $ensureDstDir | Out-Null
	Copy-Item -Force $ensureSrc (Join-Path $ensureDstDir "ensure_city_deps.ps1")

	Write-CityLauncher (Join-Path $StageDir "City.bat")
	Copy-Item -Force (Join-Path $Root "install_city.bat") (Join-Path $StageDir "install_city.bat")

	$readme = @"
City - Windows portable (slim)
==============================

1. Unzip this folder anywhere.
2. Double-click City.bat
3. First launch downloads Godot 4.6 + Voxel Tools (~80 MB, internet required)
   and imports assets (several minutes). Later launches are offline.

Optional: install_city.bat copies into %LOCALAPPDATA%\Programs\City with shortcuts.

Keep city_voxel.dll under addons\city_voxel\bin\ - required, not downloaded.
"@
	Set-Content -Path (Join-Path $StageDir "README_INSTALL.txt") -Value $readme -Encoding UTF8
}

function Compress-SlimZip {
	Write-Step "Zipping -> $ZipPath ..."
	if (Test-Path $ZipPath) {
		Remove-Item -Force $ZipPath
	}
	# tar.exe produces more compact zips than Compress-Archive on large trees.
	$tar = Get-Command tar.exe -ErrorAction SilentlyContinue
	if ($null -ne $tar) {
		Push-Location $DistDir
		try {
			& tar.exe -a -cf "CityPortable-windows.zip" "CityPortableSlim"
			if ($LASTEXITCODE -ne 0) {
				throw "tar zip failed ($LASTEXITCODE)"
			}
		}
		finally {
			Pop-Location
		}
	}
	else {
		Compress-Archive -Path $StageDir -DestinationPath $ZipPath -Force
	}
	$item = Get-Item $ZipPath
	Write-Step ("Zip size: {0:N1} MB" -f ($item.Length / 1MB))
	if ($item.Length -ge $MaxZipBytes) {
		throw "Zip is too large for a GitHub Release asset (limit 2 GiB). Size=$($item.Length)"
	}
}

function Publish-Release {
	Assert-Command "gh"
	$auth = & gh auth status 2>&1
	if ($LASTEXITCODE -ne 0) {
		throw "gh is not logged in. Run: gh auth login"
	}

	$notes = @"
## City portable (Windows)

1. Download **CityPortable-windows.zip** and unzip it.
2. Double-click **City.bat**.
3. First launch downloads Godot 4.6 + Voxel Tools (~80 MB) and imports assets (a few minutes). Later launches work offline.

Optional: run **install_city.bat** for shortcuts under ``%LOCALAPPDATA%\Programs\City``.

``city_voxel.dll`` is included. No Rust/Visual Studio build required.
"@

	## "release not found" writes to stderr — must not trip $ErrorActionPreference Stop.
	$prevEap = $ErrorActionPreference
	$ErrorActionPreference = "Continue"
	$null = & gh release view $Tag 2>&1
	$viewCode = $LASTEXITCODE
	$ErrorActionPreference = $prevEap

	if ($viewCode -eq 0) {
		Write-Step "Release $Tag exists - uploading/replacing asset..."
		& gh release upload $Tag $ZipPath --clobber
		if ($LASTEXITCODE -ne 0) {
			throw "gh release upload failed"
		}
	}
	else {
		Write-Step "Creating GitHub release $Tag ..."
		& gh release create $Tag $ZipPath --title "City portable $Tag" --notes $notes
		if ($LASTEXITCODE -ne 0) {
			throw "gh release create failed"
		}
	}
	& gh release view $Tag --json url -q .url
}

if ($RebuildPortable) {
	Write-Step "Rebuilding full portable via make_installer.bat /S (optional local bake)..."
	$make = Join-Path $Root "make_installer.bat"
	& cmd.exe /c "`"$make`" /S"
	if ($LASTEXITCODE -ne 0) {
		throw "make_installer.bat failed"
	}
}

Stage-SlimPortable
Compress-SlimZip

if ($SkipUpload) {
	Write-Step "SkipUpload set - zip ready at $ZipPath"
	exit 0
}

Publish-Release
Write-Step "Done."
exit 0
