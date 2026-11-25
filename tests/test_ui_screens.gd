extends TestCase
## UI screens (SPEC 11): every screen script builds headlessly under a Control, is operable without the mouse
## (a button has focus), closes with the documented result shape, and the notebook obeys the Fairness rules
## (never says which rule is the entity rule; never lists evidence that was not found or is not true this run).
## Global state touched here (Settings, RunState marks/clause/evidence, SaveService pages) is snapshotted and restored.

const SETTINGS_PATH := "user://settings.cfg"

var _host: Control = null
var _settings_snapshot: Dictionary = {}
var _settings_file: PackedByteArray = PackedByteArray()
var _settings_file_existed := false
var _run_snapshot: Dictionary = {}
var _save_run: Dictionary = {}
var _attempts_snapshot: Array = []


func before_each() -> void:
	_host = Control.new()
	_host.name = "UiTestHost"
	_host.size = Vector2(1280, 720)
	tree.root.add_child(_host)
	for p in Settings._persisted_props():
		_settings_snapshot[p] = Settings.get(p)
	_settings_file_existed = FileAccess.file_exists(SETTINGS_PATH)
	if _settings_file_existed:
		_settings_file = FileAccess.get_file_as_bytes(SETTINGS_PATH)
	_run_snapshot = {
		"marks": RunState.marks.duplicate(), "evidence": RunState.evidence_found.duplicate(), "clause": RunState.clause,
		"void": RunState.clause_void, "pocket": RunState.pocket, "battery": RunState.battery, "nerve": RunState.nerve,
		"attempt": RunState.floor_attempt, "mark_ok": RunState.entity_mark_ok.duplicate(), "guest": RunState.guest_number,
		"frames": RunState.freeze_frames_left,
	}
	_save_run = (SaveService.data.get("run", {}) as Dictionary).duplicate(true)
	_attempts_snapshot = (SaveService.page(&"yellow")["attempts"] as Array).duplicate(true)


func after_each() -> void:
	AudioDirector.clear_pa()
	if is_instance_valid(_host):
		_host.queue_free()
	for p in _settings_snapshot:
		Settings.set(p, _settings_snapshot[p])
	if _settings_file_existed:
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_settings_file)
	elif FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	Settings.apply()
	RunState.marks = _run_snapshot["marks"]
	RunState.evidence_found = _run_snapshot["evidence"]
	RunState.clause = _run_snapshot["clause"]
	RunState.clause_void = _run_snapshot["void"]
	RunState.pocket = _run_snapshot["pocket"]
	RunState.battery = _run_snapshot["battery"]
	RunState.nerve = _run_snapshot["nerve"]
	RunState.floor_attempt = _run_snapshot["attempt"]
	RunState.entity_mark_ok = _run_snapshot["mark_ok"]
	RunState.guest_number = _run_snapshot["guest"]
	RunState.freeze_frames_left = _run_snapshot["frames"]
	SaveService.data["run"] = _save_run
	var page_attempts: Array = SaveService.page(&"yellow")["attempts"]
	page_attempts.clear()
	page_attempts.append_array(_attempts_snapshot)


# --- helpers ----------------------------------------------------------------------------------

func _open(id: StringName, args: Dictionary = {}) -> ScreenBase:
	var s := (load(Game.SCREENS[id]) as GDScript).new() as ScreenBase
	assert_not_null(s, "%s is a ScreenBase" % id)
	s.setup(args)
	_host.add_child(s)
	return s


func _capture(s: ScreenBase) -> Dictionary:
	var got := {"n": 0, "result": null}
	s.closed.connect(func(r: Variant) -> void:
		got["n"] = int(got["n"]) + 1
		got["result"] = r)
	return got


func _session(truth: int = RunState.Truth.HOLDS) -> FloorSession:
	var s := FloorSession.new()
	s.def = FloorCatalog.get_def(&"yellow")
	s.truth = truth
	return s


func _buttons(n: Node, out: Array[Button]) -> void:
	for c in n.get_children():
		if c is Button:
			out.append(c)
		_buttons(c, out)


