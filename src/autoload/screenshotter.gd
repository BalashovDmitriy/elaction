extends Node

## Screenshots for later analysis and optimization.
##
## Manual mode: F12 saves the current frame to `screens/manual/`.
## Automatic: running the game with the `-- --capture=M2` argument plays a short
## milestone script, saves a frame for each step and closes the game. This way shots
## are taken after every playable milestone — see tools/capture.py.
##
## Shots are written as JPEG next to the project: `screens/<milestone>/<time>_<step>.jpg`.

const OUTPUT_ROOT := "res://screens"
const JPEG_QUALITY: float = 0.9
const CAPTURE_ARG_PREFIX := "--capture="
const MANUAL_FOLDER := "manual"

## Steps of the automatic run per milestone: what to hold and for how many seconds.
##
## The plan is chosen by the --capture=<milestone> argument, name case does not matter; for
## an unknown milestone the M1 plan is used and a warning goes to the log.
##
## M1 delays are tied to Otto's flight time (2 · jump_speed / gravity ≈ 0.85 s):
## "jump" is shot near the apex, and "crouch" — already after landing.
##
## M2 delays deliberately do not require precision: "ride_down" holds the descent longer
## than three floors need, and the cab hits the bottom of the shaft. So the frame does not depend
## on exactly how long the ride takes.
##
## The "at_red_door" delay in M3 is the way to the red door's mat and nothing
## more: 320 px from Otto's spawn point at walk_speed 90 px/s. "Up" in this
## step is deliberately not held, otherwise Otto would manage to go inside and the frame promising
## him in front of the door would show an empty doorway.
##
## M6 light is not checked by this script, and it is not worth trying: a dark floor
## comes only from a shot-down lamp, and hitting it with a delay is exactly the
## case that broke here four times. Darkness is shot by tools/dark_shot.tscn:
## it waits not for seconds but for a state. From here only the look of the real game is needed —
## with HUD, vignette and glow, which that tool does not have.
##
## M11 combat is not shot here for the same reason: an agent kneels not on a
## schedule, but when a high bullet flies at him. It is shot by
## tools/combat_shot.tscn — also by state.
##
## There is deliberately no death in the script. One can crash in a shaft only from a height and
## only while the cab is not underfoot: where it will be at that moment depends on
## its schedule, and that shifts with any pause edit. Such a step would silently shoot
## something other than what the caption promises. Falling and crushing are checked by a separate
## manual run — how it is done is described in docs/STATUS.md.
const AUTO_PLANS: Dictionary = {
	"M1":
	[
		{"label": "idle", "actions": [], "hold": 0.7},
		{"label": "walk", "actions": ["move_right"], "hold": 0.9},
		{"label": "jump", "actions": ["move_right", "jump"], "hold": 0.42},
		{"label": "crouch", "actions": ["move_down"], "hold": 0.9},
	],
	"M2":
	[
		{"label": "floor_top", "actions": [], "hold": 0.4},
		{"label": "in_car", "actions": ["move_right"], "hold": 0.55},
		{"label": "ride_down", "actions": ["move_down"], "hold": 4.5},
		{"label": "floor_bottom", "actions": [], "hold": 0.4},
		{"label": "left_car", "actions": ["move_right"], "hold": 0.7},
		{"label": "to_escalator", "actions": ["move_left", "move_up"], "hold": 3.4},
		{"label": "middle_floor", "actions": [], "hold": 1.0},
	],
	"M3":
	[
		{"label": "floor_top", "actions": [], "hold": 0.4},
		{"label": "at_red_door", "actions": ["move_left"], "hold": 3.55},
		{"label": "inside", "actions": ["move_up"], "hold": 0.7},
		{"label": "back_outside", "actions": ["move_right"], "hold": 0.6},
	],
	"M4A":
	[
		{"label": "agent_out", "actions": [], "hold": 0.8},
		{"label": "otto_fires", "actions": ["shoot"], "hold": 0.2},
		{"label": "after_the_shot", "actions": [], "hold": 1.5},
		{"label": "under_fire", "actions": [], "hold": 7.0},
	],
	"M4B":
	[
		{"label": "floor_top", "actions": [], "hold": 0.4},
		{"label": "jump_at_the_lamp", "actions": ["move_left", "jump"], "hold": 0.12},
		{"label": "shot", "actions": ["move_left", "shoot"], "hold": 0.25},
		{"label": "floor_goes_dark", "actions": [], "hold": 1.4},
	],
	"M5A":
	[
		{"label": "roof", "actions": [], "hold": 1.2},
		{"label": "walking", "actions": ["move_right"], "hold": 1.5},
		{"label": "settled", "actions": [], "hold": 1.5},
	],
	"M5B":
	[
		{"label": "playing", "actions": [], "hold": 0.8},
		{"label": "paused", "actions": ["pause"], "hold": 0.6},
		{"label": "still_paused", "actions": [], "hold": 0.4},
		{"label": "resumed", "actions": ["pause"], "hold": 0.6},
	],
	"M6":
	[
		{"label": "roof", "actions": [], "hold": 0.8},
		{"label": "muzzle_flash", "actions": ["shoot"], "hold": 0.08},
		{"label": "walking", "actions": ["move_right"], "hold": 1.4},
		{"label": "settled", "actions": [], "hold": 1.0},
	],
	# No step promises a place: doors and lamps stand by seed, and a delay
	# will not reach them — tools/dark_shot.tscn handles that, it waits for a state.
	"M7A":
	[
		{"label": "roof", "actions": [], "hold": 0.8},
		{"label": "walking", "actions": ["move_right"], "hold": 1.4},
		{"label": "muzzle_flash", "actions": ["shoot"], "hold": 0.08},
		{"label": "settled", "actions": [], "hold": 1.0},
	],
	"M7B":
	[
		{"label": "otto_stands", "actions": [], "hold": 0.8},
		{"label": "otto_walks", "actions": ["move_right"], "hold": 1.2},
		{"label": "otto_shoots", "actions": ["shoot"], "hold": 0.1},
		{"label": "otto_jumps", "actions": ["move_right", "jump"], "hold": 0.35},
		{"label": "otto_crouches", "actions": ["move_down"], "hold": 0.8},
	],
	# M17 light: the roof and two floors under it with lamps, ribs and indicator lights. The dark
	# zone cannot be shot here — the lamp stands by seed; F12 during play shoots it.
	"M17":
	[
		{"label": "roof", "actions": [], "hold": 1.0},
		{"label": "walking", "actions": ["move_right"], "hold": 1.5},
		{"label": "muzzle_flash", "actions": ["shoot"], "hold": 0.08},
		{"label": "settled", "actions": [], "hold": 1.0},
	],
	# M18b: descent from the roof by the shaft the milestone rests on. The escalator, a shaft
	# on a darkened floor and the two-storey pair cannot be shot by delay — they stand
	# by seed; tools/geometry_shot.tscn shoots them into the same folder.
	"M18B":
	[
		{"label": "roof", "actions": [], "hold": 1.0},
		{"label": "walking", "actions": ["move_right"], "hold": 1.5},
		{"label": "riding_down", "actions": ["move_down"], "hold": 2.5},
		{"label": "settled", "actions": [], "hold": 1.0},
	],
	# M18c: proportions. Height next to a door and a lamp, a cab the full floor tall, 3.67
	# floors in the frame — and crouch with jump: in a jump the head hits the ceiling.
	"M18C":
	[
		{"label": "roof", "actions": [], "hold": 1.0},
		{"label": "to_the_shaft", "actions": ["move_right"], "hold": 4.2},
		{"label": "riding_down", "actions": ["move_down"], "hold": 2.2},
		{"label": "stopped", "actions": [], "hold": 1.6},
		{"label": "walking_out", "actions": ["move_left"], "hold": 1.4},
		{"label": "crouching", "actions": ["move_down"], "hold": 0.6},
		{"label": "jumping", "actions": ["jump"], "hold": 0.25},
		{"label": "settled", "actions": [], "hold": 1.0},
	],
	# M18d: ROM combat. Descent by cab, stepping out onto a floor and a shootout: agents
	# come out nearby, shoot standing, kneeling and lying, Otto answers from a crouch.
	"M18D":
	[
		{"label": "roof", "actions": [], "hold": 1.0},
		{"label": "to_the_shaft", "actions": ["move_right"], "hold": 5.4},
		{"label": "riding_down", "actions": ["move_down"], "hold": 2.2},
		{"label": "stopped", "actions": [], "hold": 1.6},
		{"label": "walking_out", "actions": ["move_left"], "hold": 1.4},
		{"label": "waiting", "actions": [], "hold": 3.0},
		{"label": "shooting", "actions": ["shoot"], "hold": 0.12},
		{"label": "crouch_shot", "actions": ["move_down", "shoot"], "hold": 0.3},
		{"label": "jump_shot", "actions": ["jump", "shoot"], "hold": 0.3},
		{"label": "firefight", "actions": [], "hold": 2.5},
	],
	# M18e: building by the map. A tower with four doors per floor, descent by cab
	# and stepping out onto a floor where agents come out of doors standing every other slot.
	# Dark floors (ROM 11–15) and the wide base by seed are shot not by delay but by
	# tools/layout_shot.tscn into the same folder.
	"M18E":
	[
		{"label": "roof", "actions": [], "hold": 1.0},
		{"label": "to_the_shaft", "actions": ["move_right"], "hold": 5.4},
		{"label": "riding_down", "actions": ["move_down"], "hold": 2.2},
		{"label": "stopped", "actions": [], "hold": 1.6},
		{"label": "walking_out", "actions": ["move_left"], "hold": 1.4},
		{"label": "waiting", "actions": [], "hold": 3.0},
		{"label": "doors", "actions": [], "hold": 1.0},
	],
	# M19: city, weather, roof and dressing. A roof with slopes and the city behind
	# it, descent by cab past the blocks, a floor with items at the back wall.
	# The wide base, a dark floor and the wall by seed are shot by tools/layout_shot.tscn.
	# M20: detail — roof with equipment and neon, descent by cab (walls, panel,
	# ropes, counterweight), a floor with doors, lamps and a runner. Garage, effects,
	# rounds and weather are shot by tools/layout_shot.tscn -- --folder=M20.
	"M20":
	[
		{"label": "roof", "actions": [], "hold": 1.2},
		{"label": "roof_walk", "actions": ["move_right"], "hold": 2.5},
		{"label": "to_the_shaft", "actions": ["move_right"], "hold": 2.9},
		{"label": "riding_down", "actions": ["move_down"], "hold": 2.2},
		{"label": "stopped", "actions": [], "hold": 1.6},
		{"label": "walking_out", "actions": ["move_left"], "hold": 1.4},
		{"label": "shooting", "actions": ["shoot"], "hold": 0.3},
		{"label": "floor", "actions": [], "hold": 1.5},
	],
	# M21: people in suits. Otto walks on the roof with the walk clip, rides down, steps out
	# onto the floor to agents in fedoras, shoots, squats and jumps.
	# All poses side by side, with ROM bullet lines, are shot by tools/actor_shot.tscn, cars
	# at the exit — tools/layout_shot.tscn -- --folder=M21.
	"M21":
	[
		{"label": "roof", "actions": [], "hold": 1.2},
		{"label": "roof_walk", "actions": ["move_right"], "hold": 2.5},
		{"label": "to_the_shaft", "actions": ["move_right"], "hold": 2.9},
		{"label": "riding_down", "actions": ["move_down"], "hold": 2.2},
		{"label": "stopped", "actions": [], "hold": 1.6},
		{"label": "walking_out", "actions": ["move_left"], "hold": 1.4},
		{"label": "waiting", "actions": [], "hold": 2.5},
		{"label": "shooting", "actions": ["shoot"], "hold": 0.3},
		{"label": "crouching", "actions": ["move_down"], "hold": 0.6},
		{"label": "jumping", "actions": ["jump"], "hold": 0.3},
		{"label": "firefight", "actions": [], "hold": 2.0},
	],
	# M21b: world from pack models. Roof with equipment and a sign on the corner, descent by cab
	# past floor indicator boards, a hotel floor with dressing and a steel shaft. Office and garages
	# per building are shot by tools/layout_shot.tscn -- --folder=M21b --building=N.
	# M22: grading and HUD — the same descent as M21b: roof, cab, hotel floor.
	# Quality levels and tone side by side are shot by tools/layout_shot.tscn --floor-only.
	"M22":
	[
		{"label": "roof", "actions": [], "hold": 1.2},
		{"label": "roof_walk", "actions": ["move_right"], "hold": 2.5},
		{"label": "to_the_shaft", "actions": ["move_right"], "hold": 2.9},
		{"label": "riding_down", "actions": ["move_down"], "hold": 2.2},
		{"label": "stopped", "actions": [], "hold": 1.6},
		{"label": "walking_out", "actions": ["move_left"], "hold": 1.4},
		{"label": "floor", "actions": [], "hold": 1.5},
	],
	"M21B":
	[
		{"label": "roof", "actions": [], "hold": 1.2},
		{"label": "roof_walk", "actions": ["move_right"], "hold": 2.5},
		{"label": "to_the_shaft", "actions": ["move_right"], "hold": 2.9},
		{"label": "riding_down", "actions": ["move_down"], "hold": 2.2},
		{"label": "stopped", "actions": [], "hold": 1.6},
		{"label": "walking_out", "actions": ["move_left"], "hold": 1.4},
		{"label": "floor", "actions": [], "hold": 1.5},
		{"label": "walking_on", "actions": ["move_left"], "hold": 1.6},
	],
	# M24b: the helicopter brings Otto (tools/intro_shot.tscn shoots the scene), then
	# the same descent: roof, cab, floor. Garage — tools/garage_shot.tscn; the timed script
	# does not reach the door, the basement and the exit, they have no shooting
	# tool of their own yet.
	"M24B":
	[
		{"label": "roof", "actions": [], "hold": 1.2},
		{"label": "roof_walk", "actions": ["move_right"], "hold": 2.5},
		{"label": "to_the_shaft", "actions": ["move_right"], "hold": 2.9},
		{"label": "riding_down", "actions": ["move_down"], "hold": 2.2},
		{"label": "stopped", "actions": [], "hold": 1.6},
		{"label": "walking_out", "actions": ["move_left"], "hold": 1.4},
		{"label": "floor", "actions": [], "hold": 1.5},
	],
	# M24c: movement with UAL clips. The same descent, and on the floor — push-off, flight,
	# landing, turning in the middle and a step. All poses side by side, with ROM
	# bullet lines, are shot by tools/actor_shot.tscn -- --folder=M24C.
	"M24C":
	[
		{"label": "roof", "actions": [], "hold": 1.2},
		{"label": "roof_walk", "actions": ["move_right"], "hold": 2.5},
		{"label": "to_the_shaft", "actions": ["move_right"], "hold": 2.9},
		{"label": "riding_down", "actions": ["move_down"], "hold": 2.2},
		{"label": "stopped", "actions": [], "hold": 1.6},
		{"label": "walking_out", "actions": ["move_left"], "hold": 1.4},
		{"label": "floor", "actions": [], "hold": 0.6},
		{"label": "takeoff", "actions": ["jump"], "hold": 0.2},
		{"label": "falling", "actions": [], "hold": 0.45},
		{"label": "landing", "actions": [], "hold": 0.4},
		{"label": "turning", "actions": ["move_right"], "hold": 0.05},
		{"label": "walking_on", "actions": ["move_right"], "hold": 1.0},
	],
	# M24d: takedowns. The same route as M24c: the jump is now without the leg, flight
	# with a clip. Takedown scenes are shot by tools/takedown_shot.tscn -- --folder=M24D:
	# a timed route will not bring an agent up close.
	"M24D":
	[
		{"label": "roof", "actions": [], "hold": 1.2},
		{"label": "roof_walk", "actions": ["move_right"], "hold": 2.5},
		{"label": "to_the_shaft", "actions": ["move_right"], "hold": 2.9},
		{"label": "riding_down", "actions": ["move_down"], "hold": 2.2},
		{"label": "stopped", "actions": [], "hold": 1.6},
		{"label": "walking_out", "actions": ["move_left"], "hold": 1.4},
		{"label": "floor", "actions": [], "hold": 0.6},
		{"label": "takeoff", "actions": ["jump"], "hold": 0.2},
		{"label": "falling", "actions": [], "hold": 0.45},
		{"label": "landing", "actions": [], "hold": 0.4},
		{"label": "turning", "actions": ["move_right"], "hold": 0.05},
		{"label": "walking_on", "actions": ["move_right"], "hold": 1.0},
	],
	# M24e: demo mode. The game route is the same as M24d; the demo itself is shot by
	# tools/demo_shot.tscn -- --folder=M24E: it is from the menu, while capture starts with a game.
	"M24E":
	[
		{"label": "roof", "actions": [], "hold": 1.2},
		{"label": "roof_walk", "actions": ["move_right"], "hold": 2.5},
		{"label": "to_the_shaft", "actions": ["move_right"], "hold": 2.9},
		{"label": "riding_down", "actions": ["move_down"], "hold": 2.2},
		{"label": "stopped", "actions": [], "hold": 1.6},
		{"label": "walking_out", "actions": ["move_left"], "hold": 1.4},
		{"label": "floor", "actions": [], "hold": 0.6},
		{"label": "takeoff", "actions": ["jump"], "hold": 0.2},
		{"label": "falling", "actions": [], "hold": 0.45},
		{"label": "landing", "actions": [], "hold": 0.4},
		{"label": "turning", "actions": ["move_right"], "hold": 0.05},
		{"label": "walking_on", "actions": ["move_right"], "hold": 1.0},
	],
	# M24f: bugs and settings. The game route is the same as M24e; light and
	# darkness frames — tools/light_bench.tscn -- --shot=, the menu with "Credits" —
	# tools/ui_shot.tscn -- --folder=M24F.
	"M24F":
	[
		{"label": "roof", "actions": [], "hold": 1.2},
		{"label": "roof_walk", "actions": ["move_right"], "hold": 2.5},
		{"label": "to_the_shaft", "actions": ["move_right"], "hold": 2.9},
		{"label": "riding_down", "actions": ["move_down"], "hold": 2.2},
		{"label": "stopped", "actions": [], "hold": 1.6},
		{"label": "walking_out", "actions": ["move_left"], "hold": 1.4},
		{"label": "floor", "actions": [], "hold": 0.6},
		{"label": "takeoff", "actions": ["jump"], "hold": 0.2},
		{"label": "falling", "actions": [], "hold": 0.45},
		{"label": "landing", "actions": [], "hold": 0.4},
		{"label": "turning", "actions": ["move_right"], "hold": 0.05},
		{"label": "walking_on", "actions": ["move_right"], "hold": 1.0},
	],
	# M24g: animation and looks. The game route is the same as M24f, plus the rope descent
	# at the start; corpses, cab, escalator, door — tools/m24g_shot.tscn, the exit
	# frame by frame — tools/m24b_shot.tscn -- --sequence, poses — tools/actor_shot.tscn.
	"M24G":
	[
		{"label": "rope", "actions": [], "hold": 0.4},
		{"label": "roof", "actions": [], "hold": 1.2},
		{"label": "roof_walk", "actions": ["move_right"], "hold": 2.5},
		{"label": "to_the_shaft", "actions": ["move_right"], "hold": 2.9},
		{"label": "riding_down", "actions": ["move_down"], "hold": 2.2},
		{"label": "stopped", "actions": [], "hold": 1.6},
		{"label": "walking_out", "actions": ["move_left"], "hold": 1.4},
		{"label": "floor", "actions": [], "hold": 0.6},
		{"label": "takeoff", "actions": ["jump"], "hold": 0.2},
		{"label": "falling", "actions": [], "hold": 0.45},
		{"label": "landing", "actions": [], "hold": 0.4},
		{"label": "turning", "actions": ["move_right"], "hold": 0.05},
		{"label": "walking_on", "actions": ["move_right"], "hold": 1.0},
	],
	# M24h: street and cab. The M24g route plus a step in a moving cab; the escalator in
	# depth — tools/m24g_shot.tscn, traffic and exit — tools/m24b_shot.tscn --
	# --sequence, a frame per floor — tools/light_bench.tscn -- --floors.
	"M24H":
	[
		{"label": "rope", "actions": [], "hold": 0.4},
		{"label": "roof", "actions": [], "hold": 1.2},
		{"label": "roof_walk", "actions": ["move_right"], "hold": 2.5},
		{"label": "to_the_shaft", "actions": ["move_right"], "hold": 2.9},
		{"label": "riding_down", "actions": ["move_down"], "hold": 1.4},
		{"label": "walking_in_the_car", "actions": ["move_down", "move_left"], "hold": 0.8},
		{"label": "stopped", "actions": [], "hold": 1.6},
		{"label": "walking_out", "actions": ["move_left"], "hold": 1.4},
		{"label": "floor", "actions": [], "hold": 0.6},
		{"label": "takeoff", "actions": ["jump"], "hold": 0.2},
		{"label": "falling", "actions": [], "hold": 0.45},
		{"label": "landing", "actions": [], "hold": 0.4},
		{"label": "walking_on", "actions": ["move_right"], "hold": 1.0},
	],
	# M24i: looks. The M24h route: helicopter and rope, roof, cab, a corridor with
	# finish by building kind. Cars with interiors — tools/car_shot.tscn, boarding
	# and exit on all models — tools/m24b_shot.tscn -- --building=N
	# --only=exit, rooms behind a door — tools/room_shot.tscn, takedowns —
	# tools/takedown_shot.tscn, hotel and office floors — tools/layout_shot.tscn --
	# --floor-only --building=N.
	"M24I":
	[
		{"label": "rope", "actions": [], "hold": 0.4},
		{"label": "roof", "actions": [], "hold": 1.2},
		{"label": "roof_walk", "actions": ["move_right"], "hold": 2.5},
		{"label": "to_the_shaft", "actions": ["move_right"], "hold": 2.9},
		{"label": "riding_down", "actions": ["move_down"], "hold": 1.4},
		{"label": "stopped", "actions": [], "hold": 1.6},
		{"label": "walking_out", "actions": ["move_left"], "hold": 1.4},
		{"label": "floor", "actions": [], "hold": 0.6},
		{"label": "walking_on", "actions": ["move_right"], "hold": 1.6},
	],
	# M24j: time of day and the new city. The M24i route — the first building of a game at
	# its seed's time of day. All twelve combinations of time and weather —
	# tools/m24j_shot.tscn, the city up close without defocus — tools/city_shot.tscn.
	"M24J":
	[
		{"label": "rope", "actions": [], "hold": 0.4},
		{"label": "roof", "actions": [], "hold": 1.2},
		{"label": "roof_walk", "actions": ["move_right"], "hold": 2.5},
		{"label": "to_the_shaft", "actions": ["move_right"], "hold": 2.9},
		{"label": "riding_down", "actions": ["move_down"], "hold": 1.4},
		{"label": "stopped", "actions": [], "hold": 1.6},
		{"label": "walking_out", "actions": ["move_left"], "hold": 1.4},
		{"label": "floor", "actions": [], "hold": 0.6},
		{"label": "walking_on", "actions": ["move_right"], "hold": 1.6},
	],
	# M24l: snow. The M24j route — the first building of a game in its seed's weather;
	# snow at all times of day, the street with pedestrians and footprints — tools/m24j_shot.tscn
	# with --weather=3 (--only=walk — a chain of footprints).
	"M24L":
	[
		{"label": "rope", "actions": [], "hold": 0.4},
		{"label": "roof", "actions": [], "hold": 1.2},
		{"label": "roof_walk", "actions": ["move_right"], "hold": 2.5},
		{"label": "to_the_shaft", "actions": ["move_right"], "hold": 2.9},
		{"label": "riding_down", "actions": ["move_down"], "hold": 1.4},
		{"label": "stopped", "actions": [], "hold": 1.6},
		{"label": "walking_out", "actions": ["move_left"], "hold": 1.4},
		{"label": "floor", "actions": [], "hold": 0.6},
		{"label": "walking_on", "actions": ["move_right"], "hold": 1.6},
	],
	# Residential building (ADR-0055): capture runs in the first residential building of an unsalted
	# game ([constant CAPTURE_KINDS]) — the same route roof — shaft — floor.
	"M24M":
	[
		{"label": "roof", "actions": [], "hold": 1.2},
		{"label": "roof_walk", "actions": ["move_right"], "hold": 2.5},
		{"label": "to_the_shaft", "actions": ["move_right"], "hold": 2.9},
		{"label": "riding_down", "actions": ["move_down"], "hold": 1.4},
		{"label": "stopped", "actions": [], "hold": 1.6},
		{"label": "walking_out", "actions": ["move_left"], "hold": 1.4},
		{"label": "floor", "actions": [], "hold": 0.6},
		{"label": "walking_on", "actions": ["move_right"], "hold": 1.6},
		{"label": "walking_back", "actions": ["move_left"], "hold": 2.4},
	],
	# Kind character (ADR-0056): the same route in the first office of a game — its
	# wall changed the most, glass and the hall behind it. Hotel and residential building
	# side by side are shot by `tools/kinds_sheet.py`.
	"M24N":
	[
		{"label": "roof", "actions": [], "hold": 1.2},
		{"label": "roof_walk", "actions": ["move_right"], "hold": 2.5},
		{"label": "to_the_shaft", "actions": ["move_right"], "hold": 2.9},
		{"label": "riding_down", "actions": ["move_down"], "hold": 1.4},
		{"label": "stopped", "actions": [], "hold": 1.6},
		{"label": "walking_out", "actions": ["move_left"], "hold": 1.4},
		{"label": "floor", "actions": [], "hold": 0.6},
		{"label": "walking_on", "actions": ["move_right"], "hold": 1.6},
		{"label": "walking_back", "actions": ["move_left"], "hold": 2.4},
	],
	# Cab by kind (ADR-0057, decision 6): the same route in the first residential building
	# of a game — the freight cab grille is closed while moving and folded at the floor. Halls
	# of special floors of three kinds are shot by `tools/kinds_sheet.py --floors`.
	"M24O":
	[
		{"label": "roof", "actions": [], "hold": 1.2},
		{"label": "roof_walk", "actions": ["move_right"], "hold": 2.5},
		{"label": "to_the_shaft", "actions": ["move_right"], "hold": 2.9},
		{"label": "riding_down", "actions": ["move_down"], "hold": 1.4},
		{"label": "stopped", "actions": [], "hold": 1.6},
		{"label": "walking_out", "actions": ["move_left"], "hold": 1.4},
		{"label": "floor", "actions": [], "hold": 0.6},
	],
	# Building exterior by kind (ADR-0058): the route in the first office of a game — the crown
	# above the roof, the tower end walls and the setback ledge from floors. Hotel and residential
	# side by side — `tools/kinds_sheet.py`, the intro — `tools/intro_shot.tscn --building=N`.
	"M24P":
	[
		{"label": "roof", "actions": [], "hold": 1.2},
		{"label": "roof_walk", "actions": ["move_right"], "hold": 2.5},
		{"label": "to_the_shaft", "actions": ["move_right"], "hold": 2.9},
		{"label": "riding_down", "actions": ["move_down"], "hold": 1.4},
		{"label": "stopped", "actions": [], "hold": 1.6},
		{"label": "walking_out", "actions": ["move_left"], "hold": 1.4},
		{"label": "floor", "actions": [], "hold": 0.6},
	],
	"M19":
	[
		{"label": "roof", "actions": [], "hold": 1.2},
		{"label": "roof_walk", "actions": ["move_right"], "hold": 2.5},
		{"label": "to_the_shaft", "actions": ["move_right"], "hold": 2.9},
		{"label": "riding_down", "actions": ["move_down"], "hold": 2.2},
		{"label": "stopped", "actions": [], "hold": 1.6},
		{"label": "walking_out", "actions": ["move_left"], "hold": 1.4},
		{"label": "floor", "actions": [], "hold": 1.5},
	],
}
const DEFAULT_PLAN := "M1"
## Which building kind a milestone's capture runs in: the game starts from the first building
## of this kind. Other milestones — from the first building, a hotel.
const CAPTURE_KINDS: Dictionary = {
	"M24M": BuildingIdentity.Kind.RESIDENTIAL,
	"M24N": BuildingIdentity.Kind.OFFICE,
	"M24O": BuildingIdentity.Kind.RESIDENTIAL,
	"M24P": BuildingIdentity.Kind.OFFICE
}

