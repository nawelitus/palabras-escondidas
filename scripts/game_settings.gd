extends Node
## Autoload: active skin, high score, sound/vibration switches and their persistence.

signal skin_changed(skin: GameSkin)
signal duration_changed(index: int)

const SAVE_PATH := "user://save.cfg"
## The colorful skin (its place in SKIN_PATHS) is the one a new player starts with.
const DEFAULT_SKIN_INDEX := 1
const SKIN_PATHS: Array[String] = [
	"res://skins/wood.tres",
	"res://skins/colorful.tres",
	"res://skins/dark.tres",
]

## Index of the chosen RoundLength, used by solo games and by the rooms this device hosts.
var duration_index := RoundLength.DEFAULT_INDEX
var sound_enabled := true
var haptics_enabled := true
## Name typed for multiplayer rooms; remembered so it is only typed once.
var player_name := ""

## Best solo score of the current round length (every length has its own record).
var high_score: int:
	get:
		return _high_scores[duration_index]

var _skins: Array[GameSkin] = []
var _skin_index := DEFAULT_SKIN_INDEX
var _high_scores: Array[int] = []


func _ready() -> void:
	_high_scores.resize(RoundLength.count())
	_high_scores.fill(0)
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


func cycle_duration() -> void:
	duration_index = (duration_index + 1) % RoundLength.count()
	_save()
	duration_changed.emit(duration_index)


func set_sound_enabled(value: bool) -> void:
	sound_enabled = value
	_save()


func set_haptics_enabled(value: bool) -> void:
	haptics_enabled = value
	_save()


func set_player_name(value: String) -> void:
	if value == player_name:
		return
	player_name = value
	_save()


## Stores the score if it beats the record. Returns true on a new record.
func submit_score(score: int) -> bool:
	if score <= high_score:
		return false
	_high_scores[duration_index] = score
	_save()
	return true


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	# Records saved before the scoring table changed ("high_score") are not comparable: dropped.
	var saved_scores: Array = config.get_value("player", "high_scores", [])
	for i in mini(saved_scores.size(), _high_scores.size()):
		_high_scores[i] = maxi(0, int(saved_scores[i]))
	duration_index = RoundLength.clamp_index(int(config.get_value("player", "duration_index", RoundLength.DEFAULT_INDEX)))
	_skin_index = clampi(int(config.get_value("player", "skin_index", DEFAULT_SKIN_INDEX)), 0, _skins.size() - 1)
	sound_enabled = bool(config.get_value("player", "sound_enabled", true))
	haptics_enabled = bool(config.get_value("player", "haptics_enabled", true))
	player_name = String(config.get_value("player", "player_name", ""))


func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("player", "high_scores", _high_scores)
	config.set_value("player", "duration_index", duration_index)
	config.set_value("player", "skin_index", _skin_index)
	config.set_value("player", "sound_enabled", sound_enabled)
	config.set_value("player", "haptics_enabled", haptics_enabled)
	config.set_value("player", "player_name", player_name)
	config.save(SAVE_PATH)
