class_name BuildingStyle
extends RefCounted

## Corridor look by building kind (ADR-0048, ADR-0055): how the hotel, office and residential
## building differ from each other, apart from dressing.
##
## Previously the building kind changed wall textures, sign metal and the furniture set, while
## doors, light fixtures, the runner and the cornice were the same for both — and corridors read
## alike (user's remark, 2026-09-30). Here everything a kind has of its
## own is in one place: floor, doors, light fixtures, sconces, signs. The mechanics are the same —
## a lamp breaks, a door opens the same way, only the look changes.
##
## No nodes: [FloorDetail], [Door], [Lamp], [BuildingProps] build from it.

## Floor light fixture: a pendant shade, an office fluorescent lamp,
## a glass dish or a bare bulb in the residential building, a hotel chandelier (ADR-0056,
## decision 5).
enum Fixture { PENDANT, PANEL, DOME, BULB, CHANDELIER }

## Departments on office signs.
const DEPARTMENTS: PackedStringArray = [
	"ACCOUNTS", "LEGAL", "SALES", "ARCHIVE", "PAYROLL", "RESEARCH", "BOARD", "SECURITY"
]

## Carpet runner along the corridor: only in the hotel. In the office — carpet tiles
## over the whole floor, in the residential building — checkerboard tiles.
var runner: bool = true
## Tiles over the whole floor: colour and joint grid pitch, m.
var tile_color := Color(0.2, 0.22, 0.25)
var tile_step: float = 0.6
## Checkerboard: every other tile is the second colour (residential building, ADR-0055, decision 4).
var checker: bool = false
var tile_alt := Color(0.16, 0.16, 0.17)
## Cornice under the ceiling: the hotel's is moulded, taller and projecting; the office's is narrow.
var crown := Vector2(0.12, 0.1)
var crown_color := Color(0.3, 0.3, 0.32)
## Door leaf: tone, panels (hotel) or glass in the leaf (office), frame tone and
## handle.
var leaf_tone := GreyboxLook.DOOR
var panels: bool = true
var vision_glass: bool = false
var frame_tone := Color(0.26, 0.2, 0.14)
var handle_tone := Color(0.78, 0.64, 0.32)
## Peephole in the leaf: for apartments.
var peephole: bool = false
## Indicator above the door: warm in the hotel, cold white in the office.
var sign_tone := GreyboxLook.SIGN_WARM
## Floor light fixture.
var fixture: Fixture = Fixture.PENDANT
## Sconces on pilasters — only in the hotel.
var sconces: bool = true
## Sign by the door: the hotel has a room number, the office — department and number, an apartment —
## floor and letter, like 12C.
var departments: bool = false
var apartment_letters: bool = false
## Small things at room doors: a "Do not disturb" sign on the handle and a tray or
## newspaper at the threshold — a share of doors.
var door_hanger_share: float = 0.0
var door_tray_share: float = 0.0
## Small things at apartment doors: a doormat and a shopping bag — a share of doors.
var door_mat_share: float = 0.0
var door_bag_share: float = 0.0
## Share of lamps that flicker: the residential building has old tubes (ADR-0055, decision 4).
var flicker_share: float = 0.0
## With what chance a wall spot gets a picture: in the hotel and the residential building
## less often — the space is needed for niches, mirrors, windows and panels ([WallFeatures]).
var decor_share: float = 0.9  # almost always: a blank wall read as a "square"
## Lower wall panel: height and tone of the rail above it. The hotel has tall
## wooden panels with a gilded rail (ADR-0056, decision 4).
var wainscot_height: float = BuildingRibs.SKIRTING_HEIGHT
var rail_tone := GreyboxLook.TRIM
## Lamp light and its energy by kind ([BuildingAir], ADR-0056, decision 1).
var lamp_light := BuildingAir.LAMP_LIGHT[BuildingIdentity.Kind.HOTEL]
var lamp_gain: float = BuildingAir.LAMP_GAIN[BuildingIdentity.Kind.HOTEL]
## Share of lamps hanging as a bare bulb on a wire instead of [member fixture]:
## in the residential building the shades are broken (ADR-0056, decision 5).
var bulb_share: float = 0.0
## Share of floors with a pipe under the ceiling: exposed only in the residential building, in the
## office a suspended ceiling hides them (ADR-0056, decision 5).
var pipe_share: float = 0.0
## The back wall is glass at door height, with an [OpenSpace] hall behind it (office, ADR-0056,
## decision 4): nothing hangs on the wall, there are no lower panels, pilasters or joints,
## and no room of its own at the door.
var glass_wall: bool = false


## Style of building [param identity].
static func of(identity: BuildingIdentity) -> BuildingStyle:
	var style := BuildingStyle.new()
	if identity != null:
		style.lamp_light = BuildingAir.LAMP_LIGHT[identity.kind]
		style.lamp_gain = BuildingAir.LAMP_GAIN[identity.kind]
	if identity == null or identity.is_hotel():
		style.decor_share = 0.5
		style.fixture = Fixture.CHANDELIER
		style.wainscot_height = 1.25
		style.rail_tone = WallFeatures.GILT
		style.door_hanger_share = 0.22
		style.door_tray_share = 0.12
		style.crown = Vector2(0.2, 0.14)
		style.crown_color = Color(0.46, 0.36, 0.22)
		return style
	style.runner = false
	style.panels = false
	style.sconces = false
	if identity.kind == BuildingIdentity.Kind.RESIDENTIAL:
		return _residential(style)
	style.crown = Vector2(0.06, 0.05)
	style.crown_color = Color(0.5, 0.52, 0.55)
	style.leaf_tone = Color(0.56, 0.58, 0.6)
	style.vision_glass = true
	style.frame_tone = Color(0.62, 0.64, 0.67)
	style.handle_tone = Color(0.8, 0.82, 0.85)
	style.sign_tone = Color(0.82, 0.92, 1.0)
	style.fixture = Fixture.PANEL
	style.departments = true
	style.glass_wall = true
	return style


## A residential building of the eighties (ADR-0055, decision 4): checkerboard tiles, a painted
## steel apartment door with a peephole, a dish fixture under the ceiling, doormats at the doors.
## The leaf is dark green paint: not red, the red door is the document's.
static func _residential(style: BuildingStyle) -> BuildingStyle:
	style.tile_color = Color(0.6, 0.57, 0.5)
	style.tile_alt = Color(0.17, 0.17, 0.18)
	style.tile_step = 0.3
	style.checker = true
	style.crown = Vector2(0.07, 0.04)
	style.crown_color = Color(0.4, 0.39, 0.36)
	style.leaf_tone = Color(0.24, 0.36, 0.32)
	style.frame_tone = Color(0.2, 0.28, 0.26)
	style.handle_tone = Color(0.62, 0.56, 0.4)
	style.peephole = true
	style.sign_tone = Color(0.95, 0.9, 0.76)
	style.fixture = Fixture.DOME
	style.apartment_letters = true
	style.door_mat_share = 0.55
	style.door_bag_share = 0.1
	style.flicker_share = 0.12
	style.bulb_share = 0.4
	style.pipe_share = 0.8
	style.decor_share = 0.45
	return style
