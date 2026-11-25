extends Node
## Top-level state machine: Boot -> Menu -> Run -> (Inspection | Blackout -> Autopsy) -> ... -> Ending
## (SPEC 12.2). Owns the references the rest of the game needs (Main, current Stage, the live FloorSession),
## the screen stack, and the orchestration of runs and floors.

enum State { BOOT, MENU, RUN, BLACKOUT, AUTOPSY, INSPECTION, ENDING }

signal state_changed(new_state: int, old_state: int)

const DEV_HARNESS_PATH := "res://tools/dev/dev_harness.gd"

const SCREENS := {
	&"menu": "res://ui/screens/main_menu.gd",
	&"card": "res://ui/screens/card_screen.gd",
	&"notebook": "res://ui/screens/notebook_screen.gd",
	&"suggestion_box": "res://ui/screens/suggestion_box_screen.gd",
	&"inspection": "res://ui/screens/inspection_screen.gd",
	&"autopsy": "res://ui/screens/autopsy_screen.gd",
	&"pause": "res://ui/screens/pause_screen.gd",
	&"settings": "res://ui/screens/settings_screen.gd",
	&"ending": "res://ui/screens/ending_screen.gd",
	&"intro": "res://ui/screens/intro_screen.gd",
}

var state: int = State.BOOT
var main: Main = null
var stage: Stage = null
var session: Node = null              ## the live FloorSession (typed loosely: avoids a class cycle with props)
var dev_opts: Dictionary = {}         ## --floor/--truth/--no-director... forwarded to FloorSession.setup
var _screens: Array[ScreenBase] = []
var _busy := false


func attach_main(m: Main) -> void:
	main = m
	AudioDirector.process_mode = Node.PROCESS_MODE_ALWAYS
	var harness: Node = _make_dev_harness()
	if harness != null:
		harness.name = "DevHarness"
		m.add_child(harness)
	change_state(State.MENU)
	if harness == null or (harness.get("args") as Dictionary).is_empty():
		call_deferred("show_menu")


func _make_dev_harness() -> Node:
	## The developer harness (command-line scenes, bots, screenshots) is optional: it only loads when
	## user args were passed AND the script exists, so a build without tools/ behaves like a shipping build.
	if OS.get_cmdline_user_args().is_empty() or not ResourceLoader.exists(DEV_HARNESS_PATH):
		return null
	var script := load(DEV_HARNESS_PATH) as GDScript
	return script.new() if script != null else null


func change_state(new_state: int) -> void:
	if new_state == state:
		return
	var old := state
	state = new_state
	state_changed.emit(new_state, old)


func make_stage() -> Stage:
	## A fresh, empty stage inside the game viewport (the previous one is freed).
	if stage != null and is_instance_valid(stage):
		stage.queue_free()
	stage = Stage.new()
	main.game_viewport.add_child(stage)
	AudioDirector.attach_world(stage)
	return stage


# --- screens ---------------------------------------------------------------------------------

func open(screen_id: StringName, args: Dictionary = {}) -> ScreenBase:
	var path: String = SCREENS.get(screen_id, "")
	if path == "" or not ResourceLoader.exists(path):
		push_error("Game.open: no screen '%s' (%s)" % [screen_id, path])
		return null
	var s := (load(path) as GDScript).new() as ScreenBase
	if s == null:
		push_error("Game.open: %s is not a ScreenBase" % path)
		return null
	s.name = String(screen_id).capitalize().replace(" ", "")
	s.setup(args)
	_screens.append(s)
	main.ui.add_child(s)
	s.closed.connect(_on_screen_closed.bind(s))
	_apply_screen_state()
	return s


func _on_screen_closed(_result: Variant, s: ScreenBase) -> void:
	_screens.erase(s)
	_apply_screen_state()


func screen_open() -> bool:
	_screens = _screens.filter(func(x): return is_instance_valid(x))
	return not _screens.is_empty()


func close_all_screens() -> void:
	for s in _screens.duplicate():
		if is_instance_valid(s):
			s.queue_free()
	_screens.clear()
	_apply_screen_state()


func _apply_screen_state() -> void:
	_screens = _screens.filter(func(x): return is_instance_valid(x) and not x.is_queued_for_deletion())
	var pause := false
	for s in _screens:
		pause = pause or s.pauses_world
	get_tree().paused = pause
	var headless := DisplayServer.get_name() == "headless"
	if not headless:
		var want_free := not _screens.is_empty() or state == State.MENU or session == null
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if want_free else Input.MOUSE_MODE_CAPTURED


func show_menu() -> void:
	close_all_screens()
	_teardown_session()
	change_state(State.MENU)
	main.set_fade(0.0)
	AudioDirector.stop_all_ambience()
	var m := open(&"menu")
	if m != null:
		m.closed.connect(_on_menu_closed)


