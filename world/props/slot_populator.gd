class_name SlotPopulator
extends RefCounted
## Turns a chunk's slots into props, interactables and evidence (SPEC 8.2). Pure content logic: it asks the
## FloorSession (when there is one) for circuits / verdict UI, but works without one so chunks can be
## previewed in the chunk viewer. All randomness comes from the plan's derived stream, so a given
## floor seed always dresses the same room the same way.

const WALL_INSET := 0.0

## Flavor graffiti: every line is literally true or plainly not a claim (the house never lies in what it shows).
const FLAVOR_GRAFFITI: Array[String] = [
	"I WAS HERE", "HELLO?", "WHAT FLOOR IS THIS", "SOMEONE KEPT COUNTING", "I TOOK THE STAIRS. THERE ARE NO STAIRS",
	"DOORS CLOSE", "2 OF US CAME IN", "NO ONE CHECKS OUT", "MIND THE TAPE",
]


static func populate(chunk: Chunk, bp: Object, session: Node = null, staged: bool = false) -> void:
	## `staged` spreads the work over the next few frames (a big room is ~30 ms of prop building; the door swing
	## hides a few frames, not one long one). The order of rng draws is identical either way.
	var job := PopulateJob.new(chunk, bp, session)
	if not staged or chunk.get_tree() == null:
		job.budget_us = 0
		while not job.done:
			job.step()
		return
	job.step()
	_continue(chunk, job)


static func _continue(chunk: Chunk, job: PopulateJob) -> void:
	if job.done or not is_instance_valid(chunk) or chunk.get_tree() == null:
		return
	chunk.get_tree().process_frame.connect(func() -> void:
		if is_instance_valid(chunk):
			job.step()
			_continue(chunk, job), CONNECT_ONE_SHOT)