func _button(root: Node, starts_with: String) -> Button:
	var all: Array[Button] = []
	_buttons(root, all)
	for b in all:
		if b.text.begins_with(starts_with) and b.is_visible_in_tree():
			return b
	return null


func _texts(n: Node, out: PackedStringArray) -> void:
	for c in n.get_children():
		if c is Label:
			out.append((c as Label).text)
		elif c is Button:
			out.append((c as Button).text)
		_texts(c, out)


func _all_text(n: Node) -> String:
	var t := PackedStringArray()
	_texts(n, t)
	return "\n".join(t)


func _action(name: StringName) -> InputEventAction:
	var a := InputEventAction.new()
	a.action = name
	a.pressed = true
	return a


func _press(s: ScreenBase, name: StringName) -> void:
	var a := _action(name)
	s._input(a)
	s._unhandled_input(a)


func _has_focus(s: ScreenBase) -> bool:
	var f := s.get_viewport().gui_get_focus_owner()
	return f != null and s.is_ancestor_of(f)


# --- the table and the base ---------------------------------------------------------------------

func test_every_registered_screen_is_a_screen_base() -> void:
	assert_true(Game.SCREENS.size() >= 10, "all ten screens registered")
	for id in Game.SCREENS:
		var path: String = Game.SCREENS[id]
		assert_true(ResourceLoader.exists(path), "%s exists" % path)
		var script := load(path) as GDScript
		assert_not_null(script, "%s loads" % path)
		if script != null:
			var inst: Object = script.new()
			assert_true(inst is ScreenBase, "%s extends ScreenBase" % id)
			if inst is Node:
				(inst as Node).free()


# --- main menu ----------------------------------------------------------------------------------

func test_menu_builds_and_new_run_closes_with_action() -> void:
	SaveService.data["run"] = {}
	var s := _open(&"menu")
	var got := _capture(s)
	await wait_frames(2)
	assert_false(s.pauses_world, "the menu does not pause (nothing to pause)")
	assert_eq(s.dim_world, 1.0, "the 3D world is hidden")
	assert_null(_button(s, "Continue"), "no Continue without a saved run")
	assert_not_null(_button(s, "Settings"), "Settings button")
	assert_not_null(_button(s, "Quit"), "Quit button")
	assert_true(_has_focus(s), "a menu button has focus without the mouse")
	var title := _all_text(s)
	assert_true(title.contains("THE HALCYON") and title.contains("Please review the House Rules."), "title and subtitle")
	_button(s, "New Run").pressed.emit()
	assert_eq(int(got["n"]), 1, "closed once")
	assert_eq((got["result"] as Dictionary).get("action"), &"new", "result is {action: new}")


func test_menu_continue_only_with_a_saved_run() -> void:
	SaveService.data["run"] = {"floor_id": "yellow", "guest_number": 7}
	var s := _open(&"menu")
	var got := _capture(s)
	await wait_frames(2)
	var cont := _button(s, "Continue")
	assert_not_null(cont, "Continue shows with a saved run")
	if cont != null:
		assert_true(_all_text(s).contains("Guest no. 7"), "the saved run is described")
		cont.pressed.emit()
		assert_eq((got["result"] as Dictionary).get("action"), &"continue", "result is {action: continue}")


# --- pause --------------------------------------------------------------------------------------

func test_pause_buttons_resume_and_abandon_confirmation() -> void:
	var sess := _session()
	var s := _open(&"pause", {"session": sess})
	var got := _capture(s)
	await wait_frames(2)
	for label in ["Resume", "Notebook", "Re-read the card", "Settings", "Abandon run"]:
		assert_not_null(_button(s, label), "pause has '%s'" % label)
	assert_true(_has_focus(s), "focus on a pause button")
	_button(s, "Abandon run").pressed.emit()
	assert_not_null(_button(s, "No, keep going"), "abandon asks first")
	assert_null(_button(s, "Resume"), "main rows are hidden while confirming")
	_button(s, "No, keep going").pressed.emit()
	assert_not_null(_button(s, "Resume"), "back to the main rows")
	assert_eq(int(got["n"]), 0, "not closed by cancelling")
	_press(s, &"pause")
	assert_eq(int(got["n"]), 1, "Esc resumes (closes)")
	assert_null(got["result"], "resume closes with no result")
	sess.free()


