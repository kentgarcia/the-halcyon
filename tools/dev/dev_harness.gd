class_name DevHarness
extends Node
## Developer/QA entry points driven by command-line user args (after `--`):
##   --scene=<name>      jump straight into a dev scene instead of the menu
##   --seed=<n>          run seed
##   --shot=<path>       save the final composed frame (tape finish + UI) as PNG
##   --shot-frame=<n>    frame to capture (default 90)
##   --shots=f:path,...  several captures
##   --quit-frame=<n>    exit after n frames (smoke)
##   --bot=<name>        run a scripted bot (see tools/dev/bots.gd)
## None of this runs unless an arg is given, so shipping builds are unaffected.

var args: Dictionary = {}
var frame := 0
var shots: Array = []            ## [{frame, path}]
var quit_frame := -1
var scene_name := ""
var scene_node: Node = null
var bot: Node = null


func _ready() -> void:
	args = parse_args(OS.get_cmdline_user_args())
	if args.is_empty():
		set_process(false)
		return
	if not args.has("real-save"):
		SaveService.use_profile("dev")        # bots and screenshots never touch the player's save
	if args.has("shot"):
		shots.append({"frame": int(args.get("shot-frame", 90)), "path": String(args["shot"])})
	if args.has("shots"):
		for part in String(args["shots"]).split(","):
			var kv := part.split(":", true, 1)
			if kv.size() == 2:
				shots.append({"frame": int(kv[0]), "path": kv[1]})
	if args.has("quit-frame"):
		quit_frame = int(args["quit-frame"])
	if args.has("seed"):
		RunState.new_run(int(args["seed"]), 1)
	scene_name = String(args.get("scene", ""))
	if scene_name != "":
		call_deferred("_start_scene")


static func parse_args(raw: PackedStringArray) -> Dictionary:
	var out := {}
	for a in raw:
		if not a.begins_with("--"):
			continue
		var s := a.substr(2)
		var eq := s.find("=")
		if eq < 0:
			out[s] = "1"
		else:
			out[s.substr(0, eq)] = s.substr(eq + 1)
	return out


func _start_scene() -> void:
	match scene_name:
		"greybox":
			scene_node = GreyboxScene.new()
			Game.main.add_child(scene_node)
		"chunkview":
			scene_node = ChunkViewScene.new()
			Game.main.add_child(scene_node)
		"walk":
			scene_node = WalkScene.new()
			Game.main.add_child(scene_node)
			if args.has("bot"):
				bot = Bots.new()
				bot.name = "Bot"
				Game.main.add_child(bot)
				bot.call("start", String(args["bot"]), scene_node, self)
		"floor":
			_start_floor()
		"screen":
			_start_screen()
		"echo":
			_start_echo()
		_:
			push_error("DevHarness: unknown --scene=%s" % scene_name)


func _start_echo() -> void:
	## --scene=echo --clip=<hum_hold|hum_inv|foreman_*|lifeguard_*|queue_*|greeter_*> [--echo-dump=<dir>] [--echo-step=10]
	## Starts a Yellow floor session and plays the Echo clip through the camcorder (screenshot it with --shots).
	## --echo-dump=<dir> bakes the clip, prints the bake time and saves a contact sheet (every --echo-step-th frame,
	## optionally only --echo-from=<frame> --echo-count=<n>, with --echo-cols / --echo-scale)
	## to <dir>/<clip>.png instead of playing it, then quits.
	var clip := StringName(String(args.get("clip", "hum_hold")))
	Game.start_new_run(&"yellow", int(args.get("seed", 1)), {"skip_card": true, "no_director": true, "no_housekeeping": true})
	for _i in 12:
		await get_tree().process_frame
	var sess := Game.session as FloorSession
	if sess == null:
		push_error("DevHarness: no session for the echo scene")
		return
	var truth: int = RunState.Truth.HOLDS if String(clip).ends_with("_hold") else RunState.Truth.INVERTED
	if args.has("echo-dump"):
		var dir := String(args["echo-dump"])
		DirAccess.make_dir_recursive_absolute(dir)
		var frames: Array[PackedByteArray] = await EchoPlayer.bake_frames(sess, clip)
		print("DevHarness: baked %s: %d frames in %d ms (%.1f s of tape)" % [clip, frames.size(), EchoPlayer.last_bake_ms, float(frames.size()) / EchoPlayer.FPS])
		if args.has("echo-from"):
			# --echo-from=<frame> --echo-count=<n>: only a slice of the clip (look closely at one moment)
			var from := clampi(int(args["echo-from"]), 0, frames.size())
			frames = frames.slice(from, mini(frames.size(), from + int(args.get("echo-count", 12))))
		var sheet := EchoPlayer.contact_sheet(frames, int(args.get("echo-step", 10)), int(args.get("echo-cols", 4)), int(args.get("echo-scale", 2)))
		var path := "%s/%s.png" % [dir, clip]
		print("DevHarness: saved %s err=%d" % [path, sheet.save_png(path)])
		get_tree().quit(0)
		return
	EchoPlayer.play(sess, clip, truth)


