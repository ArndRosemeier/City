# Run Godot test scenes headless behind a hard timeout.
#
# A hung headless Godot never releases addons/city_voxel/bin/city_voxel.dll (a GDExtension
# stays loaded for the process lifetime), so an unbounded test run blocks every later DLL
# build as well as itself. Everything here exists to make that impossible: the process is
# waited on for a bounded time, killed when it overruns, and reported as TIMEOUT.
#
# Exit 0 = every scene printed RESULT: OK, 1 = a scene failed, 2 = a scene was killed.
#
#   powershell -File tools\run_test.ps1 test_ped_nav
#   powershell -File tools\run_test.ps1 test_nav_bake test_nav_links -TimeoutSec 300
#   powershell -File tools\run_test.ps1 test_ped_nav -KeepLog
#   powershell -File tools\run_test.ps1 shot_ped_crowd -Rendered -GodotArgs "--spawn-district=0,0"
param(
	# Position 0 is declared so -TimeoutSec stays named-only and a bare scene list after it
	# cannot be swallowed as an integer.
	[Parameter(Position = 0, Mandatory = $true, ValueFromRemainingArguments = $true)]
	[string[]]$Scene,
	# The whole nav suite runs in about half a minute, so anything past this is hung, not slow.
	[Parameter()][int]$TimeoutSec = 180,
	[Parameter()][switch]$KeepLog,
	# Screenshot tools need a real renderer, and the district bake waits on is_area_editable,
	# which never becomes true headless. Same hang guard, window instead of --headless.
	[Parameter()][switch]$Rendered,
	# Passed through to Godot after the scene path, for scenes that read CityRoot's own flags
	# such as --spawn-district=x,z.
	[Parameter()][string[]]$GodotArgs = @()
)

$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Split-Path -Parent $PSScriptRoot)).Path
$Godot = Join-Path $Root "tools\godot\Godot_v4.6-voxel_win64.exe"
if (-not (Test-Path $Godot)) {
	Write-Host "ERROR: no Godot at $Godot (run tools\ensure_city_deps.ps1)"
	exit 1
}

# tools\*.log and tools\*.err are gitignored, so runs leave nothing to clean up in the repo.
function Get-SceneName([string]$raw) {
	$name = $raw -replace "^res://", "" -replace "\\", "/"
	$name = ($name -split "/")[-1]
	return $name -replace "\.tscn$", ""
}

$results = @()
$worst = 0

Push-Location $Root
try {
	foreach ($raw in $Scene) {
		$name = Get-SceneName $raw
		$scenePath = Join-Path $Root "tools\$name.tscn"
		if (-not (Test-Path $scenePath)) {
			Write-Host "ERROR: no scene at $scenePath"
			exit 1
		}
		$log = Join-Path $Root "tools\$name.log"
		$err = Join-Path $Root "tools\$name.err"
		Write-Host "--- $name (timeout ${TimeoutSec}s)"
		$clock = [System.Diagnostics.Stopwatch]::StartNew()
		$godotArgs = @("--path", ".", "res://tools/$name.tscn") + $GodotArgs
		if (-not $Rendered) {
			$godotArgs = @("--headless") + $godotArgs
		}
		$proc = Start-Process -FilePath $Godot -ArgumentList $godotArgs `
			-NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError $err
		$exited = $proc.WaitForExit($TimeoutSec * 1000)
		if (-not $exited) {
			$proc.Kill()
		}
		# The bounded overload returns as soon as the process is gone; the parameterless one
		# also waits for the redirected streams to flush, so the log is complete when read.
		$proc.WaitForExit()
		$clock.Stop()
		$secs = [math]::Round($clock.Elapsed.TotalSeconds, 1)

		$stdout = if (Test-Path $log) { @(Get-Content -LiteralPath $log) } else { @() }
		$stderr = if (Test-Path $err) { @(Get-Content -LiteralPath $err) } else { @() }
		# The scene's own RESULT: line is the verdict. Godot's exit code is not readable
		# through Start-Process -PassThru with redirected streams, and a scene that died
		# before printing anything shows up as a missing line, which is the same failure.
		$resultLine = @($stdout | Where-Object { $_ -match "^RESULT:" })
		$verdict = ""
		$code = 0
		if (-not $exited) {
			$verdict = "TIMEOUT_KILLED after ${TimeoutSec}s"
			$code = 2
		}
		elseif ($resultLine.Count -eq 0) {
			$verdict = "NO RESULT LINE - the scene died before it judged itself"
			$code = 1
		}
		else {
			$verdict = $resultLine[-1]
			if ($verdict -ne "RESULT: OK") {
				$code = 1
			}
		}
		Write-Host ("    {0}  [{1}s]" -f $verdict, $secs)
		if ($code -ne 0) {
			# The failure is in the log the test just wrote, so put it where it is read.
			$stdout | Select-Object -Last 40 | ForEach-Object { Write-Host ("    | " + $_) }
			$stderr | Where-Object { $_ -ne "" } | Select-Object -Last 40 |
				ForEach-Object { Write-Host ("    ! " + $_) }
			Write-Host "    logs: $log / $err"
			$worst = [math]::Max($worst, $code)
		}
		elseif (-not $KeepLog) {
			Remove-Item -LiteralPath $log, $err -ErrorAction SilentlyContinue
		}
		$results += [pscustomobject]@{ Scene = $name; Verdict = $verdict; Seconds = $secs }
	}

	if ($results.Count -gt 1) {
		Write-Host ""
		Write-Host "=== summary"
		foreach ($r in $results) {
			Write-Host ("    {0,-28} {1,6}s  {2}" -f $r.Scene, $r.Seconds, $r.Verdict)
		}
	}
	exit $worst
}
finally {
	Pop-Location
}
