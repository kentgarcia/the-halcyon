class_name Bots
extends Node
## Scripted players for smoke tests and screenshots. They drive the real PlayerInput in scripted mode,
## so the same code paths run as for a human. Each bot is a coroutine; results print as `BOT: ...`.

var scene: Node
var harness: DevHarness
var player: Player


func start(bot_name: String, p_scene: Node, p_harness: DevHarness) -> void:
	scene = p_scene
	harness = p_harness
	await get_tree().process_frame
	await get_tree().process_frame
	player = scene.get("player") as Player
	if player != null:
		player.input.script_mode(true)
	match bot_name:
		"door":
			await _bot_door()
		"floor_walk":
			await _bot_floor_walk(999)
		"floor_encounter":
			await _bot_floor_walk(1)
			await _bot_encounter()
		"entity_play":
			await _bot_entity_play()
		"campaign":
			await _bot_campaign()
		"housekeeping":
			await _bot_housekeeping()
		"stakeout":
			await _bot_stakeout()
		"continue":
			await _bot_continue()
		"blackout":
			await _bot_blackout()
		"crowd_play":
			await _bot_crowd_play()
		"label_peek":
			await _bot_label_peek()
		_:
			print("BOT: unknown bot %s" % bot_name)
	if harness != null and harness.args.has("bot-quit"):
		await frames(10)
		get_tree().quit()      # headless soaks: stop when the bot is done instead of idling to --quit-frame


func frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func face(target: Vector3) -> void:
	var d := target - player.global_position
	player.rotation.y = atan2(-d.x, -d.z)


func walk_to(target: Vector3, stop_dist: float = 0.5, max_frames: int = 4000) -> bool:
	var last := player.global_position
	var still := 0
	var side := 1.0
	for _i in max_frames:
		var d := target - player.global_position
		d.y = 0.0
		if d.length() < stop_dist:
			player.input.set_move(Vector2.ZERO)
			return true
		face(target)
		# pinned head-on against a prop (a locker on the line to the next tile centre)? sidestep like a person would
		if _i % 12 == 11:
			var moved := Vector2(player.global_position.x - last.x, player.global_position.z - last.z).length()
			still = still + 1 if moved < 0.06 else 0
			last = player.global_position
			if still >= 2:
				side = -side
				for _k in 22:
					player.input.set_move(Vector2(side, 0.35))
					await get_tree().process_frame
				still = 0
				continue
		player.input.set_move(Vector2(0.0, 1.0))
		await get_tree().process_frame
	player.input.set_move(Vector2.ZERO)
	return false


func _bot_door() -> void:
	## Walk the hall to its east door, open it, step through, check a new chunk streamed in.
	var streamer: ChunkStreamer = scene.get("streamer")
	var start_live := streamer.live_count()
	var exit_tile := Vector2i(20, 1)
	var door_pos := Vector3((exit_tile.x + 0.5) * GameScale.TILE, 0.0, (exit_tile.y) * GameScale.TILE)
	var ok := true
	for wp in [Vector2i(1, 5), Vector2i(1, 2), exit_tile + Vector2i(0, 1)]:
		ok = ok and await walk_to(GameScale.tile_to_world(wp), 0.3)
	print("BOT: reached door approach: %s at %s" % [ok, player.global_position])
	face(door_pos + Vector3(0, 1.2, 0))
	player.pitch = 0.0
	await frames(10)
	print("BOT: focus=%s prompt='%s'" % [player.focus, player.focus.current_prompt(player) if player.focus else ""])
	player.input.tap(&"interact")
	await frames(60)
	print("BOT: live chunks %d -> %d, build_ms=%.2f" % [start_live, streamer.live_count(), streamer.build_ms_last])
	var ok2 := await walk_to(door_pos + Vector3(0, 0, -2.5), 0.4)
	print("BOT: walked through: %s now at %s current=%s" % [ok2, player.global_position, streamer.current.spec.id if streamer.current else "none"])
	await frames(90)
	print("BOT: after 90 frames live=%d (door closes behind)" % streamer.live_count())


# --- full-floor bots (drive a live FloorSession) ---------------------------------------------

func _exit_entry(chunk: Chunk, index: int) -> Dictionary:
	for e in chunk.exit_world:
		if int(e["index"]) == index:
			return e
	return {}


func _tile_free(t: Vector2i) -> bool:
	## The grid only knows walls; the bot also avoids tiles with solid props (desks, cabinets...).
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.34
	q.shape = sh
	q.transform = Transform3D(Basis(), GameScale.tile_to_world(t, 0.7))
	q.collision_mask = GameScale.LAYER_WORLD | GameScale.LAYER_PROPS
	return player.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _bot_floor_walk(stop_at_beat: int) -> void:
	## Walk the main line of the floor: path to the forward door, open it, step through, repeat.
	var s: FloorSession = scene
	var t0 := Time.get_ticks_msec()
	var guard := 0
	while s.player.frozen and guard < 900:
		await frames(1)
		guard += 1
	var rooms := 0
	while not s.cleared and not s.blackout_done and rooms < 40:
		var cur: Chunk = s.streamer.current
		if cur == null:
			await frames(5)
			continue
		var bp := s.current_beat()
		if bp == null or not bp.main:
			print("BOT: left the main line (%s)" % (cur.spec.id))
			return
		if bp.index >= stop_at_beat:
			print("BOT: reached beat %d (%s) after %.1fs" % [bp.index, cur.spec.id, (Time.get_ticks_msec() - t0) / 1000.0])
			return
		if bp.forward_exit < 0 and bp.kind != &"departure":
			print("BOT: floor_walk reached the final beat %s: cleared=%s nerve=%d build_ms_max=%.1f history=%s" % [cur.spec.id, s.cleared, RunState.nerve, s.streamer.build_ms_max, s.director.history])
			return
		if bp.kind == &"departure" or bp.forward_exit < 0:
			await frames(20)
			continue
		var ex := _exit_entry(cur, bp.forward_exit)
		if ex.is_empty():
			print("BOT: no exit entry %d in %s" % [bp.forward_exit, cur.spec.id])
			return
		var door_tile: Vector2i = ex["tile"]
		var dir: Vector2i = ex["dir"]
		var path := s.grid.path(GameScale.world_to_tile(player.global_position), door_tile, {"allow": _tile_free})
		if path.is_empty():
			path = s.grid.path(GameScale.world_to_tile(player.global_position), door_tile)
		if path.is_empty():
			print("BOT: no path in %s to the forward door" % cur.spec.id)
			return
		var stuck_run := 0
		for t in path:
			if not await walk_to(GameScale.tile_to_world(t), 0.32, 400):
				# a prop sits on this tile (A* only knows walls): skip it and aim for the next one
				stuck_run += 1
				if stuck_run >= 3:
					print("BOT: stuck at %s heading for %s in %s" % [player.global_position, t, cur.spec.id])
					print("BOT:   frozen=%s hidden=%s encounter=%s entity=%s nerve=%d" % [player.frozen, player.hidden, s.encounter_active(), (s.entity.get("mode") if s.entity != null else "none"), RunState.nerve])
					_print_blockers(GameScale.tile_to_world(t))
					return
			else:
				stuck_run = 0
		var door_world := GameScale.tile_to_world(door_tile, 1.2) + Vector3(dir.x, 0, dir.y) * (GameScale.TILE * 0.5)
		var beyond := door_tile + dir
		var opened := false
		var door := s.grid.door_on_edge(door_tile, beyond)
		for _a in 8:
			if door != null and not door.is_closed() and s.streamer.occupied.has(beyond):
				opened = true
				break
			face(door_world)
			player.pitch = 0.0
			player.head.rotation.x = 0.0
			await frames(6)
			player.input.tap(&"interact")
			await frames(40)
		if not opened and door != null and not door.is_closed() and s.streamer.occupied.has(beyond):
			opened = true
		if not opened:
			print("BOT: door did not open in %s (focus=%s)" % [cur.spec.id, player.focus])
			return
		await frames(30)
		if not await walk_to(GameScale.tile_to_world(beyond), 0.4, 600):
			print("BOT: could not step through the door of %s" % cur.spec.id)
			return
		rooms += 1
		await frames(10)
	print("BOT: slowest chunk build: %s" % s.streamer.build_split)
	print("BOT: floor_walk done: cleared=%s blackout=%s rooms=%d t=%.1fs build_ms_max=%.1f nerve=%d history=%s" % [s.cleared, s.blackout_done, rooms, (Time.get_ticks_msec() - t0) / 1000.0, s.streamer.build_ms_max, RunState.nerve, s.director.history])


func _bot_encounter() -> void:
	var s: FloorSession = scene
	s.director.enabled = true
	var ok: bool = s.director.force_encounter(&"minor")
	print("BOT: force_encounter=%s entity=%s" % [ok, s.entity])
	for i in 18:
		await frames(60)
		var e := s.entity
		var info := ""
		if e != null and e.get("mode") != null:
			info = "mode=%s tile=%s" % [e.get("mode"), e.get("tile")]
		print("BOT: t+%ds phase=%d nerve=%d %s" % [i + 1, s.director.phase, RunState.nerve, info])
	print("BOT: history=%s" % [s.director.history])


