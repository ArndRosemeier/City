# Pull latest mainline changes and rebuild Godot's global script class cache.
#
#   powershell -File .\pull.ps1
#   .\pull.bat
#
# After a big pull, stale class_name entries in .godot/global_script_class_cache.cfg
# break typed GDScript until the editor rescans. This always clears and regenerates that cache.
param(
	[string]$Root = ""
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$msg) {
	Write-Host $msg
}

if ([string]::IsNullOrWhiteSpace($Root)) {
	$Root = $PSScriptRoot
}
$Root = (Resolve-Path $Root).Path
$Godot = Join-Path $Root "tools\godot\Godot_v4.6-voxel_win64.exe"
$ClassCache = Join-Path $Root ".godot\global_script_class_cache.cfg"

Push-Location $Root
try {
	if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
		throw "git not found on PATH"
	}
	if (-not (Test-Path -LiteralPath $Godot)) {
		throw "Godot missing at $Godot (run tools\ensure_city_deps.ps1)"
	}

	$branch = (git rev-parse --abbrev-ref HEAD).Trim()
	if ([string]::IsNullOrWhiteSpace($branch) -or $branch -eq "HEAD") {
		throw "Detached HEAD - checkout a branch before pulling"
	}

	Write-Step "Fetching origin..."
	git fetch origin
	if ($LASTEXITCODE -ne 0) {
		throw "git fetch failed"
	}

	$remoteRef = "origin/$branch"
	git rev-parse --verify $remoteRef 2>$null | Out-Null
	if ($LASTEXITCODE -ne 0) {
		throw "No remote branch $remoteRef - push this branch first or set upstream"
	}

	## Untracked local files that the remote also adds will abort the merge; remove those
	## blockers (same situation as leftover castle *.png.import sidecars).
	$remoteFiles = @(git ls-tree -r --name-only $remoteRef)
	$remoteSet = [System.Collections.Generic.HashSet[string]]::new(
		[StringComparer]::OrdinalIgnoreCase
	)
	foreach ($rf in $remoteFiles) {
		[void]$remoteSet.Add(($rf -replace "\\", "/"))
	}
	$untracked = @(git -c core.quotepath=false ls-files --others --exclude-standard)
	foreach ($u in $untracked) {
		$norm = ($u -replace "\\", "/")
		if (-not $remoteSet.Contains($norm)) {
			continue
		}
		Write-Step "Removing untracked file that remote will bring: $norm"
		Remove-Item -LiteralPath (Join-Path $Root $u) -Force
	}

	Write-Step "Pulling $branch..."
	git pull --ff-only origin $branch
	if ($LASTEXITCODE -ne 0) {
		Write-Step "Fast-forward failed - trying merge pull..."
		git pull origin $branch
		if ($LASTEXITCODE -ne 0) {
			throw "git pull failed"
		}
	}

	Write-Step "Rebuilding Godot global script class cache..."
	if (Test-Path -LiteralPath $ClassCache) {
		Remove-Item -LiteralPath $ClassCache -Force
	}
	$outLog = Join-Path $env:TEMP ("city_pull_godot_" + [guid]::NewGuid().ToString("N") + ".log")
	$errLog = "$outLog.err"
	$p = Start-Process -FilePath $Godot -ArgumentList @(
		"--editor", "--path", $Root, "--quit-after", "10"
	) -Wait -PassThru -NoNewWindow -RedirectStandardOutput $outLog -RedirectStandardError $errLog
	if (-not (Test-Path -LiteralPath $ClassCache)) {
		if (Test-Path $errLog) {
			Get-Content $errLog | Select-Object -Last 40 | Write-Host
		}
		throw "Class cache was not regenerated (Godot exit $($p.ExitCode))"
	}

	Write-Step "Verifying scripts load..."
	$v = Start-Process -FilePath $Godot -ArgumentList @(
		"--headless", "--path", $Root, "--quit-after", "1"
	) -Wait -PassThru -NoNewWindow -RedirectStandardOutput $outLog -RedirectStandardError $errLog
	$errs = @()
	if (Test-Path $errLog) {
		$errs = @(Get-Content $errLog | Select-String -Pattern "Could not find type|Parse Error|Failed to load script")
	}
	Remove-Item -Force $outLog, $errLog -ErrorAction SilentlyContinue
	if ($errs.Count -gt 0) {
		$errs | Select-Object -First 20 | ForEach-Object { Write-Host $_ }
		throw "Script load still broken after class-cache rebuild (Godot exit $($v.ExitCode))"
	}

	Write-Step ("OK - on {0} @ {1}, class cache ready." -f $branch, (git rev-parse --short HEAD).Trim())
	exit 0
}
finally {
	Pop-Location
}
