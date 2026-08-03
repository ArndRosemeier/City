# Stage tracked changes, commit, and push the current branch.
#
#   powershell -File .\push.ps1 "Commit message here"
#   .\push.bat "Commit message here"
#   powershell -File .\push.ps1 "msg" -Untracked   # also git-add untracked (gitignore still applies)
#
# Does not amend, force-push, or skip hooks. Refuses an empty commit message.
param(
	[Parameter(Mandatory = $true, Position = 0)]
	[string]$Message,
	[switch]$Untracked,
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
$Message = $Message.Trim()
if ([string]::IsNullOrWhiteSpace($Message)) {
	throw "Commit message is required"
}

Push-Location $Root
try {
	if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
		throw "git not found on PATH"
	}

	$branch = (git rev-parse --abbrev-ref HEAD).Trim()
	if ([string]::IsNullOrWhiteSpace($branch) -or $branch -eq "HEAD") {
		throw "Detached HEAD - checkout a branch before pushing"
	}

	Write-Step "Working tree:"
	git status -sb
	Write-Step ""

	if ($Untracked) {
		Write-Step "Staging tracked updates + untracked files (gitignore respected)..."
		git add -A
	}
	else {
		Write-Step "Staging tracked updates only (pass -Untracked to include new files)..."
		git add -u
	}
	if ($LASTEXITCODE -ne 0) {
		throw "git add failed"
	}

	## Keep Windows DLL lock copies and local probe dumps out even if somehow staged.
	$blocked = @(
		git diff --cached --name-only |
			Where-Object {
				$_ -match '(^|/|\\)~city_voxel\.dll' -or
				$_ -match '(^|/|\\)tools[/\\].*\.(txt|log|err)$'
			}
	)
	if ($blocked.Count -gt 0) {
		Write-Step "Unstaging blocked junk:"
		$blocked | ForEach-Object { Write-Host ("  " + $_); git restore --staged -- $_ }
	}

	$staged = @(git diff --cached --name-only)
	if ($staged.Count -eq 0) {
		Write-Step "Nothing staged to commit."
	}
	else {
		Write-Step ("Committing {0} path(s)..." -f $staged.Count)
		$staged | ForEach-Object { Write-Host ("  " + $_) }
		## PowerShell here-string keeps the message literal (no bash HEREDOC).
		git commit -m @"
$Message
"@
		if ($LASTEXITCODE -ne 0) {
			throw "git commit failed"
		}
	}

	$ahead = 0
	git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null | Out-Null
	if ($LASTEXITCODE -eq 0) {
		$counts = (git rev-list --left-right --count "HEAD...@{u}").Trim() -split "\s+"
		if ($counts.Count -ge 1) {
			$ahead = [int]$counts[0]
		}
	}
	else {
		## No upstream yet - always push -u.
		$ahead = 1
	}

	if ($ahead -le 0 -and $staged.Count -eq 0) {
		Write-Step "Already up to date with upstream - nothing to push."
		exit 0
	}

	Write-Step "Pushing $branch..."
	git push -u origin HEAD
	if ($LASTEXITCODE -ne 0) {
		throw "git push failed"
	}

	Write-Step ("OK - pushed {0} @ {1}" -f $branch, (git rev-parse --short HEAD).Trim())
	exit 0
}
finally {
	Pop-Location
}
