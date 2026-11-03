<#
.SYNOPSIS
  Runs the headless smoke test (res://tests/smoke_all.tscn) under a watchdog.

.DESCRIPTION
  Usage:
    powershell -ExecutionPolicy Bypass -File tests\run_smoke.ps1 [GODOT]

  GODOT is the path to a Godot 4.6 binary. Prefer the *_console.exe build so
  output is captured. Falls back to $env:GODOT, then godot_console / godot on PATH.

  Environment (all optional):
    SMOKE_TIMEOUT    watchdog seconds (default 90). The run is killed after this.
    SMOKE_SCENE      scene to run (default res://tests/smoke_all.tscn).
    SMOKE_MARKER     line that must appear in the output (default SMOKE_ALL_OK).
                     For the laser stress test:
                       $env:SMOKE_SCENE='res://tests/laser_stress.tscn'; $env:SMOKE_MARKER='STRESS_OK'
    SMOKE_LOG        where to write the full log (default: a temp file, path printed).
    SMOKE_KEEP_DATA  1 to keep the throwaway user data dir after the run.

  The run points APPDATA at a fresh, throwaway folder, so your real settings.tres,
  Twitch tokens, users and nivek relay cursor are never touched.

  Exit code: 0 only if the marker line appears and Godot exits 0;
             124 on watchdog timeout; otherwise nonzero.
#>
param([string]$Godot = "")

$ErrorActionPreference = "Stop"

$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Scene = if ($env:SMOKE_SCENE) { $env:SMOKE_SCENE } else { "res://tests/smoke_all.tscn" }
$Marker = if ($env:SMOKE_MARKER) { $env:SMOKE_MARKER } else { "SMOKE_ALL_OK" }
$Timeout = if ($env:SMOKE_TIMEOUT) { [int]$env:SMOKE_TIMEOUT } else { 90 }

if (-not $Godot) { $Godot = $env:GODOT }
if (-not $Godot) {
    foreach ($candidate in @("godot_console", "godot4", "godot")) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) { $Godot = $cmd.Source; break }
    }
}
if (-not $Godot) {
    Write-Error "run_smoke: no Godot found. Pass the binary as argument 1 or set `$env:GODOT."
    exit 2
}

$Data = Join-Path ([System.IO.Path]::GetTempPath()) ("rso-smoke-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Path $Data | Out-Null
$Log = if ($env:SMOKE_LOG) { $env:SMOKE_LOG } else { Join-Path ([System.IO.Path]::GetTempPath()) ("rso-smoke-log-" + [guid]::NewGuid().ToString("N").Substring(0, 8) + ".txt") }
Set-Content -Path $Log -Value "" -Encoding UTF8

function Quote-Arg([string]$a) {
    if ($a -match '[\s"]') { return '"' + ($a -replace '"', '\"') + '"' }
    return $a
}

# Runs Godot with $GodotArgs under a watchdog. Output is shown and appended to
# $Log. Returns the exit code, or 124 on timeout.
function Invoke-Watchdog([string[]]$GodotArgs, [int]$Seconds) {
    $out = "$Log.stdout"
    $err = "$Log.stderr"
    $argLine = ($GodotArgs | ForEach-Object { Quote-Arg $_ }) -join " "
    $p = Start-Process -FilePath $Godot -ArgumentList $argLine -NoNewWindow -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err
    $null = $p.Handle # cache the handle so ExitCode is available later
    $timedOut = -not $p.WaitForExit($Seconds * 1000)
    if ($timedOut) {
        # Kill the whole tree (Godot may spawn helpers).
        & taskkill.exe /PID $p.Id /T /F 2>$null | Out-Null
        try { $p.WaitForExit(5000) | Out-Null } catch {}
    }
    foreach ($f in @($out, $err)) {
        if (Test-Path $f) {
            $text = Get-Content -Path $f -Raw -ErrorAction SilentlyContinue
            if ($text) { Write-Host -NoNewline $text; Add-Content -Path $Log -Value $text -Encoding UTF8 }
            Remove-Item $f -ErrorAction SilentlyContinue
        }
    }
    if ($timedOut) {
        $msg = "run_smoke: TIMEOUT after ${Seconds}s, killed Godot"
        Write-Host $msg; Add-Content -Path $Log -Value $msg
        return 124
    }
    return $p.ExitCode
}

# Isolate the user data dir (Godot uses %APPDATA%\Godot\app_userdata\<project>)
# and never let a real relay token/url leak into the run (the test stubs these too).
$saved = @{
    APPDATA = $env:APPDATA
    RSO_SMOKE_DATA_DIR = $env:RSO_SMOKE_DATA_DIR
    NIVEK_DEVICE_TOKEN = $env:NIVEK_DEVICE_TOKEN
    NIVEK_RELAY_URL = $env:NIVEK_RELAY_URL
}
$rc = 1
try {
    $env:APPDATA = $Data
    $env:RSO_SMOKE_DATA_DIR = $Data
    Remove-Item Env:NIVEK_DEVICE_TOKEN -ErrorAction SilentlyContinue
    Remove-Item Env:NIVEK_RELAY_URL -ErrorAction SilentlyContinue

    Write-Host "run_smoke: godot=$Godot repo=$Repo scene=$Scene timeout=${Timeout}s"
    Write-Host "run_smoke: log=$Log"

    # A fresh clone has no .godot\ import cache; import once first (this only
    # writes the gitignored .godot\ folder).
    $code = 0
    if (-not (Test-Path (Join-Path $Repo ".godot\imported"))) {
        Write-Host "run_smoke: no .godot import cache, importing assets first"
        $code = Invoke-Watchdog @("--headless", "--path", $Repo, "--import") 300
        if ($code -eq 124) { Write-Host "run_smoke: import timed out" }
    }
    if ($code -ne 124) {
        Set-Content -Path $Log -Value "" -Encoding UTF8 # judge only the test run
        $code = Invoke-Watchdog @("--headless", "--path", $Repo, $Scene) $Timeout
    }
    $lines = Get-Content -Path $Log
    $hasMarker = $lines | Where-Object { $_.TrimEnd() -eq $Marker } | Select-Object -First 1

    if ($code -eq 124) {
        Write-Host "run_smoke: FAIL (timed out after ${Timeout}s; last progress line above shows where it hung)"
        $rc = 124
    } elseif (-not $hasMarker) {
        Write-Host "run_smoke: FAIL ($Marker not found, godot exit code $code)"
        $lines | Where-Object { $_ -match '^SMOKE .* FAIL' } | ForEach-Object { Write-Host $_ }
        $rc = if ($code -eq 0) { 1 } else { $code }
    } elseif ($code -ne 0) {
        Write-Host "run_smoke: FAIL ($Marker printed but godot exited $code)"
        $rc = $code
    } else {
        Write-Host "run_smoke: PASS"
        $rc = 0
    }
} finally {
    foreach ($k in $saved.Keys) {
        if ($null -eq $saved[$k]) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
        else { Set-Item "Env:$k" $saved[$k] }
    }
    if ($env:SMOKE_KEEP_DATA -ne "1") { Remove-Item -Recurse -Force $Data -ErrorAction SilentlyContinue }
}
exit $rc
