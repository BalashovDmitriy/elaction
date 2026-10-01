extends SceneTree

## Разбор скриптов движком пачкой в одном процессе (M24j): загрузка каждого
## скрипта компилирует его и всё, от чего он зависит, — то же, что
## `--check-only`, без старта движка на каждый файл. Пути — в файле, чей путь
## после `--`; итог по скрипту — строка `CHECK OK <путь>` или `CHECK FAIL <путь>`.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("нет списка скриптов")
		quit(2)
		return
	var listing := FileAccess.get_file_as_string(args[0])
	var failed := false
	for line: String in listing.split("\n", false):
		var path := line.strip_edges()
		if path.is_empty():
			continue
		var script := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE) as Script
		if script == null or not script.can_instantiate():
			print("CHECK FAIL %s" % path)
			failed = true
		else:
			print("CHECK OK %s" % path)
	quit(1 if failed else 0)