class PopulateJob extends RefCounted:
	var chunk: Chunk
	var session: Node
	var beat: FloorPlan.BeatPlan
	var rng: RandomNumberGenerator
	var evidence: Array[EvidenceDef] = []
	var loot: Array[StringName] = []
	var graffiti_slots: Array = []
	var tape_slots: Array = []
	var loot_slots: Array = []
	var phase := 0
	var done := false
	var budget_us := 4000            ## per-frame time slice when staged; 0 = unlimited
	var _slots: Array = []
	var _slot_i := 0
	var _prepared := false

	func _init(p_chunk: Chunk, bp: Object, p_session: Node) -> void:
		chunk = p_chunk
		session = p_session
		beat = bp as FloorPlan.BeatPlan
		var plan: FloorPlan = null
		if session != null and "plan" in session:
			plan = session.plan
		if plan != null:
			rng = plan.rng_for("dress:%s:%d" % [chunk.spec.id, chunk.uid])
		else:
			rng = RandomNumberGenerator.new()
			rng.seed = RngStreams.mix(chunk.spec.id.hash(), chunk.uid)
		if beat != null:
			evidence.assign(beat.evidence)
			loot.assign(beat.loot)

	func step() -> void:
		if done:
			return
		var t0 := Time.get_ticks_usec()
		while not done:
			match phase:
				0:
					if not _phase_props(t0):
						return       # out of time this frame: resume next frame
				1: _phase_marks()
				2: _phase_light_evidence()
				_:
					SlotPopulator._fixtures(chunk, session)
					done = true
			phase += 1
			if budget_us > 0 and Time.get_ticks_usec() - t0 >= budget_us:
				return

	func _phase_props(t0: int) -> bool:
		if not _prepared:
			_prepared = true
			if session != null and "circuits" in session and session.circuits != null:
				session.circuits.apply_to_chunk(chunk)
			# evidence needing a graffiti slot: pick distinct slots in order
			graffiti_slots = RngStreams.shuffled(rng, chunk.spec.slots.filter(func(sl): return sl.kind == &"graffiti"))
			tape_slots = chunk.spec.slots.filter(func(sl): return sl.kind == &"tape")
			loot_slots = RngStreams.shuffled(rng, chunk.spec.slots.filter(func(sl): return sl.kind == &"loot"))
			_slots = chunk.spec.slots
		while _slot_i < _slots.size():
			var sl: ChunkSpec.SlotDef = _slots[_slot_i]
			_slot_i += 1
			match sl.kind:
				&"graffiti", &"tape", &"loot", &"floor_mark", &"ceiling_mark":
					pass     # handled in the next phase so evidence gets first pick of the slots
				&"anchor":
					SlotPopulator._marker(chunk, sl)
				_:
					SlotPopulator._place_prop(chunk, sl, rng, session, beat)
			if budget_us > 0 and Time.get_ticks_usec() - t0 >= budget_us:
				return false
		return true

	func _phase_marks() -> void:
		var g_i := 0
		for e in evidence:
			if e.kind == EvidenceDef.Kind.GRAFFITI and g_i < graffiti_slots.size():
				SlotPopulator._place_graffiti(chunk, graffiti_slots[g_i], e.text, e, session, true)
				g_i += 1
		for k in range(g_i, graffiti_slots.size()):
			if rng.randf() < 0.55:
				SlotPopulator._place_graffiti(chunk, graffiti_slots[k], SlotPopulator.FLAVOR_GRAFFITI[rng.randi() % SlotPopulator.FLAVOR_GRAFFITI.size()], null, session, false)
		var tape_i := 0
		for e in evidence:
			if e.kind == EvidenceDef.Kind.TAPE_CLIP and tape_i < tape_slots.size():
				SlotPopulator._place_tape(chunk, tape_slots[tape_i], e)
				tape_i += 1
		if beat != null and not beat.own_tape.is_empty():
			SlotPopulator._place_own_tape(chunk, tape_slots, tape_i, beat.own_tape)
		var li := 0
		for item in loot:
			if li < loot_slots.size():
				SlotPopulator._place_loot(chunk, loot_slots[li], item, rng)
				li += 1

	func _phase_light_evidence() -> void:
		for e in evidence:
			if e.kind == EvidenceDef.Kind.PROP_STATE:
				SlotPopulator._light_evidence(chunk, e, rng, session)


# --- helpers --------------------------------------------------------------------------------

static func local_center(chunk: Chunk, t: Vector2i) -> Vector3:
	return ChunkBuilder.local_center(t)


static func _open_facing(chunk: Chunk, t: Vector2i) -> Vector2i:
	## Local direction toward the most open neighbour (so furniture faces into the room, away from walls).
	var best := Vector2i(0, 1)
	var best_score := -1
	for d in Dir.ALL:
		if not chunk.spec.can_step(t, d):
			continue
		var score := 1
		if chunk.spec.can_step(t + d, d):
			score += 1
		if chunk.spec.can_step(t + d, Dir.rot(d, 1)) or chunk.spec.can_step(t + d, Dir.rot(d, 3)):
			score += 1
		if score > best_score:
			best_score = score
			best = d
	return best


static func _attach(chunk: Chunk, node: Node3D, pos: Vector3, yaw: float) -> void:
	chunk.props_root.add_child(node)
	node.position = pos
	node.rotation.y = yaw


