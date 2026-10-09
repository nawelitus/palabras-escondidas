class_name RoundLength
extends RefCounted
## The three round lengths the player can pick, for solo games and for rooms.
## An index into these arrays is what gets saved and passed around.

const NAMES: Array[String] = ["Rápida", "Normal", "Extendida"]
const SECONDS: Array[float] = [60.0, 140.0, 185.0]
const DEFAULT_INDEX := 1


static func count() -> int:
	return SECONDS.size()


static func clamp_index(index: int) -> int:
	return clampi(index, 0, SECONDS.size() - 1)


static func seconds(index: int) -> float:
	return SECONDS[clamp_index(index)]


## "2:20"
static func clock(index: int) -> String:
	var whole := int(seconds(index))
	return "%d:%02d" % [whole / 60, whole % 60]


## "Normal · 2:20"
static func label(index: int) -> String:
	return "%s · %s" % [NAMES[clamp_index(index)], clock(index)]


## "2 minutos y 20 segundos", for sentences.
static func spoken(index: int) -> String:
	var whole := int(seconds(index))
	var minutes := whole / 60
	var rest := whole % 60
	var text := "%d %s" % [minutes, "minuto" if minutes == 1 else "minutos"]
	if rest > 0:
		text += " y %d %s" % [rest, "segundo" if rest == 1 else "segundos"]
	return text
