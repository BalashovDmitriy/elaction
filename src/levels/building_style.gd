class_name BuildingStyle
extends RefCounted

## Вид коридора по типу здания (ADR-0048): чем отель отличается от офиса,
## кроме обстановки.
##
## Раньше тип здания менял фактуры стен, металл табличек и набор мебели, а
## двери, светильники, дорожка и карниз были одни на оба — и коридоры читались
## одинаковыми (замечание пользователя, 2026-09-30). Здесь всё, что у типа
## своё, одним местом: пол, двери, светильники, бра, таблички. Механика одна —
## лампа бьётся, дверь открывается одинаково, меняется только вид.
##
## Без узлов: строят по нему [FloorDetail], [Door], [Lamp], [BuildingProps].

## Светильник этажа: подвесной плафон отеля или офисная лампа дневного света.
enum Fixture { PENDANT, PANEL }

## Отделы на табличках офиса.
const DEPARTMENTS: PackedStringArray = [
	"ACCOUNTS", "LEGAL", "SALES", "ARCHIVE", "PAYROLL", "RESEARCH", "BOARD", "SECURITY"
]

## Ковровая дорожка вдоль коридора: только в отеле. В офисе — ковровая плитка
## во весь пол.
var runner: bool = true
## Ковровая плитка офиса: цвет и шаг сетки швов, м.
var tile_color := Color(0.2, 0.22, 0.25)
var tile_step: float = 0.6
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
## Табло над дверью: тёплое у отеля, холодное белое у офиса.
var sign_tone := GreyboxLook.SIGN_WARM
## Светильник этажа.
var fixture: Fixture = Fixture.PENDANT
## Бра на пилястрах — только в отеле.
var sconces: bool = true
## Табличка у двери: у отеля — номер, у офиса — отдел и номер.
var departments: bool = false
## Мелочи у дверей номеров: табличка «Не беспокоить» на ручке и поднос или
## газета у порога — доля дверей.
var door_hanger_share: float = 0.0
var door_tray_share: float = 0.0


## Стиль здания [param identity].
static func of(identity: BuildingIdentity) -> BuildingStyle:
	var style := BuildingStyle.new()
	if identity == null or identity.is_hotel():
		style.door_hanger_share = 0.22
		style.door_tray_share = 0.12
		style.crown = Vector2(0.2, 0.14)
		style.crown_color = Color(0.46, 0.36, 0.22)
		return style
	style.runner = false
	style.crown = Vector2(0.06, 0.05)
	style.crown_color = Color(0.5, 0.52, 0.55)
	style.leaf_tone = Color(0.56, 0.58, 0.6)
	style.panels = false
	style.vision_glass = true
	style.frame_tone = Color(0.62, 0.64, 0.67)
	style.handle_tone = Color(0.8, 0.82, 0.85)
	style.sign_tone = Color(0.82, 0.92, 1.0)
	style.fixture = Fixture.PANEL
	style.sconces = false
	style.departments = true
	return style
