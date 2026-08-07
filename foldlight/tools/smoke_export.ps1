param(
    [Parameter(Mandatory = $true)]
    [string]$ExePath,
    [Parameter(Mandatory = $true)]
    [string]$LogPath,
    [switch]$TestMode
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

function Get-DisplaySnapshot {
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $adapters = @(Get-CimInstance Win32_VideoController | ForEach-Object {
        [ordered]@{
            Name = $_.Name
            Width = $_.CurrentHorizontalResolution
            Height = $_.CurrentVerticalResolution
        }
    })
    return [ordered]@{
        PrimaryWidth = $bounds.Width
        PrimaryHeight = $bounds.Height
        Adapters = $adapters
    }
}

if (-not (Test-Path -LiteralPath $ExePath -PathType Leaf)) {
    throw "Export does not exist: $ExePath"
}

$resolvedExePath = (Resolve-Path -LiteralPath $ExePath).Path
$resolvedLogPath = if ([System.IO.Path]::IsPathRooted($LogPath)) {
    [System.IO.Path]::GetFullPath($LogPath)
} else {
    [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $LogPath))
}
$logDirectory = Split-Path -Parent $resolvedLogPath
if (-not [string]::IsNullOrWhiteSpace($logDirectory)) {
    New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
}

$before = Get-DisplaySnapshot
$arguments = @('--windowed', '--resolution', '1280x720', '--verbose', '--log-file', $resolvedLogPath)
if ($TestMode) {
    $arguments += @('--', '--test-mode')
}

$process = Start-Process -FilePath $resolvedExePath -ArgumentList $arguments -PassThru -WindowStyle Hidden
$startedAt = Get-Date
$samples = @()
for ($index = 0; $index -lt 10; $index++) {
    Start-Sleep -Milliseconds 800
    $process.Refresh()
    $samples += [ordered]@{
        ElapsedMs = [int]((Get-Date) - $startedAt).TotalMilliseconds
        HasExited = $process.HasExited
        Responding = if ($process.HasExited) { $false } else { $process.Responding }
        MainWindowHandle = if ($process.HasExited) { 0 } else { $process.MainWindowHandle.ToInt64() }
    }
    if ($process.HasExited) {
        break
    }
}

$process.Refresh()
$aliveAtGate = -not $process.HasExited
$respondingAtGate = $aliveAtGate -and $process.Responding
$windowAtGate = if ($aliveAtGate) { $process.MainWindowHandle.ToInt64() } else { 0 }
$after = Get-DisplaySnapshot

if ($aliveAtGate) {
    [void]$process.CloseMainWindow()
    if (-not $process.WaitForExit(2000)) {
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit()
    }
}

$result = [ordered]@{
    Exe = $resolvedExePath
    TestMode = [bool]$TestMode
    AliveAfterEightSeconds = $aliveAtGate
    RespondingAfterEightSeconds = $respondingAtGate
    MainWindowHandle = $windowAtGate
    ResolutionUnchanged = (($before.PrimaryWidth -eq $after.PrimaryWidth) -and ($before.PrimaryHeight -eq $after.PrimaryHeight))
    Before = $before
    After = $after
    Samples = $samples
    LogExists = Test-Path -LiteralPath $resolvedLogPath -PathType Leaf
}

$result | ConvertTo-Json -Depth 8
if (-not $aliveAtGate -or -not $respondingAtGate -or -not $result.ResolutionUnchanged) {
    exit 1
}
