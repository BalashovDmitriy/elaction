class_name Release
extends RefCounted

## Game version and the startup line.
##
## The version lives in one place, `config/version` in `project.godot`
## ([ADR-0013](../../docs/adr/0013-release-and-versioning.md), item 3). Everyone who
## needs it takes it from here: the main menu corner, the log line and, through
## `tools/version.py`, the export presets and the release tag.
##
## A class without nodes or state: it is queried from the menu, from the entry point
## and from a test, and there is no point in creating an autoload for two lines.

## Project setting key that holds the version.
const SETTING := "application/config/version"

## In case the setting is missing altogether: better an obviously non-game version in
## the screen corner than an empty spot nobody will ask about.
const UNKNOWN := "0.0.0"


## Game version, for example `0.9.0`.
static func version() -> String:
	var found: Variant = ProjectSettings.get_setting(SETTING, UNKNOWN)
	var text := str(found)
	return text if not text.is_empty() else UNKNOWN


## The same with the letter `v`, as in the tag and the archive name.
static func tag() -> String:
	return "v" + version()


## The line the game prints to the log at startup.
##
## It is also the marker for `tools/smoke.py`: a built binary that did not print it does
## not count as started, even if the process exited with zero (ADR-0013, item 6). So the
## format must not change without fixing smoke.
static func banner() -> String:
	return "elaction %s · %s" % [version(), OS.get_name()]