var _milestone: String = MANUAL_FOLDER


func _ready() -> void:
	# This is a development tool. In an exported build res:// is not
	# writable, and a global input hook and a busy F12 are not needed by the game.
	if not OS.is_debug_build():
		set_process_input(false)
		return

	# A shot must work on pause too, otherwise F12 stops working in M8.
	process_mode = Node.PROCESS_MODE_ALWAYS

	var milestone := _milestone_from_cmdline()
	if milestone.is_empty():
		return
	_milestone = milestone
	_run_auto_plan.call_deferred()


## Whether auto capture is running. [Main] uses this to know the menu must be skipped:
## the capture script presses game actions, and it will not get from the menu to the game —
## it cannot press menu buttons and must not be able to.
##
## Static: the autoload name is not visible when a single script is parsed apart from the
## project, so it is called via preload of the file itself — like the neighbouring
## [method mark_ignored_by_engine].
static func capturing() -> bool:
	return not _milestone_from_cmdline().is_empty()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("screenshot"):
		# A manual frame always goes to manual/, even in the middle of an automatic run:
		# otherwise it would land in the milestone folder and pass for a script frame.
		capture(MANUAL_FOLDER, MANUAL_FOLDER)


## Saves the current frame. Call with await, otherwise the shot slips a frame ahead.
##
## [param folder] overrides the milestone folder; an empty string — the folder of the current run.
func capture(label: String, folder: String = "") -> void:
	await RenderingServer.frame_post_draw

	var target := _milestone if folder.is_empty() else folder
	var absolute_root := ProjectSettings.globalize_path(OUTPUT_ROOT)
	var absolute_folder := absolute_root.path_join(target)
	var error := DirAccess.make_dir_recursive_absolute(absolute_folder)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_error(
			"Could not create the screenshot folder: %s (code %d)" % [absolute_folder, error]
		)
		return
	mark_ignored_by_engine(absolute_root)

	var absolute_path := _free_path(absolute_folder, label)
	var image := get_viewport().get_texture().get_image()
	error = image.save_jpg(absolute_path, JPEG_QUALITY)
	if error != OK:
		push_error("Could not save screenshot %s (code %d)" % [absolute_path, error])
		return

	print("[screenshot] %s" % absolute_path)


