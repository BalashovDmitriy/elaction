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
    # Модулем, а не gdformat.exe и gdlint.exe: неподписанные обёртки pip
    # блокирует управление приложениями Windows (WinError 4551), см.
    # .pre-commit-config.yaml. python.exe из того же окружения не блокируется.
    & (Join-Path $bin 'python.exe') -m gdtoolkit.formatter --check src tests tools
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host '== gdlint ==' -ForegroundColor Cyan
    & (Join-Path $bin 'python.exe') -m gdtoolkit.linter src tests tools
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host '== godot --headless --import ==' -ForegroundColor Cyan
    & python (Join-Path $root 'tools\godot_check.py')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host '== тесты GUT ==' -ForegroundColor Cyan
    & python (Join-Path $root 'tools\run_tests.py')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    # Отпечаток зелёного дерева: хук на push по нему не гоняет то же самое
    # второй раз (tools/check_stamp.py).
    & python (Join-Path $root 'tools\check_stamp.py') --write
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host 'Все проверки пройдены.' -ForegroundColor Green
}
finally {
    Pop-Location
}
