extends SceneTree
## Headless guest that plays like a bot, for tests with real devices.
##   godot --headless --path . --quit-after 600000 -s tools/bot_client.gd -- <host address> <port> <name> <minutes to stay>
## It joins a room, and in every round it solves the board and submits words at a human pace.

const WORDS_PER_MINUTE := 12.0

var _dictionary := WordDictionary.new()
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("BOT usage: -- <host address> <port> [name] [minutes]")
		quit(1)
		return
	var address := args[0]
	var port := int(args[1])
	var bot_name := args[2] if args.size() > 2 else "Bot"
	var minutes := float(args[3]) if args.size() > 3 else 5.0
	_rng.randomize()
	if not _dictionary.load_from_file("res://data/words_es.txt"):
		print("BOT error: dictionary not found")
		quit(1)
		return
	_run(address, port, bot_name, minutes)
	quit()


func _run(address: String, port: int, bot_name: String, minutes: float) -> void:
	var client := RoomClient.new()
	var state := {"joined": false, "closed": false, "words": [], "next_at": 0, "play_from": 0, "play_until": 0}
	client.joined.connect(func(final_name: String, room: String) -> void:
		state["joined"] = true
		print("BOT %s joined room '%s' as '%s'" % [bot_name, room, final_name]))
	client.join_failed.connect(func(reason: String) -> void:
		print("BOT %s join failed: %s" % [bot_name, reason])
		state["closed"] = true)
	client.room_closed.connect(func(reason: String) -> void:
		print("BOT %s room closed: %s" % [bot_name, reason])
		state["closed"] = true)
	client.round_started.connect(func(board: PackedStringArray, countdown: float, duration: float) -> void:
		var solutions := BoardSolver.solve(board, _dictionary)
		var words: Array = solutions.keys()
		words.sort_custom(func(a: String, b: String) -> bool: return a.length() < b.length() or (a.length() == b.length() and a < b))
		state["words"] = words.slice(0, mini(words.size(), 70))
		var now := Time.get_ticks_msec()
		state["play_from"] = now + int(countdown * 1000.0)
		state["play_until"] = now + int((countdown + duration) * 1000.0)
		state["next_at"] = state["play_from"] + 1500
		print("BOT %s round %d: %d words on the board" % [bot_name, client.round_number, solutions.size()]))
	client.round_finished.connect(func(ranking: Array, _table: Array) -> void:
		var line := []
		for entry: Dictionary in ranking:
			line.append("%d.%s=%d" % [entry["rank"], entry["name"], entry["score"]])
		print("BOT %s results %s" % [bot_name, line]))

	var err := client.connect_to(address, port, bot_name)
	if err != OK:
		print("BOT %s cannot connect (%d)" % [bot_name, err])
		return
	var deadline := Time.get_ticks_msec() + int(minutes * 60000.0)
	while Time.get_ticks_msec() < deadline and not state["closed"]:
		client.poll()
		var now := Time.get_ticks_msec()
		if state["joined"] and now >= state["play_from"] and now < state["play_until"] and now >= state["next_at"] \
				and not state["words"].is_empty():
			client.submit_word(state["words"][_rng.randi_range(0, state["words"].size() - 1)])
			state["next_at"] = now + int(60000.0 / WORDS_PER_MINUTE * _rng.randf_range(0.6, 1.4))
		OS.delay_msec(10)
	client.leave()
	print("BOT %s done" % bot_name)
