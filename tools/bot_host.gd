extends SceneTree
## Headless room host that plays like a bot, for tests with real devices. It opens a
## room, waits for enough players, starts rounds, plays words, prints what happens.
##   godot --headless --path . --quit-after 600000 -s tools/bot_host.gd -- <name> <min players> <rounds> <round seconds>
## A phone or the emulator joins it by address (the emulator reaches this PC at 10.0.2.2).

const WORDS_PER_MINUTE := 14.0

var _dictionary := WordDictionary.new()
var _generator := BoardGenerator.new()
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var host_name := args[0] if args.size() > 0 else "Mesa"
	var min_players := int(args[1]) if args.size() > 1 else 2
	var rounds := int(args[2]) if args.size() > 2 else 2
	var round_seconds := float(args[3]) if args.size() > 3 else 40.0
	_rng.randomize()
	if not _dictionary.load_from_file("res://data/words_es.txt"):
		print("BOTHOST error: dictionary not found")
		quit(1)
		return
	_run(host_name, min_players, rounds, round_seconds)
	quit()


func _run(host_name: String, min_players: int, rounds: int, round_seconds: float) -> void:
	var host := RoomHost.new()
	host.round_seconds = round_seconds
	host.countdown_seconds = 3.0
	host.announce_enabled = true
	host.board_factory = func() -> Dictionary:
		var board := _generator.generate_playable(_dictionary, 100)
		return {"board": board, "words": BoardSolver.solve(board, _dictionary)}
	var err := host.open(host_name)
	if err != OK:
		print("BOTHOST error: cannot open a room (%d)" % err)
		return
	print("BOTHOST open name=%s port=%d addresses=%s" % [host_name, host.port, LanDiscovery.local_addresses()])
	host.roster_changed.connect(func() -> void:
		var names := []
		for entry: Dictionary in host.session.players():
			names.append("%s%s" % [entry["name"], "" if entry["connected"] else "(off)"])
		print("BOTHOST roster %s" % [names]))
	host.round_started.connect(func(board: PackedStringArray, _c: float, _d: float) -> void:
		print("BOTHOST round %d starts board=%s" % [host.session.round_number, ",".join(board)]))
	host.round_finished.connect(func(ranking: Array, _table: Array) -> void:
		var line := []
		for entry: Dictionary in ranking:
			line.append("%d.%s=%d" % [entry["rank"], entry["name"], entry["score"]])
		print("BOTHOST results %s" % [line]))

	# One shared Dictionary: lambdas capture plain local variables by value.
	var state := {"finished": 0, "started": false, "waiting_since": Time.get_ticks_msec()}
	var next_word_at := 0
	var last_join_ms := Time.get_ticks_msec()
	var known_players := 1
	var deadline := Time.get_ticks_msec() + 20 * 60 * 1000
	host.round_finished.connect(func(_r: Array, _t: Array) -> void:
		state["finished"] += 1
		state["started"] = false
		state["waiting_since"] = Time.get_ticks_msec())
	while Time.get_ticks_msec() < deadline and state["finished"] < rounds:
		host.poll()
		var now := Time.get_ticks_msec()
		var connected := host.session.connected_count()
		if connected != known_players:
			known_players = connected
			last_join_ms = now
		if not state["started"] and connected >= min_players \
				and now - last_join_ms > 2500 and now - state["waiting_since"] > 4000:
			if host.start_round():
				state["started"] = true
		if state["started"] and host.session.phase == RoomSession.Phase.PLAYING \
				and host.countdown_left() <= 0.0 and now >= next_word_at:
			_play_a_word(host)
			next_word_at = now + int(60000.0 / WORDS_PER_MINUTE * _rng.randf_range(0.6, 1.4))
		OS.delay_msec(10)
	print("BOTHOST done rounds=%d" % state["finished"])
	host.close()
	for i in 40:  # let the goodbye through
		host.poll()
		OS.delay_msec(10)


func _play_a_word(host: RoomHost) -> void:
	var words: Array = host.session._valid_words.keys()
	if words.is_empty():
		return
	words.sort_custom(func(a: String, b: String) -> bool: return a.length() < b.length() or (a.length() == b.length() and a < b))
	# Short words first: more likely to coincide with other players and cancel.
	var pick: String = words[_rng.randi_range(0, mini(words.size() - 1, 60))]
	host.submit_local_word(pick)
