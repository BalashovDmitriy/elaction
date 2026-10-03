extends SceneTree

## Engine parsing of scripts in a batch in one process (M24j): loading each script
## compiles it and everything it depends on — the same as `--check-only`, without
## starting the engine for every file. The paths are in a file whose path comes after
## `--`; the result per script is a line `CHECK OK <path>` or `CHECK FAIL <path>`.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("no script list")
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
