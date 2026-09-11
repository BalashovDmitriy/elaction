# elaction

Ремейк аркадной игры **Elevator Action** (Taito, 1983) на Godot 4.

Механика — как в оригинале: агент Otto спускается с крыши тридцатиэтажного здания,
собирает документы за красными дверями, ездит на лифтах, отстреливается от вражеских
агентов и уходит на машине. Картинка — современная: динамический свет, нормал-мапы,
пост-обработка. Лампы на этаже можно прострелить, и этаж погрузится в темноту.

| | |
|---|---|
| Движок | Godot 4.7.2 |
| Язык | GDScript со статической типизацией |
| Платформы | Windows, Linux |
| Статус | M0 — фундамент. Играть пока нельзя |

## Дорожная карта

Весь план работ — в [`docs/EPIC.md`](docs/EPIC.md). Архитектурные решения и их причины —
в [`docs/adr/`](docs/adr/).

## Запуск

### Что нужно поставить

- [Godot 4.7.2](https://godotengine.org/download) — на Windows проще через winget:

  ```powershell
  winget install --id GodotEngine.GodotEngine
  ```

- Python 3.12 или новее — для линтеров и хуков.

### Настройка окружения

```powershell
python -m venv .venv
.venv/Scripts/pip install -r requirements-dev.txt
.venv/Scripts/pre-commit install
.venv/Scripts/pre-commit install --hook-type pre-push
```

### Запустить игру

```powershell
godot --path .
```

### Открыть в редакторе

```powershell
godot -e --path .
```

## Проверки

Хуки прогоняются сами: `gdformat` и `gdlint` на коммите, импорт проекта движком — на push.
Полный прогон вручную:

```powershell
tools/check.ps1
```

Тот же набор проверок выполняет CI на каждый push и pull request.

## Структура и стиль

Описаны в [`docs/conventions.md`](docs/conventions.md).

## Лицензия

Код проекта — MIT. Elevator Action является товарным знаком Taito Corporation; проект
не аффилирован с правообладателем, оригинальные ассеты игры не используются.
