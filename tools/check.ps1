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
    # Модулями, а не gdformat.exe и gdlint.exe: неподписанные обёртки pip
    # блокирует управление приложениями Windows (WinError 4551), см.
    # .pre-commit-config.yaml. Оба разом и кусками по потокам процессора:
    # подряд они шли одиннадцать секунд на одном потоке (tools/gd_tools.py).
    & (Join-Path $bin 'python.exe') (Join-Path $root 'tools\gd_tools.py')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host '== движок: импорт и разбор скриптов ==' -ForegroundColor Cyan
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
