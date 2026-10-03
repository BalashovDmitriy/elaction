#Requires -Version 5.1
<#
.SYNOPSIS
    Full run of the elaction project checks: formatting, lint, engine.
.DESCRIPTION
    Exactly what CI runs. Run before push:
        .\tools\check.ps1
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    $bin = Join-Path $root '.venv\Scripts'
    if (-not (Test-Path $bin)) {
        throw 'No .venv. Create it: python -m venv .venv; .venv\Scripts\pip install -r requirements-dev.txt'
    }

    Write-Host '== gdformat --check and gdlint ==' -ForegroundColor Cyan
    # As modules, not gdformat.exe and gdlint.exe: unsigned pip wrappers are blocked
    # by Windows application control (WinError 4551), see
    # .pre-commit-config.yaml. Both at once and in chunks across processor threads:
    # in sequence they took eleven seconds on one thread (tools/gd_tools.py).
    & (Join-Path $bin 'python.exe') (Join-Path $root 'tools\gd_tools.py')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host '== engine: import and script parsing ==' -ForegroundColor Cyan
    & python (Join-Path $root 'tools\godot_check.py')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host '== GUT tests ==' -ForegroundColor Cyan
    & python (Join-Path $root 'tools\run_tests.py')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    # Fingerprint of a green tree: the push hook uses it to avoid running the same
    # thing a second time (tools/check_stamp.py).
    & python (Join-Path $root 'tools\check_stamp.py') --write
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host 'All checks passed.' -ForegroundColor Green
}
finally {
    Pop-Location
}