static func _place_prop(chunk: Chunk, sl: ChunkSpec.SlotDef, rng: RandomNumberGenerator, session: Node, beat: FloorPlan.BeatPlan) -> void:
	var kind := sl.kind
	var wall := sl.wall_dir != Vector2i.ZERO
	var c := local_center(chunk, sl.tile)
	var facing: Vector2i
	var pos: Vector3
	if wall:
		facing = -sl.wall_dir
		pos = c + Dir.to_vec3(sl.wall_dir) * (GameScale.TILE * 0.5)
	else:
		facing = _open_facing(chunk, sl.tile)
		pos = c
	var yaw := Dir.yaw_of(facing)
	if not wall and kind in [&"plant", &"boxes", &"chair"]:
		yaw += rng.randf_range(-0.5, 0.5)
		# push against a wall where there is one (feels placed, not dropped)
		for d in Dir.ALL:
			if not chunk.spec.can_step(sl.tile, d) and not chunk.spec.pillars.has(sl.tile + d):
				pos += Dir.to_vec3(d) * 0.28
				break
	match kind:
		&"hide_desk", &"desk":
			var prop := PropFactory.make(kind, rng)
			_attach(chunk, prop, pos, yaw)
			if kind == &"hide_desk":
				var hs := HideSpot.create(&"desk")
				prop.add_child(hs)
				hs.position = Vector3(0, 0, -0.02)
				hs.interactable.position = Vector3(0, 0.45, -0.42)
				chunk.slot_nodes[&"hide"] = chunk.slot_nodes.get(&"hide", []) + [hs]
		&"hide_closet":
			var prop2 := PropFactory.make(&"closet", rng)
			_attach(chunk, prop2, pos, yaw)
			var hs2 := HideSpot.create(&"closet")
			if chunk.theme != null and chunk.theme.id == &"natatorium":
				hs2.sfx_open = &"locker_open"
				hs2.sfx_close = &"locker_close"
			prop2.add_child(hs2)
			hs2.position = Vector3(0, 0, -0.3)
			hs2.interactable.position = Vector3(0, 1.2, -0.75)
			chunk.slot_nodes[&"hide"] = chunk.slot_nodes.get(&"hide", []) + [hs2]
		&"breaker":
			var br := PropFactory.make(&"breaker", rng)
			_attach(chunk, br, pos, yaw)
			_wire_breaker(chunk, br, session, beat)
		&"switch":
			var sw := PropFactory.make(&"switch", rng)
			_attach(chunk, sw, pos, yaw)
			_wire_switch(chunk, sw, session, beat)
		&"suggestion_box":
			var sb := PropFactory.make(&"suggestion_box", rng)
			_attach(chunk, sb, pos, yaw)
			_wire_suggestion_box(sb, session)
			var lab := PropFactory.make_label("SUGGESTIONS", Color(0.1, 0.08, 0.05), 0.3)
			sb.add_child(lab)
			lab.position = Vector3(0, 1.46, -0.03)
		&"charger":
			var ch := PropFactory.make(&"charger", rng)
			_attach(chunk, ch, pos, yaw)
			_wire_charger(ch)
		&"pa_horn":
			var pa := PropFactory.make(&"pa_horn", rng)
			_attach(chunk, pa, pos, yaw)
			if session != null and session.has_method("register_pa_horn"):
				session.register_pa_horn(pa)
		&"sign":
			if _is_queue_exam(session, beat):
				# the exam's `n` is the NOW SERVING board (the Queue drives it; SPEC 6.4)
				var qb := QueueBoard.create()
				_attach(chunk, qb, pos, yaw)
				chunk.slot_nodes[&"board"] = chunk.slot_nodes.get(&"board", []) + [qb]
				return
			var sg := PropFactory.make(&"sign", rng)
			_attach(chunk, sg, pos, yaw)
			var text := "STAFF ONLY"
			if beat != null and beat.kind == &"rest":
				text = "REST AREA"
			var lab2 := PropFactory.make_label(text, Color(0.12, 0.1, 0.06), 0.36)
			sg.add_child(lab2)
			lab2.position = Vector3(0, 1.5, -0.04)
			_tint(chunk, lab2, Color(0.12, 0.1, 0.06), session)
		&"tray":
			if session != null and "def" in session and session.def != null and session.def.id == &"units":
				# Units floor: every tray sits beside a door in the TRUE state (open on HOLDS, shut on INVERTED)
				TrayRecipe.place_slot(chunk, sl, int(session.truth), rng)
			else:
				var tr := PropFactory.make(kind, rng)
				_attach(chunk, tr, pos, yaw)
		&"number_dispenser":
			var nd := PropFactory.make(kind, rng)
			_attach(chunk, nd, pos, yaw)
			chunk.slot_nodes[&"dispenser"] = chunk.slot_nodes.get(&"dispenser", []) + [nd]
		_:
			var prop3 := PropFactory.make(kind, rng)
			_attach(chunk, prop3, pos, yaw)


