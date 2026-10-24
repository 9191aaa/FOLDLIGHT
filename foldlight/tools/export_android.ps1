param(
    [string]$OutputPath = 'build/FOLDLIGHT_Android/FOLDLIGHT.apk',
    [string]$GodotPath = 'G:/godot/Godot_v4.6.3-stable_win64_console.exe'
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$toolchainRoot = Join-Path $projectRoot 'build/toolchain'
$jdkRoot = Get-ChildItem -LiteralPath $toolchainRoot -Directory -Filter 'jdk-17*' | Select-Object -First 1
if ($null -eq $jdkRoot) { throw 'Install the official JDK 17 under build/toolchain first.' }
$env:JAVA_HOME = $jdkRoot.FullName
$env:ANDROID_HOME = Join-Path $toolchainRoot 'android-sdk'
$env:PATH = (Join-Path $env:JAVA_HOME 'bin') + ';' + $env:PATH
$env:APPDATA = Join-Path $projectRoot 'build/test-runtime/web-export/Roaming'
$env:LOCALAPPDATA = Join-Path $projectRoot 'build/test-runtime/android-export/Local'
$signingRoot = Join-Path $projectRoot 'build/signing'
New-Item -ItemType Directory -Path $signingRoot -Force | Out-Null
$keystorePath = Join-Path $signingRoot 'foldlight-release.keystore'
$passwordPath = Join-Path $signingRoot 'foldlight-password.dpapi'
if ((Test-Path -LiteralPath $keystorePath) -and !(Test-Path -LiteralPath $passwordPath)) {
    throw 'The release keystore exists but its local protected password is missing. Restore the pair; do not generate a replacement key.'
}
if (!(Test-Path -LiteralPath $passwordPath)) {
    $secretBytes = New-Object byte[] 36
    [Security.Cryptography.RandomNumberGenerator]::Fill($secretBytes)
    $secret = [Convert]::ToBase64String($secretBytes)
    $secret | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString | Set-Content -LiteralPath $passwordPath
    $secret = $null
}
$securePassword = Get-Content -LiteralPath $passwordPath | ConvertTo-SecureString
$credential = New-Object System.Net.NetworkCredential('', $securePassword)
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = $keystorePath
$env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = 'foldlight'
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $credential.Password
try {
    if (!(Test-Path -LiteralPath $keystorePath)) {
        & (Join-Path $env:JAVA_HOME 'bin/keytool.exe') -genkeypair -keystore $keystorePath -storepass:env GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD -keypass:env GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD -alias foldlight -keyalg RSA -keysize 3072 -validity 10000 -dname 'CN=FOLDLIGHT, OU=Game, O=Paper Sea, C=CN' -noprompt
        if ($LASTEXITCODE -ne 0) { throw 'Release keystore generation failed.' }
    }
    $editorSettingsPath = Join-Path $env:APPDATA 'Godot/editor_settings-4.6.tres'
    $settings = if (Test-Path -LiteralPath $editorSettingsPath) { Get-Content -LiteralPath $editorSettingsPath -Raw } else { "[gd_resource type=`"EditorSettings`" format=3]`n`n[resource]`n" }
    foreach ($entry in @{'export/android/java_sdk_path'=$env:JAVA_HOME; 'export/android/android_sdk_path'=$env:ANDROID_HOME}.GetEnumerator()) {
        $line = $entry.Key + ' = "' + $entry.Value.Replace('\', '/') + '"'
        $pattern = '(?m)^' + [regex]::Escape($entry.Key) + ' = .*\r?\n?'
        $settings = [regex]::Replace($settings, $pattern, '')
        $settings += "`n" + $line + "`n"
    }
    [IO.File]::WriteAllText($editorSettingsPath, $settings, [Text.UTF8Encoding]::new($false))
    $target = if ([IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $projectRoot $OutputPath }
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
    & $GodotPath --headless --path $projectRoot --export-release 'Android' $target
    if ($LASTEXITCODE -ne 0) { throw 'Android export failed.' }
    & (Join-Path $env:ANDROID_HOME 'build-tools/35.0.1/apksigner.bat') verify --verbose $target
    if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed.' }
    Get-Item -LiteralPath $target | Select-Object FullName, Length
} finally {
    Remove-Item Env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD -ErrorAction SilentlyContinue
    $credential = $null
    $securePassword = $null
}
