# Unified Eccentri City packer.
# Stages a CLEAN tree from git (not the dirty working copy), validates it, then emits:
#   -Folder   -> dist/EccentriCityPortable   (engine + baked .godot)
#   -Zip      -> dist/EccentriCityPortable-windows.zip  (slim: no engine / no .godot)
#   -Publish  -> Zip + gh release upload
#   -Check    -> tracking + required files only
#
# Usage:
#   powershell -File tools/pack_release.ps1 -Mode Folder
#   powershell -File tools/pack_release.ps1 -Mode Zip
#   powershell -File tools/pack_release.ps1 -Mode Publish [-Tag portable-YYYYMMDD]
#   powershell -File tools/pack_release.ps1 -Mode Check
param(
	[string]$Root = "",
	[ValidateSet("Check", "Folder", "Zip", "Publish")]
	[string]$Mode = "Folder",
	[string]$Tag = "",
	[switch]$SkipUpload,
	[switch]$SkipTrackingCheck
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
	$Root = Split-Path -Parent $PSScriptRoot
}
$Root = (Resolve-Path $Root).Path

$GodotName = "Godot_v4.6-voxel_win64.exe"
$DistDir = Join-Path $Root "dist"
$StageName = "EccentriCityPortable"
$SlimName = "EccentriCityPortableSlim"
$StageDir = Join-Path $DistDir $StageName
$SlimDir = Join-Path $DistDir $SlimName
$ZipPath = Join-Path $DistDir "EccentriCityPortable-windows.zip"
$MaxZipBytes = 2GB - 1MB
$ExcludesFile = Join-Path $Root "tools\ship_excludes.txt"

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

function Get-ShipExcludes {
	$patterns = @()
	if (-not (Test-Path $ExcludesFile)) {
		return $patterns
	}
	Get-Content -LiteralPath $ExcludesFile | ForEach-Object {
		$line = $_.Trim()
		if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) {
			return
		}
		$patterns += ($line -replace "\\", "/")
	}
	return $patterns
}

function Test-ShipExcluded([string]$rel, [string[]]$patterns) {
	$rel = $rel -replace "\\", "/"
	foreach ($p in $patterns) {
		if ($p.EndsWith("/")) {
			$prefix = $p.TrimEnd("/")
			if ($rel -eq $prefix -or $rel.StartsWith($p) -or $rel.StartsWith("$prefix/")) {
				return $true
			}
			continue
		}
		# Simple * ? glob against full relative path.
		if ($rel -like $p) {
			return $true
		}
	}
	return $false
}

function Get-ShipFiles {
	Assert-Command "git"
	Push-Location $Root
	try {
		$excludes = Get-ShipExcludes
		$files = @(git -c core.quotepath=false ls-files -z).Split([char]0, [System.StringSplitOptions]::RemoveEmptyEntries)
		$out = @()
		foreach ($f in $files) {
			$norm = $f -replace "\\", "/"
			if (Test-ShipExcluded $norm $excludes) {
				continue
			}
			$out += $norm
		}
		return $out
	}
	finally {
		Pop-Location
	}
}

function Clear-Dir([string]$path) {
	if (Test-Path $path) {
		Remove-Item -Recurse -Force $path
	}
	New-Item -ItemType Directory -Force -Path $path | Out-Null
}