static func _is_queue_exam(session: Node, beat: FloorPlan.BeatPlan) -> bool:
	return session != null and "def" in session and session.def != null and session.def.id == &"blue" \
		and beat != null and beat.kind == &"exam"


static func _marker(chunk: Chunk, sl: ChunkSpec.SlotDef) -> void:
	var m := Marker3D.new()
	m.name = "Anchor_%d" % sl.index
	chunk.props_root.add_child(m)
	m.position = local_center(chunk, sl.tile)
	chunk.slot_nodes[&"anchor"] = chunk.slot_nodes.get(&"anchor", []) + [m]


static func _tint(chunk: Chunk, label: Label3D, base: Color, session: Node) -> void:
	var lt := LightTint.new()
	lt.target = label
	lt.base_color = base
	if session != null and "stage" in session and session.stage != null:
		lt.field = session.stage.light_field
	elif chunk.get_parent() != null:
		var st := chunk.get_parent().get_parent()
		if st is Stage:
			lt.field = (st as Stage).light_field
	label.add_child(lt)


static func _place_graffiti(chunk: Chunk, sl: ChunkSpec.SlotDef, text: String, e: EvidenceDef, session: Node, is_evidence: bool) -> void:
	var holder: Node3D
	var col := Color(0.62, 0.1, 0.09) if is_evidence else Color(0.22, 0.2, 0.17)
	if is_evidence:
		var mark := EvidenceMark.create(e)
		holder = mark
	else:
		holder = Node3D.new()
		holder.name = "Graffiti"
	chunk.props_root.add_child(holder)
	var facing := -sl.wall_dir
	holder.position = local_center(chunk, sl.tile) + Dir.to_vec3(sl.wall_dir) * (GameScale.TILE * 0.5 - 0.012) + Vector3(0, 1.25, 0)
	holder.rotation.y = Dir.yaw_of(facing)
	var size := 0.5 if text.length() <= 12 else 0.9
	var lab := PropFactory.make_label(text, col, size)
	if text.length() > 20:
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.width = 520
	holder.add_child(lab)
	holder.rotation.z = (float((sl.index * 37) % 11) - 5.0) * 0.012
	_tint(chunk, lab, col, session)


static func _place_tape(chunk: Chunk, sl: ChunkSpec.SlotDef, e: EvidenceDef) -> void:
	var t := TapePickup.create(StringName(e.params.get("clip", "")), e.id)
	chunk.props_root.add_child(t)
	t.position = local_center(chunk, sl.tile) + Vector3(0, 0.0, 0)
	t.rotation.y = float(sl.index) * 1.3
	t.label_text = e.note


static func _place_own_tape(chunk: Chunk, tape_slots: Array, used: int, entry: Dictionary) -> void:
	## Your own old Autopsy footage (SPEC 4.11) on a second tape slot; when the room has only one, beside the first.
	var guest := int(entry.get("guest", 0))
	var pos: Vector3
	var yaw := 0.7
	if used < tape_slots.size():
		var sl: ChunkSpec.SlotDef = tape_slots[used]
		pos = local_center(chunk, sl.tile)
		yaw = float(sl.index) * 1.3
	elif not tape_slots.is_empty():
		var sl0: ChunkSpec.SlotDef = tape_slots[0]
		pos = local_center(chunk, sl0.tile) + Vector3(0.38, 0.0, 0.3)
		yaw = float(sl0.index) * 1.3 + 2.1
	else:
		return
	var t := TapePickup.create(&"", &"")
	t.name = "Tape_Guest%d" % guest
	t.own_death = entry
	t.label_text = "Guest No. %d" % guest
	t.interactable.prompt_cb = func(_pl): return "Play your tape (Guest No. %d)" % guest
	chunk.props_root.add_child(t)
	t.position = pos
	t.rotation.y = yaw


