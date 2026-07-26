param(
	[Parameter(Mandatory = $true)]
	[string] $InstallDir,
	[int] $Attempts = 30,
	[int] $DelayMs = 1000
)

$cacheDir = Join-Path $InstallDir ".godot"
$classCache = Join-Path $cacheDir "global_script_class_cache.cfg"
$imported = Join-Path $cacheDir "imported"

for ($i = 1; $i -le $Attempts; $i++) {
	if ((Test-Path -LiteralPath $classCache) -and (Test-Path -LiteralPath $imported)) {
		Write-Host ("import artifacts OK after try {0}: {1}" -f $i, $InstallDir)
		exit 0
	}
	Start-Sleep -Milliseconds $DelayMs
}

Write-Host ("import artifacts MISSING under: {0}" -f $InstallDir)
if (Test-Path -LiteralPath $cacheDir) {
	Write-Host "cache dir entries:"
	Get-ChildItem -LiteralPath $cacheDir | ForEach-Object { Write-Host ("  " + $_.Name) }
} else {
	Write-Host "cache dir does not exist"
}
exit 1
