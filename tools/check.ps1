#Requires -Version 5.1
<#
.SYNOPSIS
    Полный прогон проверок проекта elaction: форматирование, линт, движок.
.DESCRIPTION
    Ровно то же, что гоняет CI. Запускать перед push:
        .\tools\check.ps1
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    $bin = Join-Path $root '.venv\Scripts'
    if (-not (Test-Path $bin)) {
        throw 'Нет .venv. Создайте: python -m venv .venv; .venv\Scripts\pip install -r requirements-dev.txt'
    }

    Write-Host '== gdformat --check и gdlint ==' -ForegroundColor Cyan
    # As modules, not gdformat.exe and gdlint.exe: unsigned pip wrappers are blocked
    # by Windows application control (WinError 4551), see
    # .pre-commit-config.yaml. Both at once and in chunks across processor threads:
    # in sequence they took eleven seconds on one thread (tools/gd_tools.py).
    & (Join-Path $bin 'python.exe') (Join-Path $root 'tools\gd_tools.py')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host '== движок: импорт и разбор скриптов ==' -ForegroundColor Cyan
    & python (Join-Path $root 'tools\godot_check.py')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host '== тесты GUT ==' -ForegroundColor Cyan
    & python (Join-Path $root 'tools\run_tests.py')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    # Fingerprint of a green tree: the push hook uses it to avoid running the same
    # thing a second time (tools/check_stamp.py).
    & python (Join-Path $root 'tools\check_stamp.py') --write
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host 'Все проверки пройдены.' -ForegroundColor Green
}
finally {
    Pop-Location
}