func _on_menu_closed(result: Variant) -> void:
	var r: Dictionary = result if result is Dictionary else {}
	match StringName(r.get("action", &"")):
		&"new":
			start_new_run()
		&"continue":
			continue_run()


# --- runs ------------------------------------------------------------------------------------

func start_new_run(first_floor: StringName = &"", seed_value: int = -1, opts: Dictionary = {}) -> void:
	_teardown_session()
	close_all_screens()
	var sd := seed_value
	if sd < 0:
		sd = int(Time.get_unix_time_from_system()) * 7919 + int(Time.get_ticks_usec() % 100003)
	var guest: int = SaveService.take_guest_number()
	RunState.new_run(sd, guest)
	SaveService.data["stats"]["runs_started"] = int(SaveService.data["stats"].get("runs_started", 0)) + 1
	SaveService.save()
	dev_opts = opts
	EventBus.run_started.emit()
	var fid := first_floor if first_floor != &"" else FloorCatalog.ORDER[0]
	if first_floor == &"" and not bool(SaveService.data.get("intro_seen", false)):
		var intro := open(&"intro")
		if intro != null:
			await intro.closed
		SaveService.data["intro_seen"] = true
		SaveService.save()
	_begin_floor(fid)


func continue_run() -> void:
	var d: Dictionary = SaveService.data.get("run", {})
	if d.is_empty():
		start_new_run()
		return
	_teardown_session()
	close_all_screens()
	RunState.from_dict(d)
	dev_opts = {}
	_begin_floor(RunState.floor_id if RunState.floor_id != &"" else FloorCatalog.ORDER[0], true)


func has_saved_run() -> bool:
	return not (SaveService.data.get("run", {}) as Dictionary).is_empty()


func _begin_floor(fid: StringName, resumed: bool = false) -> void:
	if _busy:
		return
	_busy = true
	var idx := FloorCatalog.index_of(fid)
	if not resumed:
		RunState.begin_floor(fid, idx)
	else:
		RunState.floor_id = fid
		RunState.floor_index = idx
		RunState.begin_floor(fid, idx)
	_apply_courtesies()
	var def := FloorCatalog.get_def(fid)
	var s := FloorSession.new()
	s.name = "FloorSession"
	main.add_child(s)
	s.ready_for_card.connect(_on_session_card)
	s.floor_cleared.connect(_on_floor_cleared)
	s.blacked_out.connect(func(info: Dictionary) -> void: _on_blacked_out(s, info))
	var opts := dev_opts.duplicate()
	opts["mastered"] = SaveService.is_cleared(fid)
	s.setup(def, opts)
	change_state(State.RUN)
	_busy = false
	_apply_screen_state()


func _teardown_session() -> void:
	if session != null and is_instance_valid(session):
		(session as FloorSession).teardown()
	session = null


func _apply_courtesies() -> void:
	for c in RunState.courtesies:
		match c:
			&"courtesy_battery":
				RunState.set_battery(100.0)
			&"courtesy_frame":
				RunState.freeze_frames_left += 1
			&"courtesy_bulb", &"courtesy_fuse", &"courtesy_crowbar":
				if RunState.pocket == &"":
					RunState.set_pocket(StringName(String(c).replace("courtesy_", "")))
	RunState.courtesies.clear()


# --- the card --------------------------------------------------------------------------------

func _on_session_card(s: FloorSession) -> void:
	if bool(dev_opts.get("skip_card", false)):
		s.begin_play()
		return
	var card := open(&"card", {"session": s, "mode": &"issue"})
	if card == null:
		s.begin_play()
		return
	await card.closed
	AudioDirector.clear_pa()
	if is_instance_valid(s) and session == s:
		s.begin_play()


# --- inspection (elevator, SPEC 3.4) ---------------------------------------------------------

func inspection_report(s: FloorSession) -> Dictionary:
	var rows: Array[Dictionary] = []
	var all_ok := true
	for r in s.def.rules:
		var truth_of_rule := r.is_true_for(s.truth)
		var mark := RunState.mark_of(r.id)
		var status := &"unmarked"
		if mark != RunState.Mark.UNKNOWN:
			var ok := (mark == RunState.Mark.TRUST) == truth_of_rule
			status = &"correct" if ok else &"wrong"
		if r.kind == RuleDef.Kind.ENTITY and status != &"correct":
			all_ok = false
		rows.append({"rule": r, "true": truth_of_rule, "mark": mark, "status": status})
	var clause_options: Array[ClauseDef] = []
	for cd in FloorCatalog.clause_defs():
		var rule := s.def.rule_by_id(cd.source_rule)
		if rule == null or not rule.is_true_for(s.truth):
			continue
		if cd.requires_holds and s.truth != RunState.Truth.HOLDS:
			continue
		clause_options.append(cd)
	return {
		"def": s.def,
		"truth": s.truth,
		"rows": rows,
		"entity_ok": all_ok,
		"verdict": RunState.verdict,
		"verdict_ok": RunState.verdict_correct,
		"clause_options": clause_options,
		"current_clause": RunState.clause,
		"courtesies": courtesy_offer(),
	}