func test_pause_without_a_session_still_builds() -> void:
	var s := _open(&"pause")
	await wait_frames(2)
	assert_true((_button(s, "Notebook") as Button).disabled, "no session: notebook disabled")
	assert_not_null(_button(s, "Resume"), "resume exists")


# --- settings -----------------------------------------------------------------------------------

func test_settings_sections_and_live_values() -> void:
	Settings.nerve_hits = 3
	Settings.tell_time_mult = 1.0
	var s := _open(&"settings") as SettingsScreen
	var got := _capture(s)
	await wait_frames(2)
	assert_true(_has_focus(s), "focus on a settings control")
	var body := _all_text(s)
	for head in ["Display", "Comfort", "Audio", "Accessibility", "Controls"]:
		assert_true(body.contains(head), "tab '%s'" % head)
	assert_true(body.contains("Render resolution"), "display tab is first")
	# every tab builds rows
	for i in 5:
		s._select_tab(i)
		await wait_frames(1)
		assert_gt(float(s._rows.get_child_count()), 0.0, "tab %d has content" % i)
	# toggle through its button; the value lives in Settings at once
	s._select_tab(1)
	await wait_frames(1)
	var before := Settings.invert_y
	var all: Array[Button] = []
	_buttons(s._rows, all)
	var inverted_row: Button = null
	for b in all:
		var row := b.get_parent().get_parent()
		if row != null and _all_text(row).contains("Invert look"):
			inverted_row = b
	assert_not_null(inverted_row, "invert look toggle")
	if inverted_row != null:
		inverted_row.pressed.emit()
		assert_eq(Settings.invert_y, not before, "toggle changed Settings.invert_y")
	# sliders apply live
	var sliders := s._rows.find_children("*", "HSlider", true, false)
	assert_eq(sliders.size(), 2, "comfort has two sliders (fov, sensitivity)")
	(sliders[0] as HSlider).value = 100.0
	assert_near(Settings.fov, 100.0, 0.01, "fov slider applied live")
	# audio sliders
	s._select_tab(2)
	await wait_frames(1)
	var audio := s._rows.find_children("*", "HSlider", true, false)
	assert_eq(audio.size(), 7, "seven audio sliders")
	(audio[0] as HSlider).value = 0.35
	assert_near(Settings.vol_master, 0.35, 0.001, "master volume applied live")
	# accessibility cyclers
	s._select_tab(3)
	await wait_frames(1)
	var tell: Button = null
	var nerve: Button = null
	var acc: Array[Button] = []
	_buttons(s._rows, acc)
	for b in acc:
		var txt := _all_text(b.get_parent().get_parent())
		if txt.contains("Tell time"):
			tell = b
		if txt.contains("Nerve") and b.text.begins_with("<"):
			nerve = b
	assert_not_null(tell, "tell time cycler")
	assert_not_null(nerve, "nerve cycler")
	if tell != null:
		tell.pressed.emit()
		assert_near(Settings.tell_time_mult, 1.5, 0.001, "tell time 1.0 -> 1.5")
		tell.pressed.emit()
		assert_near(Settings.tell_time_mult, 2.0, 0.001, "tell time -> 2.0")
		tell.pressed.emit()
		assert_near(Settings.tell_time_mult, 1.0, 0.001, "tell time wraps")
	if nerve != null:
		nerve.pressed.emit()
		assert_eq(Settings.nerve_hits, 4, "nerve 3 -> 4")
	# controls tab lists the bindings
	s._select_tab(4)
	await wait_frames(1)
	var ctl := _all_text(s._rows)
	for act in ["Move", "Sprint", "Crouch", "Interact", "Notebook", "Pause", "Stakeout"]:
		assert_true(ctl.contains(act), "controls lists %s" % act)
	assert_true(ctl.contains(UIKit.key_label(&"interact")), "controls shows the interact key")
	# Back saves and closes
	_button(s, "Back").pressed.emit()
	assert_eq(int(got["n"]), 1, "Back closes once")
	assert_null(got["result"], "settings closes with no result")


