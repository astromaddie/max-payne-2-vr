[CmdletBinding()]
param([string]$InputDirectory, [switch]$Restore)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (Get-Process -Name maxpayne2,vrserver,vrcompositor -ErrorAction SilentlyContinue) {
    throw 'Close Max Payne 2 and exit SteamVR, then run this again.'
}
if (!$InputDirectory) {
    $registryPath = Join-Path $env:LOCALAPPDATA 'openvr/openvrpaths.vrpath'
    if (!(Test-Path -LiteralPath $registryPath)) { throw 'Start SteamVR once, exit it, then run this again.' }
    $runtimePaths = (Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json).runtime
    foreach ($runtimePath in $runtimePaths) {
        $candidate = Join-Path $runtimePath 'drivers/indexcontroller/resources/input'
        if (Test-Path -LiteralPath (Join-Path $candidate 'index_controller_profile.json')) {
            $InputDirectory = $candidate
            break
        }
    }
    if (!$InputDirectory) { throw 'Could not find the Index controller files in the registered SteamVR runtime.' }
}
$inputRoot = (Resolve-Path -LiteralPath $InputDirectory).Path
$profilePath = Join-Path $inputRoot 'index_controller_profile.json'
$stockPath = Join-Path $inputRoot 'legacy_bindings_index_controller.json'
$editions = @(
    [pscustomobject]@{app_key='steam.app.12150'; binding_url='mp2vr_index_physical_clicks.json'},
    [pscustomobject]@{app_key='steam.app.210410'; binding_url='mp2vr_index_physical_clicks_de.json'}
)
$backupPath = Join-Path $inputRoot 'index_controller_profile.json.mp2vr-original'
$customPaths = @($editions | ForEach-Object { Join-Path $inputRoot $_.binding_url })
foreach ($path in (@($profilePath,$stockPath,$backupPath) + $customPaths)) {
    if ((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Refusing redirected binding file: $path"
    }
}
function Write-BindingJson([string]$Path, $Document) {
    if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path)) -ne $inputRoot) { throw 'Binding path escaped the Index input directory.' }
    $temporary = $Path + ".mp2vr-$PID.tmp"
    try {
        [IO.File]::WriteAllText($temporary, ($Document | ConvertTo-Json -Depth 100) + "`r`n", [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
    }
}
$profile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
if ($profile.controller_type -ne 'knuckles') { throw 'Unexpected controller profile; expected Valve Index (knuckles).' }
$defaultsProperty = $profile.PSObject.Properties['default_bindings']
$defaults = if ($defaultsProperty) { @($defaultsProperty.Value) } else { @() }
function Test-OwnedOverride($Entry) {
    foreach ($edition in $editions) {
        if ($Entry.app_key -eq $edition.app_key -and $Entry.binding_url -eq $edition.binding_url) { return $true }
    }
    return $false
}
if ($Restore) {
    $existing = @($defaults | Where-Object { Test-OwnedOverride $_ })
    if ($existing.Count -eq 0) { Write-Output 'The MP2VR Index controls override is already disabled.'; exit 0 }
    $remaining = @($defaults | Where-Object { !(Test-OwnedOverride $_) })
    if ($remaining.Count -eq 0) { $profile.PSObject.Properties.Remove('default_bindings') }
    else { $profile.default_bindings = $remaining }
    Write-BindingJson $profilePath $profile
    Write-Output 'Removed MP2VR Index overrides for standard/German Steam editions. Restart SteamVR. Other bindings were preserved.'
    exit 0
}
# Validate both editions before changing any files, including an existing v1/v2 fix.
foreach ($edition in $editions) {
    $existing = @($defaults | Where-Object { $_.app_key -eq $edition.app_key })
    if ($existing.Count -gt 1 -or ($existing.Count -eq 1 -and $existing[0].binding_url -ne $edition.binding_url)) {
        throw "A different Max Payne 2 driver-default binding already exists for $($edition.app_key). It was preserved; remove that override before applying this fix."
    }
}
$binding = Get-Content -LiteralPath $stockPath -Raw | ConvertFrom-Json
if ($binding.controller_type -ne 'knuckles') { throw 'Unexpected Index legacy binding format.' }
$legacy = $binding.bindings.PSObject.Properties['/actions/legacy'].Value
foreach ($hand in @('left','right')) {
    $stick = "/user/hand/$hand/input/thumbstick"
    $press = "/actions/legacy/in/${hand}_axis0_press"
    $physicalCount = 0
    foreach ($source in $legacy.sources) {
        $click = $source.inputs.PSObject.Properties['click']
        if (!$click -or $click.Value.output -ne $press) { continue }
        # Valve's default merges position-threshold buttons and trackpad
        # clicks with the physical stick click. Retain only the latter.
        $physical = $source.path -eq $stick -and $source.mode -eq 'joystick'
        if ($physical) {
            $parameters = $source.PSObject.Properties['parameters']
            if ($parameters -and @($parameters.Value.PSObject.Properties).Count -ne 0) {
                throw 'The native joystick has new parameters; review them before applying this fix.'
            }
            $physicalCount++
        } else {
            $source.inputs.PSObject.Properties.Remove('click')
        }
    }
    if ($physicalCount -ne 1) { throw "Expected exactly one physical $hand thumbstick click route." }

    # Valve's legacy defaults treat physical A as an extra grip button.
    # MP2VR uses the separate A channel for jump (right) / painkiller (left).
    $aSources = @($legacy.sources | Where-Object { $_.path -eq "/user/hand/$hand/input/a" })
    if ($aSources.Count -ne 1 -or $aSources[0].mode -ne 'button') {
        throw "Expected exactly one physical $hand A button source."
    }
    $aSource = $aSources[0]
    $aClick = $aSource.inputs.PSObject.Properties['click']
    if (!$aClick -or $aClick.Value.output -notin @("/actions/legacy/in/${hand}_grip_press", "/actions/legacy/in/${hand}_a_press")) {
        throw "Unexpected $hand A button click route; review it before applying this fix."
    }
    $aClick.Value.output = "/actions/legacy/in/${hand}_a_press"
    $aTouch = $aSource.inputs.PSObject.Properties['touch']
    if ($aTouch) {
        if ($aTouch.Value.output -notin @("/actions/legacy/in/${hand}_grip_touch", "/actions/legacy/in/${hand}_a_touch")) {
            throw "Unexpected $hand A button touch route; review it before applying this fix."
        }
        $aTouch.Value.output = "/actions/legacy/in/${hand}_a_touch"
    }
    $gripSources = @($legacy.sources | Where-Object {
        $_.path -eq "/user/hand/$hand/input/grip" -and
        $_.inputs.PSObject.Properties['click'] -and
        $_.inputs.click.output -eq "/actions/legacy/in/${hand}_grip_press"
    })
    if ($gripSources.Count -eq 0) { throw "Missing physical $hand squeeze-to-grab route." }
}
# Drop empty sources; preserve all remaining axes, triggers, physical grip, B buttons,
# poses, haptics, and the separate legacy_mirrored action set as supplied locally.
$legacy.sources = @($legacy.sources | Where-Object { @($_.inputs.PSObject.Properties).Count -gt 0 })
$binding.name = 'Max Payne 2 VR - Index controls v3'
$profile | Add-Member -NotePropertyName default_bindings -NotePropertyValue (@($defaults | Where-Object { $_.app_key -notin $editions.app_key }) + $editions) -Force

# Write the standalone binding first: failure cannot leave a profile pointing
# at a missing file. Keep a byte-for-byte backup of the original profile.
if (!(Test-Path -LiteralPath $backupPath)) { Copy-Item -LiteralPath $profilePath -Destination $backupPath }
foreach ($edition in $editions) {
    # Each file must identify the same app as its profile entry. The DE release
    # runs under a different Steam app ID, so the standard override cannot apply.
    $binding | Add-Member -NotePropertyName app_key -NotePropertyValue $edition.app_key -Force
    $customPath = Join-Path $inputRoot $edition.binding_url
    Write-BindingJson $customPath $binding
}
Write-BindingJson $profilePath $profile
Write-Output 'Index fix installed for Max Payne 2. Restart SteamVR, then start the game from Steam.'
Write-Output "Index controls v3: standard Steam (12150) and German Steam (210410). Profile: $profilePath"
Write-Output 'Stick movement now moves/turns; physical L3/R3 clicks control shoot-dodge/bullet time.'
Write-Output 'Right A jumps; left A uses painkillers when enabled. Squeeze the controller to grab.'
Write-Output 'If you selected a custom SteamVR binding before, select Default for Max Payne 2.'
