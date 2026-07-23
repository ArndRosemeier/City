# Bake Mixamo FBX in assets/humans/animations/mixamo/raw/ into mixamo_actions.tres
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$godotCandidates = @(
	Join-Path $root "tools\godot\Godot_v4.6-voxel_win64.exe",
	Join-Path $root "tools\godot\Godot_v4.6-stable_win64.exe"
)
$godot = $godotCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $godot) {
	Write-Error "Godot binary not found under tools/godot/. Place the voxel build there."
}

$raw = Join-Path $root "assets\humans\animations\mixamo\raw"
$fbx = @(Get-ChildItem -Path $raw -Include *.fbx,*.FBX,*.glb,*.gltf -File -ErrorAction SilentlyContinue)
if ($fbx.Count -eq 0) {
	Write-Host @"
No Mixamo files in:
  $raw

Download from https://www.mixamo.com/ (Adobe account):
  - Kick, Stomp (and any others you want)
  - FBX Binary, With Skin, In Place ON
Drop them into the raw folder, open the project once in the Godot editor
so FBX imports (humanoid BoneMap), then re-run this script.
"@
	exit 1
}

Write-Host "Using Godot: $godot"
Write-Host "Importing project assets (first open / reimport)…"
& $godot --headless --path $root --import
if ($LASTEXITCODE -ne 0) {
	Write-Warning "Godot --import exited $LASTEXITCODE (continuing to bake if resources exist)"
}

Write-Host "Baking Mixamo AnimationLibrary…"
& $godot --headless --path $root -s res://tools/bake_mixamo_library.gd
exit $LASTEXITCODE