func test_settings_render_presets_cycle() -> void:
	Settings.render_height = 360
	var s := _open(&"settings") as SettingsScreen
	await wait_frames(2)
	s._select_tab(1)
	s._select_tab(0)
	await wait_frames(1)
	var res: Button = null
	var all: Array[Button] = []
	_buttons(s._rows, all)
	for b in all:
		if b.text.contains("360p"):
			res = b
	assert_not_null(res, "render resolution cycler shows 360p")
	if res != null:
		res.pressed.emit()
		assert_eq(Settings.render_height, 480, "360 -> 480")
		res.pressed.emit()
		res.pressed.emit()
		assert_eq(Settings.render_height, 0, "720 -> native (0)")
		assert_true(res.text.contains("Native"), "native is labelled")


func test_settings_escape_goes_back() -> void:
	var s := _open(&"settings")
	var got := _capture(s)
	await wait_frames(2)
	_press(s, &"ui_cancel")
	assert_eq(int(got["n"]), 1, "Esc closes settings")


# --- notebook -----------------------------------------------------------------------------------

func test_notebook_tabs_marks_and_fairness() -> void:
	var sess := _session(RunState.Truth.HOLDS)
	RunState.marks.clear()
	var s := _open(&"notebook", {"session": sess}) as NotebookScreen
	var got := _capture(s)
	await wait_frames(2)
	assert_true(_has_focus(s), "notebook has focus on a tab")
	var rules := sess.def.rules
	var text := _all_text(s)
	assert_true(text.contains(sess.def.title), "floor title")
	for r in rules:
		assert_true(text.contains(r.text), "rule %d is listed" % r.number)
	# no rule is called the entity rule, none is called true or false
	for banned in ["entity", "ENTITY", "TRUE", "true for", "is a lie"]:
		assert_false(_all_text(s._content).contains(banned), "this-floor tab never says '%s'" % banned)
	# the mark button cycles ? -> Trust -> Lie -> ?
	var rid := rules[0].id
	var mb := s._mark_buttons[rid] as Button
	assert_eq(mb.text, "[ ? ]", "starts unmarked")
	mb.pressed.emit()
	assert_eq(RunState.mark_of(rid), RunState.Mark.TRUST, "first press: Trust")
	assert_eq(mb.text, "[ TRUST ]", "label follows")
	mb.pressed.emit()
	assert_eq(RunState.mark_of(rid), RunState.Mark.LIE, "second press: Lie")
	mb.pressed.emit()
	assert_eq(RunState.mark_of(rid), RunState.Mark.UNKNOWN, "third press: back to ?")
	# marks are identical for every rule kind: same widgets, same labels (nothing distinguishes the entity rule)
	var seen := {}
	for r in rules:
		seen[(s._mark_buttons[r.id] as Button).text] = true
	assert_eq(seen.size(), 1, "all rules look the same before any mark")
	# Tab key closes (the GUI would eat it as focus-next, so the screen listens in _input)
	_press(s, &"notebook")
	assert_eq(int(got["n"]), 1, "notebook key closes it")
	sess.free()


func test_notebook_closes_with_escape_and_interact() -> void:
	for act in [&"pause", &"ui_cancel", &"interact"]:
		var sess := _session()
		var s := _open(&"notebook", {"session": sess})
		var got := _capture(s)
		await wait_frames(1)
		_press(s, act)
		assert_eq(int(got["n"]), 1, "%s closes the notebook" % act)
		assert_null(got["result"], "notebook closes with no result")
		s.queue_free()
		sess.free()