func _start_screen() -> void:
	## --scene=screen --screen=<id> [--ending=checkout|desk|burn] [--burn-valid] [--skip] [--tab=n] [--demo] [--viewer] [--win=1920x1080]
	## Opens one UI screen. notebook / pause / card / suggestion_box get a live (dev-option) Yellow session.
	## --demo fills the notebook with plausible content (marks, evidence, frames, attempts, a clause) in memory.
	var id := StringName(String(args.get("screen", "menu")))
	process_mode = Node.PROCESS_MODE_ALWAYS      # screens pause the tree; the frame counter must keep running
	if args.has("win"):
		var wh := String(args["win"]).split("x")
		if wh.size() == 2:
			get_window().size = Vector2i(int(wh[0]), int(wh[1]))
			for _i in 4:
				await get_tree().process_frame
	var sargs := {}
	if id in [&"notebook", &"pause", &"card", &"suggestion_box"]:
		Game.start_new_run(&"yellow", int(args.get("seed", 1)),
			{"skip_card": true, "no_director": true, "no_housekeeping": true, "no_tape": true})
		for _i in 10:
			await get_tree().process_frame
		var sess := Game.session as FloorSession
		sargs["session"] = sess
		if id == &"card":
			sargs["mode"] = &"review"
		if args.has("demo") and sess != null:
			_demo_notebook(sess)
	if id == &"ending":
		sargs["ending"] = StringName(String(args.get("ending", "checkout")))
		if args.has("burn-valid"):
			sargs["burn_valid"] = true
	if args.has("tab"):
		sargs["tab"] = int(args["tab"])
	if id == &"menu" and args.has("saved-run"):
		SaveService.data["run"] = {"floor_id": "yellow", "guest_number": 7}     # in memory only: never saved here
	var s := Game.open(id, sargs)
	print("DevHarness: screen '%s' opened -> %s (session %s)" % [id, s, sargs.get("session")])
	if s != null and args.has("viewer") and s.has_method("open_first_frame"):
		for _i in 3:
			await get_tree().process_frame
		s.call("open_first_frame")
	if s != null and id == &"intro" and args.has("beat"):
		for _i in int(args["beat"]):
			s.call("_next_beat")
	if s != null and id == &"ending" and args.has("skip"):
		for _i in 3:
			await get_tree().process_frame
		s.call("skip")