function Stage-FromGit([string]$dest, [string[]]$files) {
	Write-Step "Staging $($files.Count) git-tracked ship files -> $dest"
	Clear-Dir $dest
	foreach ($rel in $files) {
		$src = Join-Path $Root ($rel -replace "/", "\")
		if (-not (Test-Path -LiteralPath $src)) {
			throw "Tracked file missing on disk: $rel"
		}
		$dst = Join-Path $dest ($rel -replace "/", "\")
		$dstDir = Split-Path -Parent $dst
		if (-not (Test-Path $dstDir)) {
			New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
		}
		Copy-Item -LiteralPath $src -Destination $dst -Force
	}
}

function Ensure-Launcher([string]$dest) {
	$launcherSrc = Join-Path $Root "EccentriCity.bat"
	if (-not (Test-Path $launcherSrc)) {
		throw "EccentriCity.bat missing at repo root (required ship launcher)"
	}
	Copy-Item -Force $launcherSrc (Join-Path $dest "EccentriCity.bat")
	$installSrc = Join-Path $Root "install_city.bat"
	if (Test-Path $installSrc) {
		Copy-Item -Force $installSrc (Join-Path $dest "install_city.bat")
	}
	$readme = @"
Eccentri City - Windows portable
==============================

1. Unzip / open this folder.
2. Double-click EccentriCity.bat
3. First launch may download Godot 4.6 + Voxel Tools (~80 MB) and import assets.

Keep addons\city_voxel\bin\city_voxel.dll — required, not downloaded.
"@
	Set-Content -Path (Join-Path $dest "README_INSTALL.txt") -Value $readme -Encoding UTF8
}

function Ensure-Engine([string]$projectRoot) {
	$ensure = Join-Path $Root "tools\ensure_city_deps.ps1"
	if (-not (Test-Path $ensure)) {
		throw "tools\ensure_city_deps.ps1 missing"
	}
	Write-Step "Ensuring Godot voxel engine..."
	## ensure_city_deps writes progress to stderr; do not treat that as terminating.
	$prev = $ErrorActionPreference
	$ErrorActionPreference = "Continue"
	& powershell -NoProfile -ExecutionPolicy Bypass -File $ensure -Root $projectRoot 2>&1 | ForEach-Object { Write-Host $_ }
	$code = $LASTEXITCODE
	$ErrorActionPreference = $prev
	if ($code -ne 0) {
		throw "ensure_city_deps.ps1 failed ($code)"
	}
	$exe = Join-Path $projectRoot "tools\godot\$GodotName"
	if (-not (Test-Path $exe)) {
		# Engine may have been installed into the source repo; copy into the stage.
		$repoExe = Join-Path $Root "tools\godot\$GodotName"
		if (-not (Test-Path $repoExe)) {
			throw "Engine still missing: $exe"
		}
		$destDir = Join-Path $projectRoot "tools\godot"
		New-Item -ItemType Directory -Force -Path $destDir | Out-Null
		Copy-Item -Force $repoExe $exe
	}
	return $exe
}

function Invoke-Import([string]$projectRoot, [string]$godotExe) {
	Write-Step "Headless import on $projectRoot ..."
	$outLog = Join-Path $env:TEMP ("city_import_out_" + [guid]::NewGuid().ToString("N") + ".log")
	$errLog = Join-Path $env:TEMP ("city_import_err_" + [guid]::NewGuid().ToString("N") + ".log")
	$p = Start-Process -FilePath $godotExe -ArgumentList @(
		"--headless", "--path", $projectRoot, "--import"
	) -Wait -PassThru -NoNewWindow -RedirectStandardOutput $outLog -RedirectStandardError $errLog
	Write-Step ("  Godot --import exit " + $p.ExitCode)
	$check = Join-Path $Root "tools\check_godot_import_artifacts.ps1"
	& powershell -NoProfile -ExecutionPolicy Bypass -File $check -InstallDir $projectRoot
	if ($LASTEXITCODE -ne 0) {
		if (Test-Path $errLog) {
			Get-Content $errLog | Select-Object -Last 40 | Write-Host
		}
		throw "Import did not produce .godot class cache / imported assets"
	}
	Remove-Item -Force $outLog, $errLog -ErrorAction SilentlyContinue
}

function Invoke-Validate([string]$projectRoot, [string]$godotExe) {
	Write-Step "Validating portable tree..."
	$outLog = Join-Path $env:TEMP ("city_portable_validate_" + [guid]::NewGuid().ToString("N") + ".log")
	$errLog = "$outLog.err"
	$p = Start-Process -FilePath $godotExe -ArgumentList @(
		"--headless", "--path", $projectRoot, "-s", "res://tools/validate_portable.gd"
	) -Wait -PassThru -NoNewWindow -RedirectStandardOutput $outLog -RedirectStandardError $errLog
	$combined = @()
	if (Test-Path $outLog) {
		$combined += Get-Content $outLog
	}
	if (Test-Path $errLog) {
		$combined += Get-Content $errLog
	}
	$ok = $combined | Select-String -Pattern "PORTABLE_VALIDATE: OK" -Quiet
	if (-not $ok) {
		$combined | Write-Host
		throw "Portable validation failed (Godot exit $($p.ExitCode))"
	}
	if ($p.ExitCode -ne 0) {
		$combined | Write-Host
		throw "Validator exited with code $($p.ExitCode)"
	}
	Write-Step "Validation OK."
	Remove-Item -Force $outLog, $errLog -ErrorAction SilentlyContinue
}

function Assert-NoForbidden([string]$dir) {
	$forbidden = @(
		"_kenney_src",
		"tools\vendor",
		"native\city_voxel\target"
	)
	foreach ($frag in $forbidden) {
		$hit = Get-ChildItem -LiteralPath $dir -Recurse -Directory -ErrorAction SilentlyContinue |
			Where-Object { $_.FullName -match [regex]::Escape($frag) } |
			Select-Object -First 1
		if ($null -ne $hit) {
			throw "Forbidden path leaked into package: $($hit.FullName)"
		}
	}
}

function Compress-Zip([string]$sourceDir, [string]$zipPath) {
	Write-Step "Zipping -> $zipPath ..."
	if (Test-Path $zipPath) {
		Remove-Item -Force $zipPath
	}
	$parent = Split-Path -Parent $sourceDir
	$leaf = Split-Path -Leaf $sourceDir
	$tar = Get-Command tar.exe -ErrorAction SilentlyContinue
	if ($null -ne $tar) {
		Push-Location $parent
		try {
			& tar.exe -a -cf (Split-Path -Leaf $zipPath) $leaf
			if ($LASTEXITCODE -ne 0) {
				throw "tar zip failed ($LASTEXITCODE)"
			}
			$written = Join-Path $parent (Split-Path -Leaf $zipPath)
			if ($written -ne $zipPath) {
				Move-Item -Force $written $zipPath
			}
		}
		finally {
			Pop-Location
		}
	}
	else {
		Compress-Archive -Path $sourceDir -DestinationPath $zipPath -Force
	}
	$item = Get-Item $zipPath
	Write-Step ("Zip size: {0:N1} MB" -f ($item.Length / 1MB))
	if ($item.Length -ge $MaxZipBytes) {
		throw "Zip too large for GitHub Release (limit 2 GiB). Size=$($item.Length)"
	}
}

function Publish-Release([string]$zipPath, [string]$tag) {
	Assert-Command "gh"
	$auth = & gh auth status 2>&1
	if ($LASTEXITCODE -ne 0) {
		throw "gh is not logged in. Run: gh auth login"
	}
	$notes = @"
## Eccentri City portable (Windows)

1. Download **EccentriCityPortable-windows.zip** and unzip it.
2. Double-click **EccentriCity.bat**.
3. First launch downloads Godot 4.6 + Voxel Tools (~80 MB) and imports assets (a few minutes). Later launches work offline.

Optional: run **install_city.bat** for shortcuts under ``%LOCALAPPDATA%\Programs\EccentriCity``.

``city_voxel.dll`` is included. No Rust/Visual Studio build required.

This build is staged from **git-tracked files only** (dirty working-tree junk cannot leak in).
"@
	$prevEap = $ErrorActionPreference
	$ErrorActionPreference = "Continue"
	$null = & gh release view $tag 2>&1
	$viewCode = $LASTEXITCODE
	$ErrorActionPreference = $prevEap

	if ($viewCode -eq 0) {
		Write-Step "Release $tag exists - uploading/replacing asset..."
		& gh release upload $tag $zipPath --clobber
		if ($LASTEXITCODE -ne 0) {
			throw "gh release upload failed"
		}
	}
	else {
		Write-Step "Creating GitHub release $tag ..."
		& gh release create $tag $zipPath --title "Eccentri City portable $tag" --notes $notes
		if ($LASTEXITCODE -ne 0) {
			throw "gh release create failed"
		}
	}
	& gh release view $tag --json url -q .url
}

function Build-ValidatedStage {
	if (-not $SkipTrackingCheck) {
		$track = Join-Path $Root "tools\check_tracking.ps1"
		Write-Step "Checking tracking policy..."
		& powershell -NoProfile -ExecutionPolicy Bypass -File $track -Root $Root
		if ($LASTEXITCODE -ne 0) {
			throw "Tracking check failed"
		}
	}

	$files = Get-ShipFiles
	if ($files.Count -lt 50) {
		throw "Ship file list suspiciously small ($($files.Count))"
	}
	New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
	Stage-FromGit $StageDir $files
	Ensure-Launcher $StageDir

	$dll = Join-Path $StageDir "addons\city_voxel\bin\city_voxel.dll"
	if (-not (Test-Path $dll)) {
		throw "city_voxel.dll missing after stage"
	}
	Assert-NoForbidden $StageDir

	# Engine lives in the source repo tools/godot (gitignored); copy into stage for import.
	$godotExe = Ensure-Engine $Root
	$stageGodotDir = Join-Path $StageDir "tools\godot"
	New-Item -ItemType Directory -Force -Path $stageGodotDir | Out-Null
	Copy-Item -Force $godotExe (Join-Path $stageGodotDir $GodotName)
	$stageGodot = Join-Path $stageGodotDir $GodotName

	Invoke-Import $StageDir $stageGodot
	Invoke-Validate $StageDir $stageGodot
	return $stageGodot
}

function Build-SlimFromStage {
	Write-Step "Building slim tree (no engine, no .godot) -> $SlimDir"
	Clear-Dir $SlimDir
	# Copy validated stage but drop caches / engine.
	$xd = @(
		(Join-Path $StageDir ".godot"),
		(Join-Path $StageDir "tools\godot")
	)
	$rcArgs = @(
		$StageDir, $SlimDir, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/nc", "/ns", "/np",
		"/XD"
	) + $xd + @("/R:2", "/W:2")
	& robocopy @rcArgs | Out-Null
	if ($LASTEXITCODE -ge 8) {
		throw "robocopy slim stage failed ($LASTEXITCODE)"
	}
	foreach ($dead in @(
		(Join-Path $SlimDir ".godot"),
		(Join-Path $SlimDir "tools\godot")
	)) {
		if (Test-Path $dead) {
			Remove-Item -Recurse -Force $dead
		}
	}
	Assert-NoForbidden $SlimDir
	$dll = Join-Path $SlimDir "addons\city_voxel\bin\city_voxel.dll"
	if (-not (Test-Path $dll)) {
		throw "slim package missing city_voxel.dll"
	}
}

# --- main ---
Write-Step "pack_release Mode=$Mode Root=$Root"

if ($Mode -eq "Check") {
	& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root "tools\check_tracking.ps1") -Root $Root
	exit $LASTEXITCODE
}

$null = Build-ValidatedStage

if ($Mode -eq "Folder") {
	Write-Step "Folder package ready: $StageDir"
	Write-Step "Done."
	exit 0
}

Build-SlimFromStage
Compress-Zip $SlimDir $ZipPath

if ($Mode -eq "Zip" -or $SkipUpload) {
	Write-Step "Zip ready: $ZipPath"
	Write-Step "Done."
	exit 0
}

# Publish
Publish-Release $ZipPath $Tag
Write-Step "Done."
exit 0
