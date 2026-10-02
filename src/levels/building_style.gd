class_name BuildingStyle
extends RefCounted

## Вид коридора по типу здания (ADR-0048, ADR-0055): чем отель, офис и жилой
## дом отличаются друг от друга, кроме обстановки.
##
## Раньше тип здания менял фактуры стен, металл табличек и набор мебели, а
## двери, светильники, дорожка и карниз были одни на оба — и коридоры читались
## одинаковыми (замечание пользователя, 2026-09-30). Здесь всё, что у типа
## своё, одним местом: пол, двери, светильники, бра, таблички. Механика одна —
## лампа бьётся, дверь открывается одинаково, меняется только вид.
##
## Без узлов: строят по нему [FloorDetail], [Door], [Lamp], [BuildingProps].

## Светильник этажа: подвесной плафон отеля, офисная лампа дневного света или
## стеклянная тарелка жилого дома.
enum Fixture { PENDANT, PANEL, DOME }

## Отделы на табличках офиса.
const DEPARTMENTS: PackedStringArray = [
	"ACCOUNTS", "LEGAL", "SALES", "ARCHIVE", "PAYROLL", "RESEARCH", "BOARD", "SECURITY"
]

## Ковровая дорожка вдоль коридора: только в отеле. В офисе — ковровая плитка
## во весь пол, в жилом доме — плитка шахматкой.
var runner: bool = true
## Плитка во весь пол: цвет и шаг сетки швов, м.
var tile_color := Color(0.2, 0.22, 0.25)
var tile_step: float = 0.6
## Шахматка: через одну плитку — второй цвет (жилой дом, ADR-0055, решение 4).
var checker: bool = false
var tile_alt := Color(0.16, 0.16, 0.17)
## Карниз под потолком: у отеля — лепной, выше и с выносом; у офиса — узкий.
var crown := Vector2(0.12, 0.1)
var crown_color := Color(0.3, 0.3, 0.32)
## Створка: тон, филёнки (отель) или стекло в створке (офис), тон коробки и
## ручки.
var leaf_tone := GreyboxLook.DOOR
var panels: bool = true
var vision_glass: bool = false
var frame_tone := Color(0.26, 0.2, 0.14)
var handle_tone := Color(0.78, 0.64, 0.32)
## Глазок в створке: у квартир.
var peephole: bool = false
## Табло над дверью: тёплое у отеля, холодное белое у офиса.
var sign_tone := GreyboxLook.SIGN_WARM
## Светильник этажа.
var fixture: Fixture = Fixture.PENDANT
## Бра на пилястрах — только в отеле.
var sconces: bool = true
## Табличка у двери: у отеля — номер, у офиса — отдел и номер, у квартиры —
## этаж и буква, как 12C.
var departments: bool = false
var apartment_letters: bool = false
## Мелочи у дверей номеров: табличка «Не беспокоить» на ручке и поднос или
## газета у порога — доля дверей.
var door_hanger_share: float = 0.0
var door_tray_share: float = 0.0
## Мелочи у дверей квартир: коврик у порога и пакет с покупками — доля дверей.
var door_mat_share: float = 0.0
var door_bag_share: float = 0.0
## Доля ламп, что мигают: у жилого дома трубки старые (ADR-0055, решение 4).
var flicker_share: float = 0.0
## Свет ламп и его сила по типу ([BuildingAir], ADR-0056, решение 1).
var lamp_light := BuildingAir.LAMP_LIGHT[BuildingIdentity.Kind.HOTEL]
var lamp_gain: float = 1.0


## Стиль здания [param identity].
static func of(identity: BuildingIdentity) -> BuildingStyle:
	var style := BuildingStyle.new()
	if identity != null:
		style.lamp_light = BuildingAir.LAMP_LIGHT[identity.kind]
		style.lamp_gain = BuildingAir.LAMP_GAIN[identity.kind]
	if identity == null or identity.is_hotel():
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
	return style


## Жилой дом восьмидесятых (ADR-0055, решение 4): плитка шахматкой, крашеная
## стальная дверь квартиры с глазком, тарелка под потолком, коврики у дверей.
## Створка — тёмно-зелёная краска: не красная, красная дверь — у документа.
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
	return style