# --- entity play bots (Foreman / Lifeguard; --bot=entity_play) --------------------------------
## --beat=N          main-line beat to stand in (default 1: the first choice room); moves on when a room cannot host him
## --kind=minor|major
## --react=stand|leave|hide|move   what the guest does once the encounter begins:
##     stand  do nothing (Lifeguard HOLDS: obey the freeze; INVERTED: the wrong play)
##     leave  run to the nearest exit and go through it (Foreman HOLDS: the right play; INVERTED: into the ambush)
##     hide   walk to the spot farthest from every exit and stay (Foreman INVERTED: the right play)
##     move   keep running between two far tiles (Lifeguard INVERTED: the right play; HOLDS: breaking the freeze)
## --bot-seconds=S   give up after S seconds of director time (default 70)
## --bot-shots=<prefix>  save <prefix>_tell.png and <prefix>_enc<T>.png at --enc-shots=2.5,7 s (looking at --look-tell / --look-enc =
##                   entity|exit|bell|seat|water) and quit when done (--bot-quit)

var _play_done := false


func _mode_name(ent: EntityBase) -> String:
	var m: Variant = ent.get("mode")
	if m == null:
		return "-"
	if ent is Foreman:
		return String(Foreman.Mode.keys()[int(m)])
	if ent is Lifeguard:
		return String(Lifeguard.Mode.keys()[int(m)])
	return str(m)


func _look_point(what: String, ent: EntityBase, cur: Chunk) -> Vector3:
	match what:
		"bell":
			var bell := AlarmSite.ensure_bell(cur, scene)
			if bell != null:
				return bell.global_position
		"sign":
			var ds: Variant = ent.get("exit_door")
			if ds != null and is_instance_valid(ds) and (ds as Door).has_meta(&"exit_sign"):
				return ((ds as Door).get_meta(&"exit_sign") as Node3D).global_position
			var exs := _nearest_exit(cur)
			if not exs.is_empty():
				return AlarmSite.exit_center(exs, 2.2)
		"exit":
			var d: Variant = ent.get("exit_door")
			if d != null and is_instance_valid(d):
				return (d as Door).global_position + Vector3(0, 1.4, 0)
			var ex := _nearest_exit(cur)
			if not ex.is_empty():
				return AlarmSite.exit_center(ex, 1.4)
		"seat":
			var sp: Variant = ent.get("seat_pos")
			if sp != null:
				return (sp as Vector3) + Vector3(0, 1.5, 0)
		"water":
			var fwd := -player.global_transform.basis.z
			return player.global_position + Vector3(fwd.x, 0.0, fwd.z).normalized() * 3.0
	if ent is Lifeguard and not (ent as Lifeguard).on_foot:
		return (ent as Lifeguard).seat_pos + Vector3(0, 1.5, 0)
	return ent.global_position + Vector3(0, 1.3, 0)


func _look_shot(tag: String, what: String, ent: EntityBase, cur: Chunk) -> void:
	var prefix := String(harness.args.get("bot-shots", ""))
	if prefix == "":
		return
	var lamp := harness.args.has("lamp")        # --lamp: raise the camcorder (lamp on) for the capture
	if lamp:
		_camcorder(true)
		await frames(30)
	var target := _look_point(what, ent, cur)
	if harness.args.has("near") and what != "water":
		# --near=M: teleport to a clear spot about M metres from what we are looking at
		var spot := _view_spot(cur, target, float(harness.args["near"]))
		if spot != Vector3.INF:
			player.global_position = spot
			player.velocity = Vector3.ZERO
			await frames(3)
	face(target)
	var eye := player.global_position + Vector3(0, 1.6, 0)
	var d := target - eye
	var flat := Vector2(d.x, d.z).length()
	player.pitch = clampf(atan2(d.y, maxf(flat, 0.01)), -1.2, 1.2)
	player.head.rotation.x = player.pitch
	await frames(3)         # the camera only picks up its new transform on the next frames
	var fwd := -player.camera.global_transform.basis.z
	print("BOT: look %s at %s from %s: aim error %.1f deg, %.1f m, screen %s fov %.0f" % [what, target, player.global_position, rad_to_deg(fwd.angle_to((target - player.camera.global_position).normalized())), (target - eye).length(), player.camera.unproject_position(target), player.camera.fov])
	if ent is Lifeguard:
		var lg := ent as Lifeguard
		print("BOT: chair sil visible=%s in_tree=%s presence=%.2f pos=%s scale=%s occupied=%s mode=%s" % [lg.sil.visible, lg.sil.mesh.is_visible_in_tree(), lg.sil.mat.get_shader_parameter("presence"), lg.sil.global_position, lg.sil.global_transform.basis.get_scale(), lg.sil.mat.get_shader_parameter("occupied"), _mode_name(lg)])
	harness.call("_capture", "%s_%s.png" % [prefix, tag])
	if lamp:
		_camcorder(false)


func _camcorder(raise: bool) -> void:
	if Settings.camcorder_toggle:
		player.input.tap(&"camcorder")
	else:
		player.input.hold(&"camcorder", raise)


func _nearest_exit(cur: Chunk) -> Dictionary:
	var s: FloorSession = scene
	var from := GameScale.world_to_tile(player.global_position)
	var best := {}
	var best_len := 999999
	for ex: Dictionary in cur.exit_world:
		var p := s.grid.path(from, ex["tile"], {"allow": _tile_free})
		if p.is_empty():
			p = s.grid.path(from, ex["tile"])
		if not p.is_empty() and p.size() < best_len:
			best_len = p.size()
			best = ex
	return best


func _walk_tiles(path: Array[Vector2i]) -> bool:
	var stuck := 0
	for t in path:
		if _play_done:
			return false
		if not await walk_to(GameScale.tile_to_world(t), 0.32, 400):
			stuck += 1
			if stuck >= 3:
				return false
		else:
			stuck = 0
	return true


func _leave_through(ex: Dictionary, stay: bool = false) -> bool:
	var s: FloorSession = scene
	var door_tile: Vector2i = ex["tile"]
	var dir: Vector2i = ex["dir"]
	var from := GameScale.world_to_tile(player.global_position)
	var path := s.grid.path(from, door_tile, {"allow": _tile_free})
	if path.is_empty():
		path = s.grid.path(from, door_tile)
	if path.is_empty():
		return false
	player.input.hold(&"sprint", true)
	var reached := await _walk_tiles(path)
	player.input.hold(&"sprint", false)
	if not reached:
		print("BOT: leave: could not walk to the door tile %s (at %s)" % [door_tile, player.global_position])
		return false
	var beyond := door_tile + dir
	var door := s.grid.door_on_edge(door_tile, beyond)
	var door_world := GameScale.tile_to_world(door_tile, 1.2) + Vector3(dir.x, 0, dir.y) * (GameScale.TILE * 0.5)
	for _a in 14:
		if _play_done:
			break
		if door != null and not door.is_closed():
			if s.streamer.occupied.has(beyond):
				break
			await frames(20)                # open, the room beyond is still being built
			continue
		face(door_world)
		var flat := Vector2(door_world.x - player.global_position.x, door_world.z - player.global_position.z).length()
		player.pitch = atan2(door_world.y - 1.6, maxf(flat, 0.1))     # aim at the leaf: close to a door it sits below the horizon
		player.head.rotation.x = player.pitch
		await frames(6)
		player.input.tap(&"interact")
		await frames(30)
	print("BOT: leave: door %s closed=%s occupied(beyond)=%s focus=%s" % [door.door_type if door != null else "-", door.is_closed() if door != null else "-", s.streamer.occupied.has(beyond), player.focus])
	if stay:
		return true                         # opened it (the alarm rings) but stays in the room
	return await walk_to(GameScale.tile_to_world(beyond), 0.4, 600)


func _far_from_exits(cur: Chunk) -> Vector2i:
	var s: FloorSession = scene
	var field: Dictionary = s.grid.distance_field(GameScale.world_to_tile(player.global_position), 30)
	var best := GameScale.world_to_tile(player.global_position)
	var best_score := -1
	for t: Vector2i in field:
		if not cur.world_open.has(t) or not _tile_free(t):
			continue
		var gap := 999
		for ex: Dictionary in cur.exit_world:
			gap = mini(gap, absi(ex["tile"].x - t.x) + absi(ex["tile"].y - t.y))
		if gap > best_score:
			best_score = gap
			best = t
	return best


