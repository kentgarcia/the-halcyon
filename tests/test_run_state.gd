extends TestCase
## Run state persistence and determinism: the elevator checkpoint must restore the run exactly, and a
## floor's seed must depend only on (run_seed, floor, attempt) so a failing seed is a reproducible bug report.


func test_run_state_json_roundtrip() -> void:
	RunState.new_run(424242, 7)
	RunState.floor_id = &"yellow"
	RunState.floor_index = 3
	RunState.set_truth(&"boiler", RunState.Truth.INVERTED)
	RunState.set_truth(&"yellow", RunState.Truth.HOLDS)
	RunState.nerve = 2
	RunState.battery = 61.5
	RunState.clause = &"walk_encouraged"
	RunState.courtesies.append(&"spare_battery")
	RunState.cleared_floors.append(&"boiler")
	RunState.entity_mark_ok[&"boiler"] = true
	RunState.evidence_found[&"yel_ev_demo"] = true
	RunState.deaths_this_run = 2
	var d := RunState.to_dict()
	# through JSON, like the file on disk (ints come back as floats)
	var parsed: Variant = JSON.parse_string(JSON.stringify(d))
	assert_true(parsed is Dictionary, "checkpoint serialises to JSON")
	RunState.new_run(1, 1)                       # scramble everything first
	RunState.from_dict(parsed as Dictionary)
	assert_eq(RunState.run_seed, 424242, "run seed")
	assert_eq(RunState.guest_number, 7, "guest number")
	assert_eq(RunState.floor_id, &"yellow", "floor id")
	assert_eq(RunState.floor_index, 3, "floor index")
	assert_eq(RunState.entity_truth(&"boiler"), RunState.Truth.INVERTED, "truth survives")
	assert_eq(RunState.nerve, 2, "nerve")
	assert_near(RunState.battery, 61.5, 0.001, "battery")
	assert_eq(RunState.clause, &"walk_encouraged", "clause")
	assert_eq(RunState.courtesies.size(), 1, "courtesies")
	assert_true(RunState.cleared_floors.has(&"boiler"), "cleared floors")
	assert_true(bool(RunState.entity_mark_ok.get(&"boiler", false)), "entity mark ok keeps its StringName key")
	assert_true(RunState.evidence_found.has(&"yel_ev_demo"), "evidence keeps its StringName key")
	assert_eq(RunState.deaths_this_run, 2, "deaths")


func test_floor_seed_depends_only_on_run_floor_attempt() -> void:
	RunState.new_run(99, 1)
	RunState.begin_floor(&"yellow", 3)
	var a := RunState.floor_seed
	RunState.new_run(99, 5)                      # different guest number, same run seed
	RunState.begin_floor(&"yellow", 3)
	assert_eq(RunState.floor_seed, a, "same run seed + floor + attempt -> same floor seed")
	RunState.reroll_floor_after_blackout()
	assert_ne(RunState.floor_seed, a, "a blackout re-rolls the floor (new layout, new truth)")
	RunState.new_run(100, 1)
	RunState.begin_floor(&"yellow", 3)
	assert_ne(RunState.floor_seed, a, "a different run seed gives a different floor")


func test_named_streams_are_deterministic_and_independent() -> void:
	RunState.new_run(2024, 1)
	RunState.begin_floor(&"yellow", 3)
	var first: Array = []
	for _i in 6:
		first.append(RunState.stream(&"rules").randi())
	RunState.new_run(2024, 1)
	RunState.begin_floor(&"yellow", 3)
	var second: Array = []
	for _i in 6:
		# interleave another stream: it must not perturb "rules"
		RunState.stream(&"director").randf()
		second.append(RunState.stream(&"rules").randi())
	assert_eq(first, second, "a named stream is not affected by draws from other streams")


func test_begin_floor_clears_per_floor_state() -> void:
	RunState.new_run(5, 1)
	RunState.begin_floor(&"boiler", 0)
	RunState.mark_rule(&"some_rule", RunState.Mark.LIE)
	RunState.verdict = 1
	RunState.floor_clock = 400.0
	RunState.housekeeping_warned = true
	RunState.begin_floor(&"natatorium", 1)
	assert_eq(RunState.marks.size(), 0, "marks are per floor")
	assert_eq(RunState.verdict, -1, "verdict is per floor")
	assert_near(RunState.floor_clock, 0.0, 0.0001, "clock resets")
	assert_false(RunState.housekeeping_warned, "warning resets")


func test_tape_pack_roundtrip() -> void:
	var frames: Array[PackedByteArray] = []
	for i in 3:
		var fr := PackedByteArray()
		fr.resize(TapeBuffer.FRAME_BYTES)
		fr.fill(10 + i * 40)
		frames.append(fr)
	var bytes := TapeBuffer.pack(frames, 10.0)
	var back := TapeBuffer.unpack(bytes)
	assert_eq((back["frames"] as Array).size(), 3, "frame count survives pack/unpack")
	assert_near(float(back["fps"]), 10.0, 0.01, "fps survives")
	assert_eq((back["frames"] as Array)[1][0], 50, "pixel data survives")