func _demo_notebook(sess: FloorSession) -> void:
	var def := sess.def
	RunState.mark_rule(def.rules[0].id, RunState.Mark.TRUST)
	RunState.mark_rule(def.rules[1].id, RunState.Mark.LIE)
	var ev := def.evidence_for(sess.truth)
	for i in mini(3, ev.size()):
		RunState.evidence_found[ev[i].id] = true
	RunState.evidence_found[def.evidence_for(1 - sess.truth)[0].id] = true     # a stale sticker from another roll: must NOT show
	RunState.pocket = &"bulb"
	RunState.battery = 62.0
	RunState.nerve = maxi(1, RunState.nerve_max - 1)
	RunState.clause = &"walk_encouraged"
	for k in 3:
		var img := Image.create(TapeBuffer.W, TapeBuffer.H, false, Image.FORMAT_RGB8)
		for y in TapeBuffer.H:
			for x in TapeBuffer.W:
				var v := 0.15 + 0.5 * float((x + k * 23) % 32) / 32.0 * float(y) / float(TapeBuffer.H)
				img.set_pixel(x, y, Color(v * 0.9, v, v * 0.55))
		sess.add_freeze_frame(img, k == 1)
	var page := SaveService.page(def.id)
	var rule := def.entity_rule()
	(page["attempts"] as Array).clear()
	for a in [
		{"result": "blackout", "truth": 1, "t": 213.0, "cause": "hum", "rule": rule.text if rule != null else ""},
		{"result": "blackout", "truth": 0, "t": 96.0, "cause": "housekeeping", "rule": rule.text if rule != null else ""},
		{"result": "cleared", "truth": 0, "t": 402.0, "marks_ok": true},
	]:
		(page["attempts"] as Array).append(a)


func _start_floor() -> void:
	## --scene=floor --floor=yellow [--truth=0|1] [--seed=n] [--skip-card] [--no-director] [--no-housekeeping]
	##              [--clock-scale=0.05] [--bot=floor_walk]
	var opts := {"skip_card": true}
	if args.has("truth"):
		opts["truth"] = int(args["truth"])
	if args.has("no-director"):
		opts["no_director"] = true
	if args.has("no-housekeeping"):
		opts["no_housekeeping"] = true
	if args.has("clock-scale"):
		opts["clock_scale"] = float(args["clock-scale"])
	if args.has("with-card"):
		opts.erase("skip_card")
	Game.start_new_run(StringName(args.get("floor", "yellow")), int(args.get("seed", 1)), opts)
	if args.has("force-encounter"):
		_force_encounter_after(float(args["force-encounter"]))
	if args.has("bot"):
		for _i in 6:
			await get_tree().process_frame
		bot = Bots.new()
		bot.name = "Bot"
		Game.main.add_child(bot)
		scene_node = Game.session
		bot.call("start", String(args["bot"]), Game.session, self)


func _force_encounter_after(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	var s: Node = Game.session
	if s == null or s.get("director") == null:
		return
	var ok: bool = s.director.force_encounter(&"minor")
	print("DevHarness: force_encounter -> %s (entity=%s)" % [ok, s.entity])
	await get_tree().create_timer(float(args.get("encounter-watch", 12.0))).timeout
	print("DevHarness: director phase=%d history=%s" % [s.director.phase, s.director.history])


func _process(_delta: float) -> void:
	frame += 1
	if frame % 30 == 0 and args.has("trace"):
		print("DevHarness: frame %d  t=%.2fs  fps=%d" % [frame, Time.get_ticks_msec() / 1000.0, Engine.get_frames_per_second()])
	for s in shots.duplicate():
		if frame >= int(s["frame"]):
			shots.erase(s)
			_capture(String(s["path"]))
	if quit_frame >= 0 and frame >= quit_frame:
		get_tree().quit(0)
	elif quit_frame < 0 and shots.is_empty() and args.has("shot") and frame > 1:
		get_tree().quit(0)


func _capture(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		push_warning("DevHarness: cannot capture in headless mode")
		return
	if args.has("ui-debug") and Game.session != null:
		var h: Control = Game.session.get("hud")
		print("DevHarness: hud rect=%s parent=%s ui=%s" % [h.get_rect(), h.get_parent(), Game.main.ui])
		print("DevHarness: main rect=%s win=%s" % [Game.main.get_rect(), get_viewport().get_visible_rect()])
		for c in h.get_children():
			if c is Label:
				print("  label '%s' rect=%s" % [(c as Label).text, (c as Control).get_global_rect()])
	RenderingServer.force_draw(false)          # a window the compositor stopped scheduling is not redrawn by itself
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("DevHarness: saved %s (%dx%d) err=%d" % [path, img.get_width(), img.get_height(), err])
	if Game.main != null and args.has("raw"):
		var raw := Game.main.game_viewport.get_texture().get_image()
		raw.save_png(path.get_basename() + "_raw.png")
		print("DevHarness: raw viewport %dx%d" % [raw.get_width(), raw.get_height()])