func _pace(cur: Chunk) -> void:
	## Keep moving between two far apart free tiles of the room until the encounter is over.
	var s: FloorSession = scene
	var here := GameScale.world_to_tile(player.global_position)
	var field: Dictionary = s.grid.distance_field(here, 14)
	var far := here
	var far_d := -1
	for t: Vector2i in field:
		if cur.world_open.has(t) and _tile_free(t) and int(field[t]) > far_d:
			far_d = int(field[t])
			far = t
	player.input.hold(&"sprint", true)
	var goals: Array[Vector2i] = [far, here]
	var i := 0
	while not _play_done and i < 12:
		var from := GameScale.world_to_tile(player.global_position)
		var path := s.grid.path(from, goals[i % 2], {"allow": _tile_free})
		if path.is_empty():
			path = s.grid.path(from, goals[i % 2])
		await _walk_tiles(path)
		i += 1
	player.input.hold(&"sprint", false)


func _react(react: String, cur: Chunk) -> void:
	var s: FloorSession = scene
	match react:
		"leave":
			var ex := _nearest_exit(cur)
			print("BOT: react leave via exit %s" % [ex.get("index", -1)])
			if not ex.is_empty():
				var ok := await _leave_through(ex)
				print("BOT: react leave done ok=%s now in %s" % [ok, s.streamer.current.spec.id if s.streamer.current else "none"])
		"hide":
			var t := _far_from_exits(cur)
			print("BOT: react hide at tile %s" % t)
			var path := s.grid.path(GameScale.world_to_tile(player.global_position), t, {"allow": _tile_free})
			await _walk_tiles(path)
		"move":
			print("BOT: react move (pace)")
			await _pace(cur)
		_:
			print("BOT: react stand")


func _stage_at_bell(cur: Chunk, steps: int) -> void:
	## --stage=bell:N  stand N walking steps from the room's alarm bell (a place to watch the Foreman work).
	var s: FloorSession = scene
	var bell := AlarmSite.ensure_bell(cur, s)
	if bell == null:
		return
	var field: Dictionary = s.grid.distance_field(bell.world_tile, steps + 2)
	var best := GameScale.world_to_tile(player.global_position)
	var best_gap := 999
	for t: Vector2i in field:
		if cur.world_open.has(t) and _tile_free(t) and absi(int(field[t]) - steps) < best_gap:
			best_gap = absi(int(field[t]) - steps)
			best = t
	var path := s.grid.path(GameScale.world_to_tile(player.global_position), best, {"allow": _tile_free})
	await _walk_tiles(path)
	face(bell.global_position)
	print("BOT: staged %d steps from the bell at %s" % [int(field.get(best, -1)), best])


func _stage_at_exit(cur: Chunk, steps: int) -> void:
	## --stage=exit:N  stand N walking steps from the exit nearest to where the guest is, facing it.
	var s: FloorSession = scene
	var ex := _nearest_exit(cur)
	if ex.is_empty():
		return
	var field: Dictionary = s.grid.distance_field(ex["tile"], steps + 2)
	var best := GameScale.world_to_tile(player.global_position)
	var best_gap := 999
	for t: Vector2i in field:
		if cur.world_open.has(t) and _tile_free(t) and absi(int(field[t]) - steps) < best_gap:
			best_gap = absi(int(field[t]) - steps)
			best = t
	# prefer a spot straight back from the door (a clear square-on view of its face)
	var dir: Vector2i = ex["dir"]
	for k in range(steps, 0, -1):
		var ok := true
		for j in range(0, k + 1):
			if not cur.world_open.has(ex["tile"] - dir * j):
				ok = false
		if ok and _tile_free(ex["tile"] - dir * k):
			best = ex["tile"] - dir * k
			break
	var path := s.grid.path(GameScale.world_to_tile(player.global_position), best, {"allow": _tile_free})
	await _walk_tiles(path)
	face(AlarmSite.exit_center(ex, 1.4))
	print("BOT: staged %d steps from exit %s at %s" % [int(field.get(best, -1)), ex["index"], best])


func _los_clear(from: Vector3, to: Vector3) -> bool:
	var short := to - (to - from).normalized() * 0.12          # stop just short: marks sit on the surface they lie on
	var q := PhysicsRayQueryParameters3D.create(from, short, GameScale.LAYER_WORLD | GameScale.LAYER_DOORS)
	return player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _view_spot(cur: Chunk, target: Vector3, ideal: float) -> Vector3:
	## A free open tile of the room about `ideal` metres from `target` with a clear line to it.
	var best := Vector3.INF
	var best_d := 99.0
	for t: Vector2i in cur.world_open:
		var w := GameScale.tile_to_world(t, 0.0)
		var d := Vector2(w.x - target.x, w.z - target.z).length()
		if d < ideal * 0.5 or d > ideal * 1.6 or not _tile_free(t):
			continue
		if _los_clear(w + Vector3(0, 1.6, 0), target) and absf(d - ideal) < best_d:
			best_d = absf(d - ideal)
			best = w
	return best


func _evidence_tour(cur: Chunk) -> void:
	## --tour=1 [--tour-max=N]: visit the room's EvidenceMarks (teleporting 2-3.5 m in front of each, lamp raised) and
	## capture them as <bot-shots>_ev<N>.png. Prints what each mark is.
	var prefix := String(harness.args.get("bot-shots", ""))
	var max_n := int(harness.args.get("tour-max", 5))
	var marks: Array[EvidenceMark] = []
	for n in get_tree().get_nodes_in_group(&"evidence"):
		var m := n as EvidenceMark
		if m != null and m.def != null and m.is_inside_tree() and m.global_position.distance_to(player.global_position) < 40.0:
			marks.append(m)
	marks.sort_custom(func(a: EvidenceMark, b: EvidenceMark): return a.global_position.distance_to(player.global_position) < b.global_position.distance_to(player.global_position))
	var picked: Array[EvidenceMark] = []
	for m in marks:
		var far := true
		for o in picked:
			if o.def.id == m.def.id and o.global_position.distance_to(m.global_position) < 4.0:
				far = false
		if far:
			picked.append(m)
		if picked.size() >= max_n:
			break
	print("BOT: tour: %d marks in reach (%d picked): %s" % [marks.size(), picked.size(), picked.map(func(m): return String(m.def.id))])
	var idx := 0
	for m in picked:
		var mp := m.global_position
		var best := Vector3.INF
		var best_d := 99.0
		for t: Vector2i in cur.world_open:
			var w := GameScale.tile_to_world(t, 0.0)
			var d := Vector2(w.x - mp.x, w.z - mp.z).length()
			if d < 1.6 or d > 4.2 or not _tile_free(t):
				continue
			if _los_clear(w + Vector3(0, 1.6, 0), mp) and absf(d - 2.6) < best_d:
				best_d = absf(d - 2.6)
				best = w
		if best == Vector3.INF:
			print("BOT: tour: no view of %s at %s" % [m.def.id, mp])
			continue
		player.global_position = best
		player.velocity = Vector3.ZERO
		_camcorder(true)
		await frames(30)
		face(mp)
		var d := mp - (player.global_position + Vector3(0, 1.6, 0))
		player.pitch = clampf(atan2(d.y, maxf(Vector2(d.x, d.z).length(), 0.01)), -1.2, 1.2)
		player.head.rotation.x = player.pitch
		await frames(4)
		print("BOT: tour: %s at %s from %.1f m (%s)" % [m.def.id, mp, d.length(), m.get_parent().name])
		if prefix != "":
			harness.call("_capture", "%s_ev%d.png" % [prefix, idx])
		idx += 1
		_camcorder(false)
		await frames(10)


func _bot_trip_alarm() -> void:
	## --trip=1: open a fire door of the room (the guest trips the alarm) and report what the House does about it.
	var s: FloorSession = scene
	var cur: Chunk = s.streamer.current
	var types: Array = []
	var fire_ex := {}
	for ex: Dictionary in cur.exit_world:
		var d := AlarmSite.exit_door(s, ex)
		types.append(String(d.door_type) if d != null else "-")
		if d != null and d.door_type == &"fire" and fire_ex.is_empty():
			fire_ex = ex
	print("BOT: trip: exits of %s are %s" % [cur.spec.id, types])
	if fire_ex.is_empty():
		print("BOT: trip: no fire door in this room")
		return
	s.director.enabled = true
	await frames(int(float(harness.args.get("trip-wait", 0.0)) * 60.0))
	var ok := await _leave_through(fire_ex, harness.args.has("trip-stay"))
	print("BOT: trip: left through the fire door ok=%s director phase=%d history=%s" % [ok, s.director.phase, s.director.history])
	var fm: Variant = s.entity
	print("BOT: trip: alarm_until=%s now=%s can_encounter(minor)=%s relief=%s enabled=%s last_end=%s cur=%s" % [fm.get("_alarm_until"), Time.get_ticks_msec() / 1000.0, s.director._can_encounter(&"minor"), s.in_relief_zone(), s.director.enabled, s.director.last_encounter_end, s.streamer.current.spec.id if s.streamer.current else "-"])
	var watch := int(harness.args.get("trip-watch", 12))
	for i in watch:
		await frames(30)
		var e := s.entity
		print("BOT: trip: t+%.1fs phase=%d ent=%s active=%s room=%s nerve=%d" % [float(i + 1) * 0.5, s.director.phase, _mode_name(e), e.active, s.streamer.current.spec.id if s.streamer.current else "-", RunState.nerve])
	print("BOT: trip: history=%s" % [s.director.history])