func test_notebook_evidence_only_found_and_true_this_run() -> void:
	var sess := _session(RunState.Truth.INVERTED)
	var def := sess.def
	RunState.evidence_found.clear()
	var s := _open(&"notebook", {"session": sess, "tab": 1}) as NotebookScreen
	await wait_frames(2)
	assert_true(_all_text(s._content).contains("0 pieces found"), "empty state says 0 pieces")
	# found: one INVERTED piece (true this run); also a leftover HOLDS piece from another roll of this floor
	var inverted := def.evidence_for(RunState.Truth.INVERTED)
	var holds := def.evidence_for(RunState.Truth.HOLDS)
	var unfound := inverted[1]
	RunState.evidence_found[inverted[0].id] = true
	RunState.evidence_found[holds[0].id] = true
	s._tab = -1
	s._select_tab(1)
	await wait_frames(1)
	var shown := _all_text(s._content)
	assert_true(shown.contains("1 piece found"), "singular 'piece' and the count: found only what is true")
	assert_true(shown.contains(inverted[0].note), "the found, true piece is listed with its note")
	assert_false(shown.contains(holds[0].note), "evidence of the other variant is never listed")
	assert_false(shown.contains(unfound.note), "evidence that was not found is never listed")
	var listed := s.found_evidence()
	assert_eq(listed.size(), 1, "found_evidence() returns one def")
	for e in listed:
		assert_eq(e.variant, RunState.Truth.INVERTED, "only variant == truth")
	s.queue_free()
	sess.free()


func test_notebook_frames_and_viewer() -> void:
	var sess := _session()
	for k in 2:
		var img := Image.create(TapeBuffer.W, TapeBuffer.H, false, Image.FORMAT_RGB8)
		img.fill(Color(0.2 + 0.2 * k, 0.4, 0.3))
		sess.freeze_frames.append({"image": img, "room": "arrival", "t": 12.0 * (k + 1), "floor": &"yellow", "from_playback": k == 1})
	var s := _open(&"notebook", {"session": sess, "tab": 2}) as NotebookScreen
	var got := _capture(s)
	await wait_frames(2)
	var thumbs := 0
	var all: Array[Button] = []
	_buttons(s._content, all)
	for b in all:
		if b.icon != null:
			thumbs += 1
	assert_eq(thumbs, 2, "two thumbnails")
	assert_true(s.open_first_frame(), "a thumbnail opens the viewer")
	assert_not_null(s._viewer, "viewer is open")
	_press(s, &"ui_cancel")
	assert_null(s._viewer, "Esc closes the viewer first")
	assert_eq(int(got["n"]), 0, "the notebook stays open")
	_press(s, &"ui_cancel")
	assert_eq(int(got["n"]), 1, "second Esc closes the notebook")
	sess.free()


func test_notebook_frames_empty_state() -> void:
	var sess := _session()
	var s := _open(&"notebook", {"session": sess, "tab": 2})
	await wait_frames(2)
	assert_true(_all_text(s).contains("None yet"), "empty frames state")
	assert_false((s as NotebookScreen).open_first_frame(), "nothing to enlarge")
	sess.free()


func test_notebook_past_attempts_summary() -> void:
	var page_attempts: Array = SaveService.page(&"yellow")["attempts"]
	page_attempts.clear()
	page_attempts.append({"result": "blackout", "truth": 1, "t": 125.0, "cause": "hum", "rule": "Lights are provided."})
	page_attempts.append({"result": "blackout", "truth": 0.0, "t": 61.0, "cause": "housekeeping", "rule": "Lights are provided."})
	page_attempts.append({"result": "cleared", "truth": 0, "t": 300.0, "marks_ok": true})
	var sess := _session()
	var s := _open(&"notebook", {"session": sess, "tab": 3})
	await wait_frames(2)
	var t := _all_text(s)
	assert_true(t.contains("3 on record"), "count")
	assert_true(t.contains("That rule lied"), "inverted attempt says the rule lied")
	assert_true(t.contains("That rule held"), "holds attempt (float truth from JSON) says the rule held")
	assert_true(t.contains("2:05") and t.contains("1:01") and t.contains("5:00"), "times formatted m:ss")
	assert_true(t.contains("The Hum") and t.contains("Housekeeping"), "causes named")
	assert_true(t.contains("Cleared") and t.contains("Blackout"), "results named")
	sess.free()