func courtesy_offer() -> Array[Dictionary]:
	if RunState.verdict_correct != 1:
		return []
	var items := [&"bulb", &"fuse", &"crowbar"]
	var pick: StringName = RngStreams.pick(RunState.stream(&"loot"), items)
	return [
		{"id": &"courtesy_battery", "label": "A full battery"},
		{"id": &"courtesy_frame", "label": "One extra Freeze Frame"},
		{"id": StringName("courtesy_%s" % pick), "label": "A %s for your pocket" % Items.display_name(pick).to_lower()},
	]


func _on_floor_cleared(s: FloorSession) -> void:
	change_state(State.INSPECTION)
	var fid := s.def.id
	if not RunState.cleared_floors.has(fid):
		RunState.cleared_floors.append(fid)
	var report := inspection_report(s)
	RunState.entity_mark_ok[fid] = bool(report["entity_ok"])
	if bool(report["entity_ok"]):
		RunState.correct_inspections += 1
	else:
		RunState.wrong_inspections += 1
	SaveService.mark_cleared(fid)
	SaveService.log_attempt(fid, {"result": "cleared", "truth": s.truth, "t": snappedf(s.play_time, 1.0), "marks_ok": bool(report["entity_ok"])})
	AudioDirector.say(&"inspection_open")
	var insp := open(&"inspection", {"session": s, "report": report})
	if insp == null:
		_advance_after_floor(s)
		return
	var res: Variant = await insp.closed
	var choice: Dictionary = res if res is Dictionary else {}
	_apply_inspection_choice(choice)
	AudioDirector.say(&"inspection_done")
	_advance_after_floor(s)


func _apply_inspection_choice(choice: Dictionary) -> void:
	var clause := StringName(choice.get("clause", &""))
	if clause != &"":
		RunState.clause = clause
		RunState.clause_void = false
		EventBus.clause_changed.emit(clause)
	var courtesy := StringName(choice.get("courtesy", &""))
	if courtesy != &"":
		RunState.courtesies.append(courtesy)


func _advance_after_floor(s: FloorSession) -> void:
	var fid := s.def.id
	var next := FloorCatalog.next_of(fid)
	_teardown_session()
	if next == &"":
		change_state(State.ENDING)
		on_ending(&"checkout")
		return
	# checkpoint: the elevator is a save point
	RunState.floor_id = next
	RunState.floor_index = FloorCatalog.index_of(next)
	SaveService.data["run"] = RunState.to_dict()
	SaveService.save()
	_begin_floor(next)


# --- blackout / autopsy (SPEC 4.4) -----------------------------------------------------------

func _on_blacked_out(s: FloorSession, info: Dictionary) -> void:
	change_state(State.AUTOPSY)
	var fid := s.def.id
	var rule := s.def.entity_rule()
	SaveService.log_attempt(fid, {
		"result": "blackout", "truth": s.truth, "t": snappedf(s.play_time, 1.0),
		"cause": String(info.get("cause", "")), "rule": rule.text if rule != null else "",
	})
	var frames: Array = info.get("frames", [])
	if not frames.is_empty():
		SaveService.save_death_tape(fid, s.truth, RunState.guest_number, frames, float(info.get("fps", 10.0)))
	SaveService.save()
	var scr := open(&"autopsy", {"session": s, "info": info})
	if scr != null:
		await scr.closed
	_teardown_session()
	RunState.reroll_floor_after_blackout()
	_begin_floor(fid)


# --- endings ---------------------------------------------------------------------------------

func on_ending(ending_id: StringName) -> void:
	## Called by the Lobby (or the run ending). The ending screen offers a new run / menu.
	change_state(State.ENDING)
	var recorded := ending_id
	if ending_id == &"burn" and not EndingScreen.burn_is_valid():
		recorded = &"burn_failed"          # the ending screen shows the failed burn; don't credit a burn that did not happen
	SaveService.add_ending(recorded)
	SaveService.data["run"] = {}
	SaveService.save()
	EventBus.run_ended.emit(ending_id)
	var scr := open(&"ending", {"ending": ending_id})
	if scr != null:
		var res: Variant = await scr.closed
		if res is Dictionary and StringName((res as Dictionary).get("action", &"")) == &"new":
			start_new_run()
		else:
			show_menu()
	else:
		show_menu()


# --- helpers used by props -------------------------------------------------------------------

func open_suggestion_box(s: FloorSession) -> void:
	open(&"suggestion_box", {"session": s})


func open_notebook(s: FloorSession) -> void:
	if not screen_open():
		open(&"notebook", {"session": s})
