extends SceneTree
## Listens for rooms announced on the local network and prints what it hears, to find
## out whether UDP broadcast really crosses between two devices on a given network.
##   godot --headless --path . --quit-after 600000 -s tools/discovery_probe.gd -- <seconds>


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seconds := float(args[0]) if args.size() > 0 else 20.0
	var discovery := LanDiscovery.new()
	var err := discovery.start_listening()
	if err != OK:
		print("PROBE cannot listen on UDP %d (error %d): another program may be using it" % [discovery.port, err])
		quit(1)
		return
	print("PROBE listening on UDP %d for %.0f s; this PC is %s" % [discovery.port, seconds, LanDiscovery.local_addresses()])
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	var seen := {}
	while Time.get_ticks_msec() < deadline:
		var now := Time.get_ticks_msec()
		discovery.poll(now)
		for room: Dictionary in discovery.rooms(now):
			var key := "%s:%d" % [room["address"], room["port"]]
			if not seen.has(key):
				seen[key] = true
				print("PROBE heard '%s' at %s (%d/%d, open=%s)" % [room["room"], key, room["players"], room["max"], room["open"]])
		OS.delay_msec(50)
	print("PROBE done: %d room(s) heard" % seen.size())
	discovery.stop()
	quit()
