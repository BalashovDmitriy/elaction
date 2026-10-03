extends SceneTree

## Prints the building layout: what was generated and where.
##
## The layout is random by seed, and it cannot be checked by eye from a frame — less than a
## third of a floor fits in the frame. The tool answers the question "what actually came out there".
##
## Run:
##     godot --headless --script res://tools/dump_plan.gd -- 1
##     godot --headless --script res://tools/dump_plan.gd -- 3 --floors=4 --span=2
##
## The first number is the seed. Building sizes can be overridden: this is how one looks at the same
## small buildings the traversal tests run on.


func _init() -> void:
	var building_seed := 1
	for argument in OS.get_cmdline_user_args():
		if argument.is_valid_int():
			building_seed = argument.to_int()
			break

	var rules := BuildingRules.new()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--floors="):
			rules.floors = argument.trim_prefix("--floors=").to_int()
		elif argument.begins_with("--documents="):
			rules.documents_cap = argument.trim_prefix("--documents=").to_int()
		elif argument.begins_with("--span="):
			rules.shaft_span = argument.trim_prefix("--span=").to_int()
	var plan := BuildingPlan.generate(rules, building_seed)

	print("Building for seed %d: %d floors" % [building_seed, plan.floors])
	print("\nShafts (floors top to bottom, x):")
	for shaft in plan.shafts:
		var pair := ""
		if shaft.double_deck:
			var span := shaft.ride_span()
			pair = "  two-storey, carries %d..%d" % [span.x, span.y]
		print("  %2d..%2d  x=%.0f%s" % [shaft.top, shaft.bottom, shaft.x, pair])

	print("\nEscalators (from floor, x, where it descends, opening):")
	for escalator in plan.escalators:
		var gap := escalator.gap(rules)
		var side := "right" if escalator.towards > 0.0 else "left"
		var mark := [escalator.floor_index, escalator.x, side, gap.x, gap.y]
		print("  %2d  x=%.0f  %s  opening %.0f..%.0f" % mark)

	print("\nInner walls (floor, x):")
	for wall in plan.walls:
		print("  %2d  x=%.1f" % [wall.floor_index, wall.x])

	print("\nShafts per floor (rules target / actual):")
	for index in rules.levels():
		var serving := 0
		for shaft in plan.shafts:
			if shaft.top <= index and shaft.bottom >= index:
				serving += 1
		print("  %2d  %d / %d" % [index, rules.shafts_on(index), serving])

	_trace_route(plan, rules)

	print("\nDocument floors: %s" % str(plan.document_floors()))
	print("Exit: x=%.0f" % plan.exit_x)
	print("Doors: %d, lamps: %d" % [plan.doors.size(), plan.lamps.size()])
	print("Winnable: %s" % str(BuildingRoute.is_winnable(plan, rules)))

	quit()


## The route as the bot sees it: step by step from the roof to the exit.
##
## This trace is used to find where the descent gets stuck: "the bot did not get through" names only
## the floor, while here one sees what it meant to use and where that leads.
func _trace_route(plan: BuildingPlan, rules: BuildingRules) -> void:
	print("\nRoute over the graph: documents top to bottom, then the exit")
	var graph := BuildingRoute.walkable(plan, rules)
	var here := BuildingRules.ROOF
	var x := plan.safe_x(rules, here)

	# The goals are the same as the bot's: the top uncollected document, and when all are collected —
	# the exit. Otherwise the trace would show a road the bot does not take.
	var goals: Array[Dictionary] = []
	for spot in plan.doors:
		if spot.has_document:
			goals.append({"floor": spot.floor_index, "x": spot.x, "what": "document"})
	goals.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["floor"] < b["floor"])
	goals.append({"floor": rules.floors - 1, "x": plan.exit_x, "what": "exit"})

	for goal: Dictionary in goals:
		print("  → %s on floor %d, x=%.1f" % [goal["what"], int(goal["floor"]), float(goal["x"])])
		var reached := false
		for _step in rules.floors * 3:
			var move := BuildingRoute.step_toward(
				graph, here, x, int(goal["floor"]), float(goal["x"])
			)
			if move.is_empty():
				print("     floor %2d, x=%5.1f — no move further" % [here, x])
				return
			if String(move["kind"]) == "walk":
				print("     floor %2d, x=%5.1f: reach" % [here, x])
				here = int(goal["floor"])
				x = float(goal["x"])
				reached = true
				break
			print(
				(
					"     floor %2d, x=%5.1f: %s to x=%.1f → floor %d"
					% [here, x, move["kind"], float(move["x"]), int(move["floor"])]
				)
			)
			here = int(move["floor"])
			x = float(move["to_x"])
		if not reached:
			print("     trail cut: the route is longer than three times the floor count")
			return