func _bot_end(tag: String) -> void:
	print("BOT: end (%s)" % tag)
	if harness != null and harness.args.has("bot-quit"):
		get_tree().quit(0)


func _bot_entity_play() -> void:
	var s: FloorSession = scene
	var beat := int(harness.args.get("beat", 1))
	var react := String(harness.args.get("react", "stand"))
	var kind := StringName(harness.args.get("kind", "minor"))
	var max_t := float(harness.args.get("bot-seconds", 70.0))
	var look_tell := String(harness.args.get("look-tell", "entity"))
	var look_enc := String(harness.args.get("look-enc", "entity"))
	var forced := false
	var cur: Chunk = null
	for _attempt in 6:
		await _bot_floor_walk(beat)
		var bp := s.current_beat()
		cur = s.streamer.current
		if bp == null or not bp.main or bp.index < beat or cur == null:
			print("BOT: play: could not reach beat %d on the main line" % beat)
			_bot_end("unreachable")
			return
		if harness.args.has("trip"):
			await _bot_trip_alarm()
			_bot_end("trip only")
			return
		if harness.args.has("tour"):
			var bpe: String = ""
			for b: FloorPlan.BeatPlan in s.plan.main_beats:
				bpe += "%d:%s%s " % [b.index, b.spec.id if b.spec != null else "-", b.evidence.map(func(e): return String(e.id))]
			print("BOT: plan evidence: %s" % bpe)
			await _evidence_tour(cur)
			_bot_end("tour only")
			return
		var stage := String(harness.args.get("stage", ""))
		if stage.begins_with("bell:"):
			await _stage_at_bell(cur, int(stage.substr(5)))
		elif stage.begins_with("exit:"):
			await _stage_at_exit(cur, int(stage.substr(5)))
		s.director.enabled = true
		forced = s.director.force_encounter(kind)
		print("BOT: play: beat %d (%s) force_encounter(%s)=%s entity=%s truth=%d react=%s nerve=%d/%d" % [
			bp.index, cur.spec.id, kind, forced, s.entity.entity_id if s.entity != null else &"-", s.truth, react, RunState.nerve, RunState.nerve_max])
		if forced:
			break
		s.director.enabled = false
		beat += 1
	if not forced:
		_bot_end("no room accepted the encounter")
		return
	_play_done = false
	var ent := s.entity
	var t0: float = s.director.t
	var last_phase := -1
	var last_nerve := RunState.nerve
	var min_nerve := RunState.nerve
	var first_hit_nerve := -1
	var told := false
	var met := false
	var ended := false
	var enc_at := -1.0
	var tell_at := -1.0
	var shot_tell := false
	var enc_times: Array = []
	for part in String(harness.args.get("enc-shots", "2.5,7")).split(",", false):
		enc_times.append(float(part))
	var ticks := 0
	while ticks < int(max_t * 4.0):
		await frames(15)
		ticks += 1
		var ph: int = s.director.phase
		var dt: float = s.director.t - t0
		if ph != last_phase:
			print("BOT: t=%.1f phase %d -> %d entity=%s active=%s nerve=%d" % [dt, last_phase, ph, _mode_name(ent), ent.active, RunState.nerve])
			if ph == DirectorCore.Phase.TELLING:
				told = true
				tell_at = dt
			elif ph == DirectorCore.Phase.ENCOUNTER:
				met = true
				enc_at = dt
				print("BOT: tell lasted %.1fs before the encounter" % (dt - tell_at))
				_react(react, cur)
			elif ph == DirectorCore.Phase.COOLDOWN and met and not ended:
				ended = true
				print("BOT: stand_down complete at t=%.1f (encounter lasted %.1fs)" % [dt, dt - enc_at])
				_play_done = true
			last_phase = ph
		if RunState.nerve != last_nerve:
			print("BOT: t=%.1f NERVE %d -> %d (entity=%s dist=%.1f)" % [dt, last_nerve, RunState.nerve, _mode_name(ent), ent.distance_to_player()])
			if RunState.nerve < last_nerve and first_hit_nerve < 0:
				first_hit_nerve = RunState.nerve
			last_nerve = RunState.nerve
			min_nerve = mini(min_nerve, RunState.nerve)
		if ticks % 4 == 0:
			print("BOT: t=%.1f ph=%d ent=%s active=%s nerve=%d dist=%.1f room=%s" % [dt, ph, _mode_name(ent), ent.active, RunState.nerve, ent.distance_to_player(), s.streamer.current.spec.id if s.streamer.current else "-"])
		if told and not shot_tell and ph == DirectorCore.Phase.TELLING and dt - tell_at >= 3.2:
			shot_tell = true
			await _look_shot("tell", look_tell, ent, cur)
		if met and not enc_times.is_empty() and dt - enc_at >= float(enc_times[0]):
			var tag := "enc%s" % String.num(float(enc_times[0]), 1).replace(".", "_")
			enc_times.pop_front()
			await _look_shot(tag, look_enc, ent, cur)
		if ended and dt - enc_at > 0.0 and ticks % 4 == 0 and ph == DirectorCore.Phase.COOLDOWN:
			if not player.frozen:
				break
	_play_done = true
	player.input.set_move(Vector2.ZERO)
	player.input.hold(&"sprint", false)
	print("BOT: RESULT truth=%d entity=%s react=%s tell=%s encounter=%s stand_down=%s min_nerve=%d first_hit_nerve=%d never_zero_on_first_hit=%s history=%s" % [
		s.truth, ent.entity_id, react, told, met, ended, min_nerve, first_hit_nerve, first_hit_nerve != 0, s.director.history])
	_bot_end("done")


# --- crowd bots (Queue / Greeter / Lobby Audit; --bot=crowd_play) ----------------------------------
## Walks the main line to the exam room (the Director plays the genuine tell, then the encounter) and plays it.
## --react   Queue (blue):    ticket (take a number, wait)  |  none (take none)  |  slip (none; walk the line in chime windows)
##                            | leave (take a number, then walk away)
##           Greeter (units): answer  |  ignore  |  hide
##           Lobby (audit):   perfect (the right play for every variant)  |  wrong (the opposite)
## --audit-truths=0,1,0,1,0   variants of boiler,natatorium,blue,yellow,units for the Audit (default: all HOLDS)
## --audit-marks=1            every earlier entity rule was marked correctly (Burn the Card is offered)
## --audit-cleared=boiler,... floors learned, in order (default: all five)
## --ending=checkout|desk|burn  what the Audit bot does at the desk (default: checkout); endings are printed, never saved
## --bot-seconds=S  give up after S s of director time (default 300)   --bot-shots=<prefix>  save <prefix>_<tag>.png

var _c_phase := -1
var _c_told := false
var _c_met := false
var _c_ended := false
var _c_tell_at := -1.0
var _c_enc_at := -1.0
var _c_min_nerve := 99
var _c_first_hit := -1
var _c_ending: StringName = &""


func _shot(tag: String) -> void:
	var prefix := String(harness.args.get("bot-shots", ""))
	if prefix != "":
		await frames(3)
		harness.call("_capture", "%s_%s.png" % [prefix, tag])


func _look(target: Vector3) -> void:
	face(target)
	var d := target - (player.global_position + Vector3(0, 1.6, 0))
	player.pitch = clampf(atan2(d.y, maxf(Vector2(d.x, d.z).length(), 0.01)), -1.2, 1.2)
	player.head.rotation.x = player.pitch


func _until(cond: Callable, seconds: float) -> bool:
	## Waits (in director time, so windowed runs behave like headless ones) until cond() or the timeout.
	var s: FloorSession = scene
	var t0: float = s.director.t
	var guard := 0
	while guard < 60000:
		if cond.call():
			return true
		if s.director.t - t0 > seconds:
			return false
		await frames(4)
		guard += 1
	return false


func _goto(world: Vector3) -> bool:
	var s: FloorSession = scene
	var from := GameScale.world_to_tile(player.global_position)
	var to := GameScale.world_to_tile(world)
	var path := s.grid.path(from, to, {"allow": _tile_free})
	if path.is_empty():
		path = s.grid.path(from, to)
	if path.is_empty():
		return false
	return await _walk_tiles(path)


func _tap_at(target: Vector3) -> void:
	_look(target)
	await frames(10)
	print("BOT: focus=%s prompt='%s'" % [player.focus, player.focus.current_prompt(player) if player.focus else ""])
	player.input.tap(&"interact")
	await frames(8)


