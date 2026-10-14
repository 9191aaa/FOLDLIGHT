param(
    [string]$GodotPath = 'godot',
    [switch]$All,
    [string[]]$SelectedTests = @(),
    [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
$engine = (Get-Command $GodotPath -ErrorAction Stop).Source
$resultsPath = Join-Path $projectPath 'build/refactor-checks'
[void](New-Item -ItemType Directory -Force -Path $resultsPath)
[void](New-Item -ItemType File -Force -Path (Join-Path $projectPath 'build/.gdignore'))
$oldAppData = $env:APPDATA
$oldLocalAppData = $env:LOCALAPPDATA
$runId = [guid]::NewGuid().ToString('N')

function Invoke-Check([string]$Name, [string[]]$EngineArguments) {
    $runtimePath = Join-Path $resultsPath ('userdata/' + $runId + '/' + $Name)
    $env:APPDATA = Join-Path $runtimePath 'Roaming'
    $env:LOCALAPPDATA = Join-Path $runtimePath 'Local'
    [void](New-Item -ItemType Directory -Force -Path $env:APPDATA, $env:LOCALAPPDATA)
    $stdout = Join-Path $resultsPath ($Name + '.log')
    $stderr = Join-Path $resultsPath ($Name + '.errors.log')
    $arguments = @('--headless', '--path', ('"' + $projectPath + '"')) + $EngineArguments
    $process = Start-Process -FilePath $engine -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $completed = $process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $completed) {
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit()
    }
    $errors = @(Select-String -Path $stdout, $stderr -Pattern 'SCRIPT ERROR|Parse Error|\[FAIL\]|: FAIL|^ERROR:' -ErrorAction SilentlyContinue)
    $passed = $completed -and $process.ExitCode -eq 0 -and $errors.Count -eq 0
    Write-Host ('[{0}] {1}' -f $(if ($passed) { 'PASS' } else { 'FAIL' }), $Name)
    if (-not $passed) { $errors | Select-Object -First 4 | ForEach-Object { Write-Host $_.Line } }
    return [pscustomobject]@{ Name = $Name; Passed = $passed; ExitCode = $process.ExitCode; TimedOut = -not $completed; Log = $stdout }
}

try {
    $results = @()
    $results += Invoke-Check 'import' @('--editor', '--import', '--quit')
    if (-not $results[0].Passed) { throw 'Godot import failed; see build/refactor-checks/import.errors.log.' }
    $testNames = @(
        'test_unified_endless_pause',
        'test_unified_story_navigation',
        'test_unified_presentation',
        'test_input_contract_3_0',
        'test_player_combat_3_0',
        'test_rogue_session_3_0',
        'test_prologue_pause_ui_3_0',
        'test_quick_tutorial_overlay_3_4',
        'test_combat_ui_teaching_3_7',
        'test_endless_title_flow_3_7',
        'test_reward_modal_safety_3_4_3',
        'test_reflection_pathing_3_7',
        'test_return_relay_3_8',
        'test_player_hit_reaction_3_5_1',
        'test_enemy_hit_feedback_3_4_1',
        'test_region_visual_layers_3_3',
        'test_formal_art_feedback_pass_3_6',
        'test_two_hour_campaign',
        'test_campaign_fixed_step_route',
        'test_challenge_tutorial_passive',
        'test_full_rogue_route_3_0',
        'test_endless_mission_reward_lanes_3_9',
        'test_endless_2_0_runtime_reuse',
        'test_interactive_route_atlas',
        'test_reward_card_motion',
        'test_tide_beacon_exploration',
        'test_rogue_checkpoint_stages_3_0',
        'test_rogue_pressure_curve',
        'test_boss_fairness_4_0',
        'test_weapon_volley_accuracy',
        'test_terrain_context_hint',
        'test_temporary_hazard_pause'
    )
    if ($SelectedTests.Count -gt 0) {
        foreach ($selected in $SelectedTests) {
            if ($selected -notmatch '^test_[a-zA-Z0-9_]+$' -or -not (Test-Path -LiteralPath (Join-Path $projectPath ('tests/integration/' + $selected + '.gd')))) {
                throw ('Unknown integration test: ' + $selected)
            }
        }
        $testNames = $SelectedTests
    } elseif ($All) {
        $testNames = @(Get-ChildItem -LiteralPath (Join-Path $projectPath 'tests/integration') -Filter 'test_*.gd' | ForEach-Object { $_.BaseName })
    }
    foreach ($testName in $testNames) {
        $results += Invoke-Check $testName @('--script', ('res://tests/integration/' + $testName + '.gd'))
    }
    $results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $resultsPath 'results.json') -Encoding utf8
    $failed = @($results | Where-Object { -not $_.Passed })
    Write-Host ('{0}/{1} checks passed. Logs: {2}' -f ($results.Count - $failed.Count), $results.Count, $resultsPath)
    if ($failed.Count -gt 0) { exit 1 }
} finally {
    $env:APPDATA = $oldAppData
    $env:LOCALAPPDATA = $oldLocalAppData
}
