#!/usr/bin/env bash
# Полный прогон проверок проекта elaction (тот же набор, что и в CI).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

if [ -x ".venv/Scripts/gdformat.exe" ]; then
	bin=".venv/Scripts"
elif [ -x ".venv/bin/gdformat" ]; then
	bin=".venv/bin"
else
	bin=""
fi
gdformat_cmd="${bin:+$bin/}gdformat"
gdlint_cmd="${bin:+$bin/}gdlint"

echo "== gdformat --check =="
"$gdformat_cmd" --check src tests tools

echo "== gdlint =="
"$gdlint_cmd" src tests tools

echo "== godot --headless --import =="
python tools/godot_check.py

echo "== тесты GUT =="
python tools/run_tests.py

echo "Все проверки пройдены."
