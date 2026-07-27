# Deprecated entrypoint — use tools/pack_release.ps1.
# Kept so older docs/scripts keep working.
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

$pack = Join-Path $PSScriptRoot "pack_release.ps1"
$packArgs = @{
	Root = $Root
	Mode = "Publish"
}
if (-not [string]::IsNullOrWhiteSpace($Tag)) {
	$packArgs["Tag"] = $Tag
}
if ($SkipUpload) {
	$packArgs["SkipUpload"] = $true
	$packArgs["Mode"] = "Zip"
}
# RebuildPortable is obsolete: Folder mode always validates from git.
& $pack @packArgs
exit $LASTEXITCODE
