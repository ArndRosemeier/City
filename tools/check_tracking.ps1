# Assert every on-disk project file is either tracked or explicitly gitignored.
# Policy: track by default; exceptions must be listed in .gitignore.
# Exit 0 = clean, 1 = unexpected untracked / missing required ship files.
param(
	[string]$Root = ""
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$msg) {
	Write-Host $msg
}

function Assert-CommandSoft([string]$name) {
	if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
		throw "$name not found on PATH"
	}
}

if ([string]::IsNullOrWhiteSpace($Root)) {
	$Root = Split-Path -Parent $PSScriptRoot
}
$Root = (Resolve-Path $Root).Path

Push-Location $Root
try {
	Assert-CommandSoft "git"

	$untracked = @(git -c core.quotepath=false ls-files --others --exclude-standard)
	if ($untracked.Count -gt 0) {
		Write-Step "COMMIT REMINDER: unexpected untracked files block packaging/publish."
		Write-Step "Releases stage from git-tracked files only. Commit these, or add an explicit .gitignore rule:"
		$untracked | ForEach-Object { Write-Host ("  ?? " + $_) }
		Write-Step ""
		Write-Step "Suggested next steps:"
		Write-Step "  git add path/to/file"
		Write-Step "  git commit"
		Write-Step "  git push"
		Write-Step "  then re-run publish_portable_release.bat"
		exit 1
	}

	$required = @(
		"project.godot",
		"addons/city_voxel/bin/city_voxel.dll",
		"addons/city_voxel/city_voxel.gdextension",
		"scenes/city_poc.tscn",
		"tools/ensure_city_deps.ps1",
		"tools/validate_portable.gd",
		"tools/pack_release.ps1",
		"tools/check_tracking.ps1",
		"EccentriCity.bat"
	)
	$missing = @()
	foreach ($rel in $required) {
		git ls-files --error-unmatch $rel 2>$null | Out-Null
		if ($LASTEXITCODE -ne 0) {
			$missing += $rel
		}
	}
	if ($missing.Count -gt 0) {
		Write-Step "COMMIT REMINDER: required ship files are not tracked in git:"
		$missing | ForEach-Object { Write-Host ("  missing: " + $_) }
		Write-Step "Add and commit them before publishing."
		exit 1
	}

	$dll = Join-Path $Root "addons\city_voxel\bin\city_voxel.dll"
	if (-not (Test-Path $dll) -or ((Get-Item $dll).Length -lt 10KB)) {
		Write-Step "ERROR: city_voxel.dll missing or too small at $dll"
		exit 1
	}

	# Gameplay sources should carry a .uid (Godot 4 stable IDs).
	$src = @(git ls-files "*.gd" "*.gdshader" "*.gdextension")
	$lackUid = @()
	foreach ($f in $src) {
		$norm = $f -replace "\\", "/"
		if ($norm.StartsWith("tools/")) {
			continue
		}
		git ls-files --error-unmatch ($norm + ".uid") 2>$null | Out-Null
		if ($LASTEXITCODE -ne 0) {
			# Also accept an on-disk uid that simply isn't staged yet — caller should add it.
			$uidPath = Join-Path $Root (($norm + ".uid") -replace "/", "\")
			if (-not (Test-Path $uidPath)) {
				$lackUid += $norm
			}
			else {
				$lackUid += ($norm + " (uid exists on disk but is not tracked)")
			}
		}
	}
	if ($lackUid.Count -gt 0) {
		Write-Step "COMMIT REMINDER: tracked sources are missing tracked .uid sidecars:"
		$lackUid | ForEach-Object { Write-Host ("  " + $_) }
		Write-Step "Open the project once in Godot, then git-add the .uid files, commit, and push."
		exit 1
	}

	Write-Step "Tracking OK: no unexpected untracked files; required ship files present."
	exit 0
}
finally {
	Pop-Location
}
