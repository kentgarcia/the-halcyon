extends TestCase
## Echo tapes (SPEC 4.3, 4.11): every clip the floor catalogue can place exists, is 8-15 s long, matches the variant
## it is filed under (Fairness Doctrine 1), and playing in a headless build degrades to static without erroring.

const ALL_CLIPS: Array[StringName] = [
	&"hum_hold", &"hum_inv", &"foreman_hold", &"foreman_inv", &"lifeguard_hold", &"lifeguard_inv",
	&"queue_hold", &"queue_inv", &"greeter_hold", &"greeter_inv",
]


func test_has_clip_for_all_ten_and_not_unknown() -> void:
	for c in ALL_CLIPS:
		assert_true(EchoPlayer.has_clip(c), "has_clip(%s)" % c)
	assert_false(EchoPlayer.has_clip(&"nope"), "unknown id")
	assert_false(EchoPlayer.has_clip(&""), "empty id")
	assert_eq(EchoPlayer.clip_ids().size(), ALL_CLIPS.size(), "exactly the ten ids")


func test_every_clip_declares_a_readable_duration() -> void:
	for c in ALL_CLIPS:
		var d := EchoPlayer.clip_duration(c)
		assert_true(d >= 8.0 and d <= 15.0, "%s duration %.1f s must be 8-15 s" % [c, d])
		assert_ne(EchoPlayer.clip_label(c), "", "%s has a viewfinder label" % c)


func test_catalogue_clips_are_all_playable_and_match_their_variant() -> void:
	## Every tape the floor definitions can place names a real clip, and a _hold clip is only filed under the
	## variant where the rule holds (and _inv under inverted): the footage can never contradict the run.
	var seen := 0
	for fid in FloorCatalog.ORDER:
		var def := FloorCatalog.get_def(fid)
		for e in def.evidence:
			if e.kind != EvidenceDef.Kind.TAPE_CLIP:
				continue
			var clip := StringName(e.params.get("clip", ""))
			seen += 1
			assert_true(EchoPlayer.has_clip(clip), "%s: evidence %s names clip '%s'" % [fid, e.id, clip])
			var want := "_hold" if e.variant == RunState.Truth.HOLDS else "_inv"
			assert_true(String(clip).ends_with(want), "%s: clip %s filed under the wrong variant" % [fid, clip])
	assert_gt(float(seen), 9.0, "the catalogue holds the ten Echo tapes")


func test_clip_for_never_shows_the_other_variant() -> void:
	assert_eq(EchoPlayer.clip_for(&"hum_hold", RunState.Truth.HOLDS), &"hum_hold", "matching hold")
	assert_eq(EchoPlayer.clip_for(&"hum_inv", RunState.Truth.INVERTED), &"hum_inv", "matching inverted")
	# a mismatched tape (a placement bug) still shows footage the run's truth allows
	assert_eq(EchoPlayer.clip_for(&"queue_hold", RunState.Truth.INVERTED), &"queue_inv", "mismatch is corrected")
	assert_eq(EchoPlayer.clip_for(&"greeter_inv", RunState.Truth.HOLDS), &"greeter_hold", "mismatch is corrected")


func test_static_frames_are_well_formed() -> void:
	var f := EchoPlayer.static_frames()
	assert_gt(float(f.size()), 3.0, "a few frames of snow")
	for fr in f:
		assert_eq(fr.size(), TapeBuffer.FRAME_BYTES, "frame size")


func test_headless_play_returns_without_error() -> void:
	# no session at all, a bogus session, an unknown clip: all of them are quiet no-ops
	EchoPlayer.play(null, &"hum_hold", RunState.Truth.HOLDS)
	var stub := Node.new()
	EchoPlayer.play(stub, &"hum_hold", RunState.Truth.HOLDS)
	EchoPlayer.play(stub, &"not_a_clip", RunState.Truth.HOLDS)
	EchoPlayer.play_own_death(null, {})
	EchoPlayer.play_own_death(stub, {"tape": "user://does_not_exist.tape", "guest": 3})
	stub.free()
	assert_true(true, "reached the end")


func test_headless_bake_degrades_to_static() -> void:
	var frames: Array[PackedByteArray] = await EchoPlayer.bake_frames(null, &"hum_hold")
	assert_gt(float(frames.size()), 0.0, "static stands in when nothing can render")
	assert_eq(frames[0].size(), TapeBuffer.FRAME_BYTES, "frame size")


func test_tape_damage_keeps_frame_size() -> void:
	var base := EchoPlayer.static_frames()[0]
	assert_eq(EchoPlayer._tear(base, 5).size(), TapeBuffer.FRAME_BYTES, "tear keeps the size")
	var clip: Array[PackedByteArray] = []
	for i in 30:
		clip.append(base)
	var done := EchoPlayer._finish(clip, &"hum_inv")
	assert_eq(done.size(), 32, "two intro frames are added")
	for fr in done:
		assert_eq(fr.size(), TapeBuffer.FRAME_BYTES, "every finished frame is a full frame")