func test_notebook_clause_tab() -> void:
	var sess := _session()
	RunState.clause = &""
	var s := _open(&"notebook", {"session": sess, "tab": 4}) as NotebookScreen
	await wait_frames(2)
	assert_true(_all_text(s._content).contains("not kept"), "no clause yet")
	RunState.clause = &"walk_encouraged"
	RunState.clause_void = false
	s._tab = -1
	s._select_tab(4)
	await wait_frames(1)
	var t := _all_text(s._content)
	var cd := FloorCatalog.clause_def(&"walk_encouraged")
	assert_true(t.contains(cd.printed) and t.contains(cd.house_side) and t.contains(cd.guest_side), "printed text and both sides")
	assert_true(t.contains("IN FORCE") and not t.contains("VOID"), "in force")
	RunState.clause_void = true
	s._tab = -1
	s._select_tab(4)
	await wait_frames(1)
	assert_true(_all_text(s._content).contains("VOID"), "void status shown as text")
	sess.free()


func test_notebook_header_shows_nerve_battery_pocket() -> void:
	var sess := _session()
	RunState.battery = 73.0
	RunState.pocket = &"fuse"
	var s := _open(&"notebook", {"session": sess}) as NotebookScreen
	await wait_frames(2)
	var t := s._stats.text
	assert_true(t.contains("Nerve") and t.contains("73%") and t.contains("Fuse"), "header: %s" % t)
	sess.free()


func test_notebook_without_a_session_does_not_crash() -> void:
	var s := _open(&"notebook")
	await wait_frames(2)
	for i in 5:
		s._tab = -1
		(s as NotebookScreen)._select_tab(i)
	assert_true(true, "built every tab with no session")


# --- endings ------------------------------------------------------------------------------------

func test_ending_screens_reveal_skip_and_results() -> void:
	for ending in [&"checkout", &"desk", &"burn"]:
		var s := _open(&"ending", {"ending": ending, "burn_valid": true}) as EndingScreen
		var got := _capture(s)
		await wait_frames(2)
		assert_false(s.is_done(), "%s: text is still being typed" % ending)
		assert_false(s._tail.visible, "%s: buttons wait for the text" % ending)
		s.skip()
		assert_true(s.is_done(), "%s: skip finishes at once" % ending)
		assert_true(s._tail.visible, "%s: buttons appear" % ending)
		var t := _all_text(s)
		assert_true(t.contains(String(EndingScreen.ENDINGS[ending]["title"])), "%s: title" % ending)
		assert_true(t.contains("Endings seen:"), "%s: endings list" % ending)
		await wait_frames(2)
		assert_true(_has_focus(s), "%s: focus lands on a button" % ending)
		_button(s, "New run").pressed.emit()
		assert_eq((got["result"] as Dictionary).get("action"), &"new", "%s: New run result" % ending)
		var s2 := _open(&"ending", {"ending": ending, "burn_valid": true}) as EndingScreen
		var got2 := _capture(s2)
		s2.skip()
		_button(s2, "Main menu").pressed.emit()
		assert_eq((got2["result"] as Dictionary).get("action"), &"menu", "%s: Main menu result" % ending)


func test_ending_types_out_by_itself() -> void:
	var s := _open(&"ending", {"ending": &"checkout"}) as EndingScreen
	await wait_frames(1)
	var n := 0
	while not s.is_done() and n < 2000:
		s._process(0.5)
		n += 1
	assert_true(s.is_done(), "finishes without input")
	for l in s._labels:
		assert_eq(l.visible_characters, -1, "every paragraph fully shown")


func test_ending_input_skips_then_buttons_work() -> void:
	var s := _open(&"ending", {"ending": &"desk"}) as EndingScreen
	var got := _capture(s)
	await wait_frames(1)
	_press(s, &"interact")
	assert_true(s.is_done(), "interact skips the reveal")
	assert_eq(int(got["n"]), 0, "skipping does not close")
	_press(s, &"ui_cancel")
	assert_eq((got["result"] as Dictionary).get("action"), &"menu", "once shown, Esc returns to the menu")


