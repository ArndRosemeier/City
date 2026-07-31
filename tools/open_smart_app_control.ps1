# Open the Windows Smart App Control settings page.
#
# Smart App Control (SAC) blocks unsigned DLLs such as city_voxel.dll when it is
# On. Microsoft does not allow a normal script to flip that switch - once On, the
# only supported way to turn it Off is this settings page (and Off is usually
# permanent until a reset). So this tool diagnoses and opens the dialog; it does
# not change the policy itself.
#
#   powershell -File tools\open_smart_app_control.ps1
#   powershell -File tools\open_smart_app_control.ps1 -CheckOnly
#   tools\OpenSmartAppControl.bat
#
# -CheckOnly exit codes (for EccentriCity.bat):
#   0 = Off, Evaluation, or not present (safe to launch)
#   2 = On / enforcement (unsigned city_voxel.dll will be blocked)
param(
	# Open the page even when SAC looks Off / absent (useful if the registry lag).
	[switch]$Force,
	# Print the state and exit without opening Settings. See exit codes above.
	[switch]$CheckOnly
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$msg) {
	Write-Host $msg
}

## SAC state from the Code Integrity policy key. Missing key = feature absent
## (Windows 10, or a SKU without SAC). Values match what Windows writes today:
##   VerifiedAndReputablePolicyState 0 = Off, 1 = On, 2 = Evaluation.
function Get-SmartAppControlState {
	$path = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy"
	if (-not (Test-Path -LiteralPath $path)) {
		return [pscustomobject]@{
			Present = $false
			State = -1
			Label = "not present"
		}
	}
	$raw = (Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue).VerifiedAndReputablePolicyState
	if ($null -eq $raw) {
		return [pscustomobject]@{
			Present = $false
			State = -1
			Label = "not present"
		}
	}
	$state = [int]$raw
	$label = switch ($state) {
		0 { "Off" }
		1 { "On (enforcement - unsigned DLLs are blocked)" }
		2 { "Evaluation (learning; usually allows unsigned code)" }
		default { "unknown ($state)" }
	}
	return [pscustomobject]@{
		Present = $true
		State = $state
		Label = $label
	}
}

function Open-Uri([string]$uri) {
	## explorer.exe handles ms-settings: / windowsdefender://. Do not -Wait: its exit
	## code is meaningless for protocol launches, and waiting can hang on some builds.
	Start-Process -FilePath "explorer.exe" -ArgumentList $uri -ErrorAction Stop | Out-Null
	return $true
}

$sac = Get-SmartAppControlState
Write-Step "Smart App Control: $($sac.Label)"

if ($CheckOnly) {
	if ($sac.Present -and $sac.State -eq 1) {
		exit 2
	}
	exit 0
}

if (-not $sac.Present) {
	Write-Step "This Windows install does not expose Smart App Control - nothing to open."
	Write-Step "If city_voxel.dll still fails to load, look in Windows Security -> App & browser control."
	if (-not $Force) {
		exit 0
	}
}

if ($sac.State -eq 0 -and -not $Force) {
	Write-Step "SAC is already Off. Re-run with -Force to open the settings page anyway."
	exit 0
}

if ($sac.State -eq 1) {
	Write-Step ""
	Write-Step "Eccentri City ships an unsigned city_voxel.dll. With SAC On, Windows blocks"
	Write-Step "Godot from loading it (Error 4551), which looks like every native type is missing."
	Write-Step ""
	Write-Step "In the window that opens: set Smart App Control to Off."
	Write-Step "(Microsoft usually will not let you turn it back On without resetting the PC.)"
	Write-Step ""
}

## Deepest link first; fall back if this build of Windows Security dropped the page.
$uris = @(
	"windowsdefender://smartapp/",
	"windowsdefender://appbrowser",
	"ms-settings:windowsdefender"
)
$opened = $false
foreach ($uri in $uris) {
	Write-Step "Opening $uri ..."
	try {
		if (Open-Uri $uri) {
			$opened = $true
			break
		}
	}
	catch {
		Write-Step ("  failed: " + $_.Exception.Message)
	}
}

if (-not $opened) {
	Write-Step "ERROR: could not open Windows Security. Open Settings manually:"
	Write-Step "  Privacy & security -> Windows Security -> App & browser control -> Smart App Control"
	exit 1
}

Write-Step "Done - pick Off in the Smart App Control page, then relaunch EccentriCity.bat."
exit 0