func _crowd_monitor(ent: EntityBase) -> void:
	var s: FloorSession = scene
	var last_nerve := RunState.nerve
	_c_min_nerve = RunState.nerve
	var t0: float = s.director.t
	while not _play_done:
		await frames(6)
		var ph: int = s.director.phase
		var dt: float = s.director.t - t0
		if ph != _c_phase:
			print("BOT: t=%.1f phase %d -> %d entity=%s active=%s nerve=%d" % [dt, _c_phase, ph, _mode_name(ent), ent.active, RunState.nerve])
			if ph == DirectorCore.Phase.TELLING:
				_c_told = true
				_c_tell_at = dt
			elif ph == DirectorCore.Phase.ENCOUNTER:
				_c_met = true
				_c_enc_at = dt
				print("BOT: the tell lasted %.1f s before the encounter" % (dt - _c_tell_at))
			elif ph == DirectorCore.Phase.COOLDOWN and _c_met and not _c_ended:
				_c_ended = true
				print("BOT: stand_down complete at t=%.1f (the encounter lasted %.1f s)" % [dt, dt - _c_enc_at])
			_c_phase = ph
		if RunState.nerve != last_nerve:
			print("BOT: t=%.1f NERVE %d -> %d (entity=%s)" % [dt, last_nerve, RunState.nerve, _mode_name(ent)])
			if RunState.nerve < last_nerve and _c_first_hit < 0:
				_c_first_hit = RunState.nerve
			last_nerve = RunState.nerve
			_c_min_nerve = mini(_c_min_nerve, RunState.nerve)


func _apply_audit_args() -> void:
	var a := harness.args
	var order: Array[StringName] = [&"boiler", &"natatorium", &"blue", &"yellow", &"units"]
	if a.has("audit-cleared"):
		RunState.cleared_floors.clear()
		for f in String(a["audit-cleared"]).split(",", false):
			RunState.cleared_floors.append(StringName(f))
	elif String(a.get("floor", "")) == "lobby":
		RunState.cleared_floors.assign(order)
	if a.has("audit-truths"):
		var bits := String(a["audit-truths"]).split(",", false)
		for i in mini(bits.size(), order.size()):
			RunState.set_truth(order[i], int(bits[i]))
	if a.has("audit-marks"):
		for f in order:
			RunState.entity_mark_ok[f] = int(a["audit-marks"]) == 1


func _bot_crowd_play() -> void:
	var s: FloorSession = scene
	var react := String(harness.args.get("react", ""))
	var max_t := float(harness.args.get("bot-seconds", 300.0))
	_play_done = false
	_c_phase = -1
	_c_told = false
	_c_met = false
	_c_ended = false
	_c_first_hit = -1
	_apply_audit_args()
	await _bot_floor_walk(maxi(1, s.plan.exam_index))
	var bp := s.current_beat()
	if bp == null or bp.kind != &"exam":
		print("BOT: crowd: did not reach the exam room (%s)" % [s.streamer.current.spec.id if s.streamer.current else "-"])
		_bot_end("no exam")
		return
	var ent := s.entity
	print("BOT: crowd: in %s with %s truth=%d react=%s nerve=%d/%d" % [s.streamer.current.spec.id, ent.entity_id, s.truth, react, RunState.nerve, RunState.nerve_max])
	s.director.enabled = true
	_crowd_monitor(ent)
	var t_start: float = s.director.t
	if not await _until(func(): return _c_met, 60.0):
		print("BOT: crowd: the exam encounter never began")
		_play_done = true
		_bot_end("no encounter")
		return
	match ent.entity_id:
		&"queue": await _crowd_queue(ent as QueueLine, react, max_t)
		&"greeter": await _crowd_greeter(ent as Greeter, react, max_t)
		&"audit": await _crowd_audit(ent as LobbyAudit, react, max_t)
		_: print("BOT: crowd: no bot for %s" % ent.entity_id)
	await frames(14)                                  # let the monitor see the director's last phase change
	_play_done = true
	player.input.set_move(Vector2.ZERO)
	print("BOT: RESULT floor=%s truth=%d entity=%s react=%s tell=%s encounter=%s stand_down=%s min_nerve=%d first_hit_nerve=%d never_zero_on_first_hit=%s t=%.0fs" % [
		s.def.id, s.truth, ent.entity_id, react, _c_told, _c_met, _c_ended, _c_min_nerve, _c_first_hit, _c_first_hit != 0, s.director.t - t_start])
	_bot_end("done")


func _crowd_queue(q: QueueLine, react: String, max_t: float) -> void:
	var s: FloorSession = scene
	await _until(func(): return q.mode == QueueLine.Mode.LIVE, 40.0)
	var reached := await _goto(q.wait_pos)
	print("BOT: queue: wait_pos=%s reached=%s guest_tile=%s dist_from_wait=%s head_dist=%s head=%s" % [q.wait_pos, reached, GameScale.world_to_tile(player.global_position), q.get("_dist_from_wait").get(GameScale.world_to_tile(player.global_position), "n/a"), q.get("_head_dist"), q.head_pos])
	_look(q.head_pos + Vector3(0, 1.3, 0))
	await _shot("queue_line")
	if q.board != null:
		await _peek(q.home_chunk, q.board.global_position + Vector3(0, 1.0, 0), "queue_board", 2.4, 4.0)
		q.passed_head = false                                 # the peek stood the guest past the head for a moment: undo
		q.set("_finish_t", -1.0)
	match react:
		"ticket", "leave":
			await _tap_at(q.dispenser.global_position + Vector3(0, 1.1, 0))
			print("BOT: queue: ticket=%d board=%d" % [q.ticket, q.board_value])
			if harness.args.has("bot-fast") and react == "ticket":
				q.board_value = q.ticket + 1                 # screenshots: skip the wait, the next chime calls the number
				q.tick_t = 1.0
			if react == "leave":
				var field: Dictionary = s.grid.distance_field(GameScale.world_to_tile(q.wait_pos), 14)
				for t: Vector2i in field:
					if int(field[t]) >= 8 and int(field[t]) <= 10 and q.home_chunk.world_open.has(t) and _tile_free(t):
						await _goto(GameScale.tile_to_world(t))
						break
				_look(q.head_pos + Vector3(0, 1.3, 0))
		"slip":
			await _slip_to_head(q, max_t)
	var t0: float = s.director.t
	var last_report := -99.0
	while q.mode != QueueLine.Mode.DONE and s.director.t - t0 < max_t:
		await frames(15)
		var dt: float = s.director.t - t0
		if harness.args.has("bot-fast") and q.tick_t > 3.0 and q.ticket >= 0 and not q.called:
			q.tick_t = 3.0                               # screenshots: the board counts every 3 s
		if dt - last_report >= 10.0:
			last_report = dt
			print("BOT: queue t=%.0f mode=%d ticket=%d board=%d ticks=%d called=%s lurches=%d alerts=%d susp=%.2f nerve=%d" % [dt, q.mode, q.ticket, q.board_value, q.tick_count, q.called, q.lurches, q.alerts, q.suspicion, RunState.nerve])
		if q.alerts == 1 and last_report >= 0.0 and q.mode == QueueLine.Mode.ALERT and q.alert_t > 1.0 and not _shot_taken.has("alert"):
			_shot_taken["alert"] = true
			await _shot("queue_alert")
		if q.called and not _shot_taken.has("called"):
			_shot_taken["called"] = true
			var win0: Door = q.call("_window_door")
			if win0 != null:
				await _peek(q.home_chunk, win0.global_position + Vector3(0, 1.2, 0), "queue_called", 2.4, 4.5)
			var win: Door = q.call("_window_door")
			await _goto(win.global_position if win != null else GameScale.tile_to_world(q.slots[0]))   # to the window, past the head
		if q.lurches >= 2 and not _shot_taken.has("lurch"):
			_shot_taken["lurch"] = true
			_look(q.figures[0].pos + Vector3(0, 1.3, 0)) if false else _look(q.head_pos + Vector3(0, 1.3, 0))
			await _shot("queue_lurch")
	await _until(func(): return s.director.phase != DirectorCore.Phase.ENCOUNTER, 15.0)
	print("BOT: queue done: mode=%d ticket=%d called=%s lurches=%d alerts=%d passed_head=%s" % [q.mode, q.ticket, q.called, q.lurches, q.alerts, q.passed_head])


var _shot_taken: Dictionary = {}


