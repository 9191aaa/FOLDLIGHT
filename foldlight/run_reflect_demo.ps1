$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$scene = 'res://rebuild/scenes/boss_lab.tscn'
if (Get-Command godot -ErrorAction SilentlyContinue) {
  & godot --path . $scene
  exit $LASTEXITCODE
}
if (Get-Command godot4 -ErrorAction SilentlyContinue) {
  & godot4 --path . $scene
  exit $LASTEXITCODE
}
Write-Host 'Godot 4.6+ was not found in PATH.' -ForegroundColor Yellow
Write-Host 'Open foldlight/project.godot in Godot and run rebuild/scenes/boss_lab.tscn (F6).'
exit 1
