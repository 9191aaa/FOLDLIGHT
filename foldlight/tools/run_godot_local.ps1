param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$GodotArgs
)

$ErrorActionPreference = 'Stop'

# Keep Godot's editor/test caches, logs, and project user:// data inside the
# workspace. Codex may write here without requesting access to the Windows
# account directories. This wrapper is for development commands only; exported
# builds still use the player's normal per-user save location.
$projectRoot = Split-Path -Parent $PSScriptRoot
$runtimeRoot = Join-Path $projectRoot '.codex-runtime'
$roamingRoot = Join-Path $runtimeRoot 'AppData\Roaming'
$localRoot = Join-Path $runtimeRoot 'AppData\Local'

[void](New-Item -ItemType Directory -Force -Path $roamingRoot)
[void](New-Item -ItemType Directory -Force -Path $localRoot)

$env:APPDATA = $roamingRoot
$env:LOCALAPPDATA = $localRoot

$godot = 'G:\godot\Godot_v4.6.3-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $godot -PathType Leaf)) {
    throw "Godot executable not found: $godot"
}

& $godot @GodotArgs
exit $LASTEXITCODE