func test_ending_burn_is_only_valid_when_every_entity_rule_was_marked_right() -> void:
	RunState.entity_mark_ok = {}
	assert_false(EndingScreen.burn_is_valid(), "nothing inspected: not valid")
	var ok := {}
	for fid in FloorCatalog.ORDER:
		if fid != &"lobby":
			ok[fid] = true
	RunState.entity_mark_ok = ok
	assert_true(EndingScreen.burn_is_valid(), "every floor below the Lobby marked right: valid")
	ok[&"blue"] = false
	assert_false(EndingScreen.burn_is_valid(), "one wrong entity mark: not valid")
	ok[&"blue"] = true
	ok.erase(&"natatorium")
	assert_false(EndingScreen.burn_is_valid(), "a floor never inspected: not valid")
	ok[&"natatorium"] = true
	ok[&"lobby"] = false
	assert_true(EndingScreen.burn_is_valid(), "the Lobby is not one of the floors below it: ignored")
	# the screen shows the real burn only when valid
	var bad := _open(&"ending", {"ending": &"burn", "burn_valid": false}) as EndingScreen
	assert_eq(bad._content_key, &"burn_failed", "an invalid burn does not take")
	var good := _open(&"ending", {"ending": &"burn", "burn_valid": true}) as EndingScreen
	assert_eq(good._content_key, &"burn", "a valid burn is the true exit")
	var unknown := _open(&"ending", {"ending": &"nonsense"}) as EndingScreen
	assert_eq(unknown.ending, &"checkout", "an unknown ending falls back to checkout")


# --- intro --------------------------------------------------------------------------------------

func test_intro_runs_four_beats_and_closes_without_result() -> void:
	var s := _open(&"intro") as IntroScreen
	var got := _capture(s)
	await wait_frames(2)
	assert_eq(s._beats.size(), 4, "four beats")
	assert_eq(s._beat, 0, "starts on the first beat")
	assert_true(String(s._beats[3]["body"]) == "Welcome to The Halcyon. Please review the House Rules.", "last beat is the welcome")
	for i in 3:
		s._next_beat()
	assert_eq(s._beat, 3, "on the last beat")
	assert_eq(int(got["n"]), 0, "still open")
	s._next_beat()
	assert_eq(int(got["n"]), 1, "closes after the last beat")
	assert_null(got["result"], "intro closes with no result")


func test_intro_total_length_is_about_twenty_seconds() -> void:
	var s := _open(&"intro") as IntroScreen
	await wait_frames(1)
	var secs := 0.0
	for b in s._beats:
		var last := bool(b.get("last", false))
		var fade_in := IntroScreen.FADE_IN * (1.5 if last else 1.0)
		secs += fade_in + (IntroScreen.LAST_HOLD if last else IntroScreen.HOLD) + IntroScreen.FADE_OUT
	assert_gt(secs, 17.0, "not too short (%.1f s)" % secs)
	assert_lt(secs, 24.0, "not too long (%.1f s)" % secs)


func test_intro_skip_button_and_escape_close() -> void:
	var s := _open(&"intro")
	var got := _capture(s)
	await wait_frames(2)
	assert_true(_has_focus(s), "the Skip button has focus")
	_button(s, "Skip").pressed.emit()
	assert_eq(int(got["n"]), 1, "Skip closes")
	var s2 := _open(&"intro")
	var got2 := _capture(s2)
	await wait_frames(1)
	_press(s2, &"pause")
	assert_eq(int(got2["n"]), 1, "Esc skips")


func test_intro_plays_through_on_its_own() -> void:
	var s := _open(&"intro") as IntroScreen
	var got := _capture(s)
	await wait_frames(1)
	var n := 0
	while int(got["n"]) == 0 and n < 4000:
		s._process(0.25)
		n += 1
	assert_eq(int(got["n"]), 1, "ends by itself")


# --- layout gotcha ------------------------------------------------------------------------------

func test_screens_get_a_real_size() -> void:
	## A Control under a CanvasLayer / plain parent needs PRESET_FULL_RECT or it is 0x0 (see CLAUDE notes).
	for id in [&"menu", &"settings", &"intro", &"ending"]:
		var s := _open(id, {"ending": &"checkout"})
		await wait_frames(2)
		assert_gt(s.size.x, 100.0, "%s has a width" % id)
		assert_gt(s.size.y, 100.0, "%s has a height" % id)
		var panel_ok := false
		for c in s.get_children():
			if c is Control and (c as Control).size.x > 100.0 and (c as Control).size.y > 50.0:
				panel_ok = true
		assert_true(panel_ok, "%s has a sized child panel" % id)
		s.queue_free()