func _run_auto_plan() -> void:
	var tree := get_tree()
	# Let the scene assemble and the level build its geometry.
	await tree.process_frame
	await _wait_for_the_player()

	for step: Dictionary in _plan_for(_milestone):
		var actions: Array = step.get("actions", [])
		for action: String in actions:
			Input.action_press(action)

		await tree.create_timer(float(step.get("hold", 0.5))).timeout
		await capture(str(step.get("label", "frame")))

		for action: String in actions:
			Input.action_release(action)

	tree.quit()


## Waits until the building hands Otto to the player.
##
## A round starts with the rope descent, and for the first half second input does nothing
## (ADR-0017, decision 4). Script steps are measured by delay from Otto's spawn
## point, and started on the rope they lose that half second of walking: the frame promising
## a door would show a blank wall. Wait by state, not by delay — the intro length
## will still change, while "stands on the floor" never will.
func _wait_for_the_player() -> void:
	var level := _level_in_play()
	if level == null:
		return

	if not await level.wait_for_the_landing():
		push_warning("Otto did not land on the roof, the script goes on as is")


## The building being captured. It sits directly in the current scene: [Main] puts it
## there, and during capture it is the only one.
func _level_in_play() -> GreyboxLevel:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	for child: Node in scene.get_children():
		var level := child as GreyboxLevel
		if level != null:
			return level
	return null