func _slip_to_head(q: QueueLine, max_t: float) -> void:
	## No number: move along the line only inside the 3 s chime windows (every face is on the board).
	var s: FloorSession = scene
	var win: Door = q.call("_window_door")
	var head_tile: Vector2i = q.slots[0]
	for e in StaffKit.chunk_doors(s, q.home_chunk):
		if e["door"] == win:
			head_tile = e["tile"]                           # the room-side tile of the window door (beyond the head)
	var wide := func(t: Vector2i) -> bool:                    # keep two tiles (2.5 m) off every figure: the far lane
		if not _tile_free(t):
			return false
		for st: Vector2i in q.slots:
			if maxi(absi(st.x - t.x), absi(st.y - t.y)) < 2:
				return false
		return true
	var path := s.grid.path(GameScale.world_to_tile(player.global_position), head_tile, {"allow": wide})
	if path.is_empty():
		path = s.grid.path(GameScale.world_to_tile(player.global_position), head_tile, {"allow": _tile_free})
	print("BOT: queue: slip from %s to %s (door %s) path=%d" % [GameScale.world_to_tile(player.global_position), head_tile, win, path.size()])
	var t0: float = s.director.t
	var i := 0
	while i < path.size() and q.mode != QueueLine.Mode.DONE and s.director.t - t0 < max_t:
		var target := GameScale.tile_to_world(path[i])
		var d := target - player.global_position
		d.y = 0.0
		if d.length() < 0.32:
			i += 1
			continue
		face(target)
		if q.chime_left > 0.3 or q.mode == QueueLine.Mode.ALERT:
			player.input.set_move(Vector2(0.0, 1.0))
		else:
			player.input.set_move(Vector2.ZERO)
		await frames(2)
	player.input.set_move(Vector2.ZERO)
	print("BOT: queue: slipped to tile %d/%d of the path; mode=%d alerts=%d passed_head=%s" % [i, path.size(), q.mode, q.alerts, q.passed_head])


func _crowd_greeter(g: Greeter, react: String, max_t: float) -> void:
	var s: FloorSession = scene
	# back to him until he is beside us: he only moves while unobserved
	var away := player.global_position * 2.0 - g.global_position
	_look(Vector3(away.x, player.global_position.y + 1.6, away.z))
	if not _shot_taken.has("greeter_far"):
		_shot_taken["greeter_far"] = true
		_look(g.global_position + Vector3(0, 1.7, 0))
		await _shot("greeter_far")
		_look(Vector3(away.x, player.global_position.y + 1.6, away.z))
	var met := await _until(func(): return g.mode == Greeter.Mode.GREET, 60.0)
	print("BOT: greeter: greeted=%s dist=%.1f mode=%d" % [met, g.distance_to_player(), g.mode])
	if not met:
		return
	_look(g.global_position + Vector3(0, 1.7, 0))
	await _shot("greeter_greet")
	match react:
		"answer":
			await _tap_at(g.global_position + Vector3(0, 1.4, 0))
			print("BOT: greeter: answered=%s mode=%d" % [g.answered, g.mode])
			await frames(30)
			await _shot("greeter_answered")
		"hide":
			_look(Vector3(away.x, player.global_position.y + 1.6, away.z))
			await frames(30)
			var hides: Array = g.home_chunk.slot_nodes.get(&"hide", [])
			var best: HideSpot = null
			var best_d := INF
			for h: HideSpot in hides:
				var d := h.global_position.distance_to(player.global_position)
				if d < best_d:
					best_d = d
					best = h
			if best != null:
				await _goto(best.exit_position())
				await _tap_at(best.interactable.global_position)
				print("BOT: greeter: hidden=%s" % player.hidden)
		_:
			pass
	var t0: float = s.director.t
	var last_report := -99.0
	while s.director.phase == DirectorCore.Phase.ENCOUNTER and s.director.t - t0 < max_t:
		await frames(15)
		var dt: float = s.director.t - t0
		if dt - last_report >= 5.0:
			last_report = dt
			print("BOT: greeter t=%.0f mode=%d answered=%s ignored=%s repeats=%d insisted=%s knocks=%s nerve=%d dist=%.1f" % [dt, g.mode, g.answered, g.ignored, g.repeats, g.insisted, g.knock_log, RunState.nerve, g.distance_to_player()])
		for m in [Greeter.Mode.GUIDE, Greeter.Mode.ESCORT, Greeter.Mode.LEAVE]:
			if g.mode == m and not _shot_taken.has("g%d" % m):
				_shot_taken["g%d" % m] = true
				await frames(30)
				await _shot("greeter_mode%d" % m)
		if g.mode == Greeter.Mode.KNOCK and g.knock_count >= 1 and not _shot_taken.has("knock"):
			_shot_taken["knock"] = true
			await _shot("greeter_knock")
		if g.mode == Greeter.Mode.STALK and react == "ignore" and not _shot_taken.has("stalk"):
			_shot_taken["stalk"] = true
			_look(g.global_position + Vector3(0, 1.7, 0))
			await _shot("greeter_stalk")
			_look(Vector3(away.x, player.global_position.y + 1.6, away.z))
	await _until(func(): return s.director.phase != DirectorCore.Phase.ENCOUNTER, 15.0)
	print("BOT: greeter done: knocks=%s answered=%s escorted=%s opened_door=%s insisted=%s" % [g.knock_log, g.answered, g.escorted, g.opened_door != null, g.insisted])


func _crowd_audit(a: LobbyAudit, react: String, max_t: float) -> void:
	var s: FloorSession = scene
	var ending := StringName(harness.args.get("ending", "checkout"))
	_c_ending = &""
	a.ending_hook = func(e: StringName) -> void:
		_c_ending = e
		print("BOT: ENDING %s" % e)
	await _until(func(): return a.mode == LobbyAudit.Mode.CHECKS, 40.0)
	print("BOT: audit: order=%s checks=%d desk=%s PA=%s" % [a.order, a.checks.size(), a.desk_pos, a.read_lines])
	var wrong := react == "wrong"
	var t0: float = s.director.t
	if react == "idle":                      # stand still: the clock alone must open the desk (no check ever starts)
		await _until(func(): return a.mode == LobbyAudit.Mode.DESK, 960.0)
		print("BOT: audit: idle guest reached mode=%d after %.0f s of encounter, passes=%d fails=%d waived=%d timed_out=%s nerve=%d" % [a.mode, s.director.t - t0, a.passes, a.fails, a.waived, a.timed_out, RunState.nerve])
	while a.mode == LobbyAudit.Mode.CHECKS and s.director.t - t0 < max_t:
		var c := a.current_check()
		if c == null:
			break
		var idx := a.check_index
		print("BOT: audit: check %d %s (%s) -> station %s" % [idx, c.floor_id, "HOLDS" if c.holds() else "INVERTED", c.station])
		await _goto(c.station)
		if not _shot_taken.has("stage%d" % idx):
			_shot_taken["stage%d" % idx] = true
			await _shot("audit_%d_%s_stage" % [idx, c.floor_id])
		await _until(func(): return c.state != AuditChecks.State.PENDING, 8.0)
		await _check_shots(a, idx, c)
		await _play_check(c, wrong)
		await _until(func(): return a.check_index != idx or a.mode != LobbyAudit.Mode.CHECKS or c.state == AuditChecks.State.PENDING, 40.0)
		print("BOT: audit: check %d %s state=%d reason=%s attempts=%d passes=%d fails=%d waived=%d nerve=%d" % [idx, c.floor_id, c.state, c.reason, c.attempts, a.passes, a.fails, a.waived, RunState.nerve])
		if c.state == AuditChecks.State.PENDING and a.check_index == idx:
			# a retry: step off the pad and back on
			await _goto(c.station + Vector3(3.0, 0.0, 0.0))
	await _until(func(): return a.mode == LobbyAudit.Mode.DESK, 30.0)
	print("BOT: audit: mode=%d passes=%d fails=%d waived=%d desk=%s burn_offered=%s" % [a.mode, a.passes, a.fails, a.waived, a.desk_nodes.keys(), a.desk_nodes.has(&"burn")])
	if a.mode != LobbyAudit.Mode.DESK:
		return
	for id in a.desk_nodes:
		await _peek(a.home_chunk, (a.desk_nodes[id] as Node3D).global_position + Vector3(0, 0.9, 0), "audit_desk_%s" % id, 1.6, 3.2)
	await _goto(a.desk_pos + Vector3(0, 0, 0))
	_look(a.desk_pos + Vector3(0, 1.0, 0))
	await _shot("audit_desk")
	var node: Node3D = a.desk_nodes.get(ending, null)
	if node == null:
		print("BOT: audit: %s is not offered at the desk" % ending)
		return
	await _goto(node.global_position)
	var it: Interactable = null
	for c2 in node.get_children():
		if c2 is Interactable:
			it = c2
	await _tap_at(it.global_position if it != null else node.global_position)
	await _until(func(): return _c_ending != &"", 20.0)
	print("BOT: audit: ending=%s mode=%d hook_called_with=%s" % [a.ending, a.mode, _c_ending])


