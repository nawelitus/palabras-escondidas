extends Node
## Autoload: active skin, high score, sound/vibration switches and their persistence.

signal skin_changed(skin: GameSkin)

const SAVE_PATH := "user://save.cfg"
const SKIN_PATHS: Array[String] = [
	"res://skins/wood.tres",
	"res://skins/colorful.tres",
	"res://skins/dark.tres",
]

var high_score := 0
var sound_enabled := true
var haptics_enabled := true

var _skins: Array[GameSkin] = []
var _skin_index := 0


func _ready() -> void:
	for path in SKIN_PATHS:
		var skin := load(path) as GameSkin
		if skin == null:
			push_error("Cannot load skin: %s" % path)
		else:
			_skins.append(skin)
	_load()


func current_skin() -> GameSkin:
	return _skins[_skin_index]


func cycle_skin() -> void:
	_skin_index = (_skin_index + 1) % _skins.size()
	_save()
	skin_changed.emit(current_skin())


func set_sound_enabled(value: bool) -> void:
	sound_enabled = value
	_save()


func set_haptics_enabled(value: bool) -> void:
	haptics_enabled = value
	_save()


## Stores the score if it beats the record. Returns true on a new record.
func submit_score(score: int) -> bool:
	if score <= high_score:
		return false
	high_score = score
	_save()
	return true


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	high_score = int(config.get_value("player", "high_score", 0))
	_skin_index = clampi(int(config.get_value("player", "skin_index", 0)), 0, _skins.size() - 1)
	sound_enabled = bool(config.get_value("player", "sound_enabled", true))
	haptics_enabled = bool(config.get_value("player", "haptics_enabled", true))


func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("player", "high_score", high_score)
	config.set_value("player", "skin_index", _skin_index)
	config.set_value("player", "sound_enabled", sound_enabled)
	config.set_value("player", "haptics_enabled", haptics_enabled)
	config.save(SAVE_PATH)