## The milestone script. Case does not matter: in documents the milestone is called `M4a`, and
## the key here is one for both spellings.
##
## An unknown milestone has no plan, and silently shooting M1 instead is not allowed: the frames
## would land in a folder with its name and pass for its script. Hence the warning.
func _plan_for(milestone: String) -> Array:
	var key := milestone.to_upper()
	if AUTO_PLANS.has(key):
		return AUTO_PLANS[key]
	push_warning("No shot plan for milestone '%s', shooting %s" % [milestone, DEFAULT_PLAN])
	return AUTO_PLANS[DEFAULT_PLAN]


## Which building to start a game from when capturing a milestone ([constant CAPTURE_KINDS]):
## without salt a building's seed is its number. Without capture — from the first.
static func start_building() -> int:
	var key := _milestone_from_cmdline().to_upper()
	if not CAPTURE_KINDS.has(key):
		return 1
	return BuildingIdentity.first_of(CAPTURE_KINDS[key])


static func _milestone_from_cmdline() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(CAPTURE_ARG_PREFIX):
			return argument.trim_prefix(CAPTURE_ARG_PREFIX).strip_edges()
	return ""


## A free path for a frame. The timestamp goes down to seconds, so two shots
## in the same second with the same label differ by a suffix instead of overwriting each other.
func _free_path(folder: String, label: String) -> String:
	var base := folder.path_join("%s_%s" % [_timestamp(), label])
	var candidate := "%s.jpg" % base
	var index := 2
	while FileAccess.file_exists(candidate):
		candidate = "%s-%d.jpg" % [base, index]
		index += 1
	return candidate


## Puts .gdignore next to the shots: without it Godot imports every JPEG
## as a project resource and litters the folder with .import files.
##
## Public and static: tools/*_shot.gd write into the same folder, and each one's own
## copy of this marker would diverge from this one at the first edit. Static,
## because it has to be called by script, not by autoload: the autoload name is
## visible only to the running game, and `godot_check.py` parses scripts one at a time.
static func mark_ignored_by_engine(root_folder: String) -> void:
	var marker := root_folder.path_join(".gdignore")
	if FileAccess.file_exists(marker):
		return
	var file := FileAccess.open(marker, FileAccess.WRITE)
	if file == null:
		push_error("Could not create %s (code %d)" % [marker, FileAccess.get_open_error()])
		return
	file.close()


func _timestamp() -> String:
	var now := Time.get_datetime_dict_from_system()
	return (
		"%04d%02d%02d-%02d%02d%02d"
		% [now["year"], now["month"], now["day"], now["hour"], now["minute"], now["second"]]
	)