static func _place_loot(chunk: Chunk, sl: ChunkSpec.SlotDef, item: StringName, rng: RandomNumberGenerator) -> void:
	var p := Pickup.create(item, rng)
	chunk.props_root.add_child(p)
	p.position = local_center(chunk, sl.tile) + Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))


# --- breakers, switches, boxes, chargers ----------------------------------------------------

static func _circuit_key(chunk: Chunk, beat: FloorPlan.BeatPlan, session: Node) -> StringName:
	## A breaker/switch controls its own chunk's S panels, or the exam room's when tagged ctl_exam.
	var beat_i := chunk.beat_index
	if chunk.spec.tags.has(&"ctl_exam") and session != null and "plan" in session and session.plan != null and session.plan.exam_index >= 0:
		beat_i = session.plan.exam_index
	return StringName("%d:S" % beat_i)


static func _wire_breaker(chunk: Chunk, prop: Node3D, session: Node, beat: FloorPlan.BeatPlan) -> void:
	var key := _circuit_key(chunk, beat, session)
	var lever_mb := MeshBuilder.new()
	lever_mb.box(&"#a32a2a", Vector3(0, 0.0, 0), Vector3(0.05, 0.3, 0.05))
	var lever := MeshInstance3D.new()
	lever.mesh = lever_mb.build()
	lever.position = Vector3(0, 1.38, -0.17)
	prop.add_child(lever)
	var it := Interactable.new()
	it.position = Vector3(0, 1.4, -0.2)
	prop.add_child(it)
	var circuits: Circuits = session.circuits if session != null and "circuits" in session else null
	var update := func():
		var on := circuits.is_on(key) if circuits != null else true
		lever.rotation.x = deg_to_rad(-28.0 if on else 28.0)
	update.call()
	it.prompt_cb = func(_p): return "Throw the breaker (%s)" % ("on" if (circuits == null or circuits.is_on(key)) else "off")
	it.tap_cb = func(_p):
		if circuits == null:
			return
		circuits.toggle(key)
		update.call()
		AudioDirector.play_at(&"breaker_thunk", prop.global_position)
		EventBus.noise_emitted.emit(prop.global_position, 0.5, &"breaker")
		EventBus.toast.emit("The breaker thunks.")


static func _wire_switch(chunk: Chunk, prop: Node3D, session: Node, beat: FloorPlan.BeatPlan) -> void:
	var key := _circuit_key(chunk, beat, session)
	var it := Interactable.new()
	it.position = Vector3(0, 1.25, -0.08)
	it.max_range = GameScale.INTERACT_RANGE + 0.2
	prop.add_child(it)
	var circuits: Circuits = session.circuits if session != null and "circuits" in session else null
	it.prompt_cb = func(_p): return "Flip the switch"
	it.tap_cb = func(_p):
		if circuits == null:
			return
		circuits.toggle(key)
		AudioDirector.play_at(&"switch_click", prop.global_position)
		EventBus.noise_emitted.emit(prop.global_position, 0.2, &"switch")


static func _wire_suggestion_box(prop: Node3D, session: Node) -> void:
	var it := Interactable.new()
	it.position = Vector3(0, 1.3, -0.25)
	prop.add_child(it)
	it.prompt_cb = func(_p):
		if session != null and session.has_method("verdict_filed") and session.verdict_filed():
			return "Feedback received"
		return "File a comment card"
	it.can_cb = func(_p): return session != null and session.has_method("open_suggestion_box")
	it.tap_cb = func(_p):
		if session != null and session.has_method("open_suggestion_box"):
			session.open_suggestion_box()