func _play_check(c: AuditChecks.Check, wrong: bool) -> void:
	## The right play for the variant (or its opposite when `wrong`), through real input where there is any.
	var holds := c.holds() != wrong                 # "act as if HOLDS" = do what the card says
	if c is AuditChecks.RunCheck:
		if holds:
			player.input.hold(&"sprint", true)
			await _goto((c as AuditChecks.RunCheck).exit_pos)
			player.input.hold(&"sprint", false)
		else:
			await _stand(c, 30.0)
	elif c is AuditChecks.FreezeCheck:
		if holds:
			await _stand(c, 8.0)
		else:
			await _pace_near(c, 14.0)
	elif c is AuditChecks.WaitCheck:
		var w := c as AuditChecks.WaitCheck
		if holds:
			await _tap_at(w.dispenser.global_position + Vector3(0, 1.1, -0.2))
			await _stand(c, 40.0)
		else:
			await _stand(c, 30.0)
	elif c is AuditChecks.LightCheck:
		var l := c as AuditChecks.LightCheck
		await _goto(l.lit_pos if holds else l.dark_pos)
		await _stand(c, 20.0)
	elif c is AuditChecks.AnswerCheck:
		var ac := c as AuditChecks.AnswerCheck
		if holds:
			var gp: Vector3 = ac.root.global_position + ac.greeter.position
			await _goto(gp + (ac.station - gp).normalized() * 1.5)          # he is 4-6 m off: walk up to him
			_look(gp + Vector3(0, 1.5, 0))
			await _shot("audit_answer_bellhop")
			await _tap_at(gp + Vector3(0, 1.4, 0))
			await _stand(c, 8.0)
		else:
			await _stand(c, 30.0)


func _stand(c: AuditChecks.Check, seconds: float) -> void:
	player.input.set_move(Vector2.ZERO)
	var s: FloorSession = scene
	var t0: float = s.director.t
	var shot := false
	while c.state == AuditChecks.State.RUNNING and s.director.t - t0 < seconds:
		await frames(8)
		if not shot and c.elapsed > 2.0:
			shot = true
			await _shot("audit_%s_running" % c.floor_id)


func _pace_near(c: AuditChecks.Check, seconds: float) -> void:
	var s: FloorSession = scene
	var t0: float = s.director.t
	var flip := false
	while c.state == AuditChecks.State.RUNNING and s.director.t - t0 < seconds:
		var target := c.station + Vector3(2.2 if flip else -2.2, 0.0, 0.0)
		await walk_to(target, 0.4, 200)
		flip = not flip
	player.input.set_move(Vector2.ZERO)


func _peek(chunk: Chunk, target: Vector3, tag: String, lo: float, hi: float) -> void:
	## Screenshot helper: stand (teleport, so no noise) on an open tile of `chunk` that has a clear line to `target`,
	## lo..hi metres away and nearest to where the guest is; look at it; shoot; teleport back.
	if not harness.args.has("bot-shots"):
		return                                          # a peek moves the guest: only when screenshots are wanted
	var home := player.global_position
	var yaw := player.rotation.y
	var best := Vector3.ZERO
	var best_d := INF
	for t: Vector2i in chunk.world_open:
		var w := GameScale.tile_to_world(t)
		var d := Vector2(w.x - target.x, w.z - target.z).length()
		if d < lo or d > hi:
			continue
		if not StaffKit.los_clear(player, w + Vector3(0, 1.6, 0), target):
			continue
		var from_home := w.distance_to(home)
		if from_home < best_d:
			best_d = from_home
			best = w
	if best == Vector3.ZERO:
		print("BOT: peek %s: no tile with a clear view" % tag)
		return
	player.teleport(best, 0.0)
	_look(target)
	await frames(6)
	await _shot(tag)
	player.teleport(home, yaw)
	await frames(2)


func _find_labels(node: Node, text: String, out: Array) -> void:
	if node is Label3D and (node as Label3D).text.contains(text):
		out.append(node)
	for c in node.get_children():
		_find_labels(c, text, out)


func _bot_label_peek() -> void:
	## --text=<substring> [--side=1|-1]: stand 2.2 m from the first Label3D containing the text, on the side of the
	## prop's -Z (its FRONT, side=-1) or +Z (side=1), look at it and shoot. Checks Label3D facing conventions.
	var s: FloorSession = scene
	var text := String(harness.args.get("text", ""))
	var side := float(harness.args.get("side", -1))
	await frames(20)
	var found: Array = []
	_find_labels(s.stage, text, found)
	print("BOT: label_peek: %d labels contain '%s'" % [found.size(), text])
	var all: Array = []
	_find_labels(s.stage, "", all)
	print("BOT: label_peek: all labels: %s" % [all.map(func(l): return "%s@%s" % [(l as Label3D).text, (l as Label3D).global_position.snapped(Vector3(0.1, 0.1, 0.1))])])
	if found.is_empty():
		_bot_end("none")
		return
	var lab: Label3D = found[0]
	var basis := lab.global_transform.basis
	var out_dir: Vector3 = basis.z * -side * -1.0          # side=-1: the -Z side of the label (its visible face is +Z)
	out_dir = (basis.z * side)
	out_dir.y = 0.0
	out_dir = out_dir.normalized()
	var at := lab.global_position + out_dir * 2.2
	at.y = lab.global_position.y - 1.6 if lab.global_position.y > 1.6 else 0.0
	at.y = maxf(at.y, lab.get_parent_node_3d().global_position.y)
	print("BOT: label at %s '%s' viewer at %s side=%.0f" % [lab.global_position, lab.text, at, side])
	player.teleport(at, 0.0)
	_look(lab.global_position)
	await frames(10)
	await _shot("label_%s" % ("front" if side < 0 else "back"))
	_bot_end("done")


func _check_shots(a: LobbyAudit, idx: int, c: AuditChecks.Check) -> void:
	## Screenshots of what a check staged: every figure, the exit mark, the pad. Taken from 3+ m so a figure that
	## fails you for being near (the Foreman) is not triggered.
	if not harness.args.has("bot-shots"):
		return
	var pts: Array = []
	for f in c.figures:
		if is_instance_valid(f):
			pts.append(["fig%d" % pts.size(), (f as Node3D).global_position + Vector3(0, 1.2, 0)])
	var mark := c.root.get_node_or_null("ExitMark") if c.root != null else null
	if mark != null:
		pts.append(["exit", (mark as Node3D).global_position + Vector3(0, 1.2, 0)])
	pts.append(["pad", c.station + Vector3(0, 0.0, 0)])
	for p in pts:
		await _peek(a.home_chunk, p[1], "audit_%d_%s_%s" % [idx, c.floor_id, p[0]], 3.3, 5.5)


# --- the whole run: every floor through Game's own flow (inspection, elevator checkpoint, blackouts, ending) ----

func _top_screen() -> ScreenBase:
	var list: Array = Game.get("_screens")
	for i in range(list.size() - 1, -1, -1):
		if is_instance_valid(list[i]) and not (list[i] as Node).is_queued_for_deletion():
			return list[i]
	return null


func _dismiss_screens(max_frames: int) -> int:
	## Closes whatever screen the flow put up (Inspection / Autopsy / ...). Returns how many were closed.
	var closed := 0
	var waited := 0
	while waited < max_frames:
		var scr := _top_screen()
		if scr == null:
			if closed > 0 or waited > 300:
				return closed
		else:
			print("BOT: campaign dismisses the %s screen" % scr.name)
			scr.close({})
			closed += 1
			await frames(6)
			continue
		await frames(3)
		waited += 3
	return closed


func _bot_campaign() -> void:
	## --scene=floor --floor=boiler --bot=campaign --bot-quit : walks floor after floor the way a player would,
	## dismissing the Inspection / Autopsy screens. Reports per-floor results and how the run ended.
	var t0 := Time.get_ticks_msec()
	var results: Array[String] = []
	var blackouts := 0
	var guard := 0
	while Game.state != Game.State.ENDING and guard < 40:
		guard += 1
		var s := Game.session as FloorSession
		if s == null:
			await frames(5)
			continue
		scene = s
		player = s.player
		player.input.script_mode(true)
		var fid := s.def.id
		var walked_from := Time.get_ticks_msec()
		await _bot_floor_walk(999)
		if fid == &"lobby" and not s.blackout_done:
			var spent := 0
			while Game.state != Game.State.ENDING and not s.blackout_done and spent < 70000:
				var audit := s.entity as LobbyAudit
				if audit != null and audit.mode == LobbyAudit.Mode.DESK:
					audit.choose(&"checkout")
				await frames(10)
				spent += 10
				if spent % 6000 == 0:
					print("BOT: lobby wait %ds: audit mode=%s director phase=%s history_tail=%s player_frozen=%s" % [spent / 60, str(audit.mode) if audit != null else "no audit", str(s.director.phase), str(s.director.history.slice(-2)), str(player.frozen)])
		if s.blackout_done:
			blackouts += 1
			results.append("%s:blackout" % fid)
			await _dismiss_screens(600)
		elif s.cleared:
			results.append("%s:cleared(%.0fs)" % [fid, (Time.get_ticks_msec() - walked_from) / 1000.0])
			await _dismiss_screens(600)
		elif Game.state == Game.State.ENDING:
			results.append("%s:ending" % fid)
		else:
			print("BOT: campaign stopped on %s: the floor bot gave up" % fid)
			break
		# wait for the flow to put a new session in place (elevator checkpoint) or the ending screen up
		var w := 0
		while Game.session == s and Game.state != Game.State.ENDING and w < 600:
			await frames(2)
			w += 2
	var ending_screen := _top_screen()
	print("BOT: campaign done: state=%d floors=[%s] blackouts=%d ending_screen=%s run_saved=%s t=%.0fs" % [
		Game.state, ", ".join(results), blackouts, ending_screen.name if ending_screen != null else "none",
		str(Game.has_saved_run()), (Time.get_ticks_msec() - t0) / 1000.0])


