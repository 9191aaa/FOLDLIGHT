$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$godotPath = 'G:\godot\Godot_v4.6.3-stable_win64.exe'

if (-not (Test-Path -LiteralPath $godotPath)) {
    throw "Godot executable not found: $godotPath"
}

Start-Process -FilePath $godotPath -ArgumentList @('--path', $projectPath)