static func _wire_charger(prop: Node3D) -> void:
	var it := Interactable.new()
	it.position = Vector3(0, 1.0, -0.2)
	prop.add_child(it)
	it.prompt_cb = func(_p): return "Charge the camcorder (%d%%)" % int(RunState.battery)
	it.can_cb = func(_p): return RunState.battery < 99.5
	it.tap_cb = func(_p):
		RunState.set_battery(100.0)
		AudioDirector.play_at(&"battery_pickup", prop.global_position)
		EventBus.toast.emit("Fully charged.")


# --- light-based evidence & fixtures --------------------------------------------------------

static func _light_evidence(chunk: Chunk, e: EvidenceDef, rng: RandomNumberGenerator, _session: Node) -> void:
	## Evidence that follows the light: claws under dead (HOLDS) or lit (INVERTED) cells, dust on dead fixtures,
	## scorch halos on lit ones. One EvidenceMark per mark, so "looking at it" means looking at it.
	var recipe := String(e.params.get("recipe", ""))
	match recipe:
		"claw":
			var want_dead := String(e.params.get("under", "dead")) == "dead"
			for cell in chunk.cells:
				var dead := not (cell.is_lit() and cell.powered)
				if cell.circuit != &"" and not cell.powered:
					dead = true
				if dead != want_dead:
					continue
				if not want_dead and rng.randf() > 0.7:
					continue          # INVERTED: most lit cells are marked, not all
				var tiles: Array = cell.region.duplicate()
				if tiles.is_empty():
					continue
				var t: Vector2i = tiles[rng.randi() % tiles.size()]
				var c := local_center(chunk, chunk.world_tile_to_local(t)) + Vector3(rng.randf_range(-0.3, 0.3), 0.012, rng.randf_range(-0.3, 0.3))
				var mb := MeshBuilder.new()
				_claws(mb, Vector3.ZERO, rng.randf() * TAU)
				_mark_node(chunk, e, mb, c)
		"dust":
			for cell in chunk.cells:
				if not (cell.is_lit() and cell.powered) or (cell.circuit != &"" and not cell.powered):
					var c2 := ChunkBuilder.local_center(cell.local_tile, GameScale.WALL_H - 0.045)
					var mb2 := MeshBuilder.new()
					mb2.ceiling_quad(&"#8d887a", -0.42, -0.42, 0.42, 0.42, 0.0)
					_mark_node(chunk, e, mb2, c2)
		"scorch":
			for cell in chunk.cells:
				if cell.is_lit() and cell.circuit == &"":
					var c3 := ChunkBuilder.local_center(cell.local_tile, GameScale.WALL_H - 0.043)
					var mb3 := MeshBuilder.new()
					mb3.ceiling_quad(&"#1d1712", -0.62, -0.62, 0.62, 0.62, 0.0)
					_mark_node(chunk, e, mb3, c3)
		_:
			EvidenceRecipes.place(chunk, e, rng, _session)


static func _mark_node(chunk: Chunk, e: EvidenceDef, mb: MeshBuilder, pos: Vector3) -> void:
	var holder := EvidenceMark.create(e)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)
	chunk.props_root.add_child(holder)
	holder.position = pos
	holder.needs_light = true


static func _claws(mb: MeshBuilder, c: Vector3, yaw: float) -> void:
	for i in 3:
		var off := (float(i) - 1.0) * 0.07
		var dx := cos(yaw)
		var dz := sin(yaw)
		var cx := c.x - dz * off
		var cz := c.z + dx * off
		mb.box(&"#140e09", Vector3(cx, c.y, cz), Vector3(0.025 + absf(dx) * 0.4, 0.004, 0.025 + absf(dz) * 0.4))


static func _fixtures(chunk: Chunk, _session: Node) -> void:
	for cell in chunk.cells:
		var f := LightFixture.create(cell)
		chunk.props_root.add_child(f)
		f.position = ChunkBuilder.local_center(cell.local_tile, GameScale.WALL_H - 0.12)