func _bot_housekeeping() -> void:
	## --scene=floor --floor=yellow --clock-scale=0.03 --no-director --bot=housekeeping --bot-quit
	## Walks to the third room and stands still until Housekeeping arrives and shows the guest out (or gives up).
	var s: FloorSession = scene
	await _bot_floor_walk(2)
	var hk: Housekeeping = s.housekeeping
	var n0 := RunState.nerve
	var seen_cart := false
	var warned_at := -1.0
	var active_at := -1.0
	var t := 0.0
	var tile0 := GameScale.world_to_tile(player.global_position)
	var moved_to := Vector2i.ZERO
	while t < 240.0 and RunState.nerve >= n0:
		await frames(30)
		t += 0.5
		if warned_at < 0.0 and hk.warned:
			warned_at = t
		if active_at < 0.0 and hk.active:
			active_at = t
		if hk.cart != null:
			seen_cart = true
	moved_to = GameScale.world_to_tile(player.global_position)
	print("BOT: housekeeping result warned_at=%.0fs active_at=%.0fs cart_seen=%s nerve %d->%d guest %s -> %s (%.1f tiles) clock=%.0f t=%.0fs" % [
		warned_at, active_at, str(seen_cart), n0, RunState.nerve, tile0, moved_to, Vector2(tile0).distance_to(Vector2(moved_to)), RunState.floor_clock, t])


func _print_blockers(target: Vector3) -> void:
	## Debug: what is physically between the guest and the point it wants to reach (a prop on the way = a content bug).
	var space := player.get_world_3d().direct_space_state
	var from := player.global_position + Vector3(0, 0.6, 0)
	var to := target + Vector3(0, 0.6, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, GameScale.LAYER_WORLD | GameScale.LAYER_PROPS | GameScale.LAYER_DOORS)
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	var motion := target - player.global_position
	motion.y = 0.0
	var kc := player.move_and_collide(motion.normalized() * 0.5, true)
	if kc != null:
		var cn := kc.get_collider() as Node
		print("BOT:   the guest's body is blocked by %s (%s) at %s, layer=%s" % [cn.name if cn != null else "?", cn.get_path() if cn != null else "", kc.get_position(), (cn as CollisionObject3D).collision_layer if cn is CollisionObject3D else -1])
	if hit.is_empty():
		print("BOT:   nothing on the straight line to %s (the A* path bends around something)" % target)
	else:
		var col: Object = hit["collider"]
		print("BOT:   blocked at %s by %s (%s) path=%s" % [hit["position"], col.name, col.get_class(), (col as Node).get_path() if col is Node else ""])


func _bot_stakeout() -> void:
	## --scene=floor --floor=yellow --no-director --no-housekeeping --bot=stakeout --bot-quit
	## Plant the camcorder, check it keeps recording, retrieve it (playback of what it saw); plant again, let
	## Housekeeping's tidy take it to Lost & Found, collect it from the shelf.
	var s: FloorSession = scene
	await _bot_floor_walk(1)
	var cc: Camcorder = s.camcorder
	var ok := true
	var notes: Array[String] = []
	# 1. plant
	player.input.tap(&"camcorder")        # raise it first, as a player would
	await frames(30)
	cc.plant()
	await frames(10)
	var node: PlantedCamcorder = cc.planted
	if node == null:
		notes.append("PLANT FAILED")
		ok = false
	else:
		var c0: int = s.recorder.stake.count
		await frames(240)
		var c1: int = s.recorder.stake.count
		notes.append("stake frames %d->%d" % [c0, c1])
		if c1 <= c0 and DisplayServer.get_name() != "headless":
			ok = false
			notes.append("stakeout is not recording")
		elif DisplayServer.get_name() == "headless":
			notes.append("(headless: no renderer, frame capture not checked)")
		if cc.state != Camcorder.State.ABSENT:
			ok = false
			notes.append("camcorder should be ABSENT while planted, is %d" % cc.state)
		# 2. retrieve
		s.retrieve_camcorder(node)
		await frames(10)
		if cc.planted != null or cc.state == Camcorder.State.ABSENT:
			ok = false
			notes.append("retrieve did not return the camcorder (state %d)" % cc.state)
		else:
			notes.append("retrieved, state=%d (3=ABSENT 2=PLAYBACK)" % cc.state)
		cc.end_playback() if cc.has_method("end_playback") else null
	# 3. plant again, then tidy as Housekeeping would
	await frames(20)
	cc.plant()
	await frames(10)
	var cur: Chunk = s.streamer.current
	if cc.planted == null:
		ok = false
		notes.append("second plant failed")
	else:
		cur.set_meta(&"tidied", false)
		s.housekeeping._tidy(cur)
		await frames(5)
		if cc.state != Camcorder.State.ABSENT or cc.planted != null or s.lost_found.size() != 1:
			ok = false
			notes.append("tidy did not send it to Lost & Found (state %d, shelf %d)" % [cc.state, s.lost_found.size()])
		else:
			notes.append("tidied to Lost & Found (shelf 1)")
		# 4. collect from the shelf
		s._collect_lost_and_found()
		await frames(10)
		if cc.state == Camcorder.State.ABSENT or not s.lost_found.is_empty():
			ok = false
			notes.append("collect failed (state %d, shelf %d)" % [cc.state, s.lost_found.size()])
		else:
			notes.append("collected, state=%d" % cc.state)
	print("BOT: stakeout result ok=%s :: %s" % [str(ok), "; ".join(notes)])


func _bot_continue() -> void:
	## Clear one floor, take the elevator checkpoint, then "quit and come back": Game.continue_run() must restore the run.
	var s: FloorSession = scene
	var first_floor := s.def.id
	await _bot_floor_walk(999)
	await _dismiss_screens(600)
	var w := 0
	while Game.session == s and w < 600:
		await frames(2)
		w += 2
	var next_session := Game.session as FloorSession
	var next_id := next_session.def.id
	var seed_before := RunState.run_seed
	var guest_before := RunState.guest_number
	var saved := Game.has_saved_run()
	var saved_floor := String((SaveService.data.get("run", {}) as Dictionary).get("floor_id", ""))
	RunState.nerve = 1                       # scribble over live state: continue must restore the checkpoint, not keep this
	RunState.cleared_floors.clear()
	Game.continue_run()
	await frames(30)
	var s2 := Game.session as FloorSession
	var ok := saved and s2 != null and s2 != next_session and s2.def.id == next_id \
		and RunState.run_seed == seed_before and RunState.guest_number == guest_before \
		and RunState.cleared_floors.has(first_floor) and RunState.nerve == RunState.nerve_max
	print("BOT: continue result ok=%s saved=%s saved_floor=%s resumed=%s seed_kept=%s cleared=%s nerve=%d/%d" % [
		str(ok), str(saved), saved_floor, s2.def.id if s2 != null else "none", str(RunState.run_seed == seed_before),
		str(RunState.cleared_floors), RunState.nerve, RunState.nerve_max])


func _bot_blackout() -> void:
	## Lose all Nerve in the second room: the Blackout must open the Autopsy, and closing it must re-roll the same
	## floor (new layout / truth, attempt + 1, a death counted, notebook kept).
	var s: FloorSession = scene
	var fid := s.def.id
	await _bot_floor_walk(1)
	var attempt0 := RunState.floor_attempt
	var seed0 := RunState.floor_seed
	var guard := 0
	while not s.blackout_done and guard < 12:
		guard += 1
		player.nerve.lose_segment(&"bot_test")
		await frames(20)
	await frames(60)
	var scr := _top_screen()
	var autopsy_open := scr != null and scr.name.to_lower().contains("autopsy")
	print("BOT: blackout: blackout_done=%s autopsy_open=%s state=%d" % [str(s.blackout_done), str(autopsy_open), Game.state])
	if scr != null:
		await frames(120)        # the Autopsy holds its retry button for a moment
		scr.close({})
	var w := 0
	while Game.session == s and w < 600:
		await frames(2)
		w += 2
	var s2 := Game.session as FloorSession
	var ok := s.blackout_done and autopsy_open and s2 != null and s2 != s and s2.def.id == fid \
		and RunState.floor_attempt == attempt0 + 1 and RunState.floor_seed != seed0 and RunState.deaths_this_run == 1 \
		and RunState.nerve == RunState.nerve_max
	print("BOT: blackout result ok=%s resumed=%s attempt %d->%d seed_changed=%s deaths=%d nerve=%d/%d" % [
		str(ok), s2.def.id if s2 != null else "none", attempt0, RunState.floor_attempt, str(RunState.floor_seed != seed0),
		RunState.deaths_this_run, RunState.nerve, RunState.nerve_max])
