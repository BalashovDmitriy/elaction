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

    Write-Host '== gdformat --check ==' -ForegroundColor Cyan
    & (Join-Path $bin 'gdformat.exe') --check src tests tools
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host '== gdlint ==' -ForegroundColor Cyan
    & (Join-Path $bin 'gdlint.exe') src tests tools
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host '== godot --headless --import ==' -ForegroundColor Cyan
    & python (Join-Path $root 'tools\godot_check.py')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host '== тесты GUT ==' -ForegroundColor Cyan
    & python (Join-Path $root 'tools\run_tests.py')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host 'Все проверки пройдены.' -ForegroundColor Green
}
finally {
    Pop-Location
}
