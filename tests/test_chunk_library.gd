extends TestCase
## Every authored room must obey the chunk contract (see "Making a room" in the README) so the floor generator
## can never be handed a room it cannot use.

const MAX_SIDE := 48


func _beat_rules(spec: ChunkSpec) -> void:
	var id := String(spec.id)
	var entries := spec.entries.size()
	var exits := spec.exits.size()
	var stats := ChunkLibrary.panel_stats(spec)
	match spec.beat:
		&"arrival":
			assert_true(exits >= 1, "%s: arrival needs an exit (the elevator doors)" % id)
			assert_true(ChunkLibrary.slot_count(spec, &"anchor") >= 1, "%s: arrival needs a 'u' anchor = player spawn" % id)
		&"departure":
			assert_true(entries >= 1, "%s: departure needs an entry (the elevator doors)" % id)
		&"choice":
			assert_true(entries >= 1 and exits >= 1, "%s: choice needs an entry and an exit" % id)
		&"long":
			assert_true(entries >= 1 and exits >= 1, "%s: long room needs an entry and an exit" % id)
			assert_true(spec.open.size() >= 120, "%s: a Long Room is big (>= 120 tiles, has %d)" % [id, spec.open.size()])
			assert_true(spec.panels.size() >= 6, "%s: a Long Room needs >= 6 light panels" % id)
			assert_true(ChunkLibrary.slot_count(spec, &"suggestion_box") >= 1, "%s: a Long Room holds a Suggestion Box 'x' (Verdicts are filed before the exam)" % id)
		&"exam":
			assert_true(entries >= 1 and exits >= 1, "%s: exam needs an entry and an exit" % id)
			if spec.floors.has(&"boiler"):
				assert_true(exits >= 2, "%s: the Boiler exam needs >= 2 exits (\"nearest exit\" must be a choice)" % id)
		&"rest":
			assert_true(entries >= 1 and exits >= 1, "%s: rest needs an entry and an exit" % id)
			assert_true(ChunkLibrary.slot_count(spec, &"charger") >= 1, "%s: a rest room has a charger 'r'" % id)
			assert_eq(stats["dead"], 0, "%s: a rest room has no dead panels" % id)
		&"side":
			assert_true(entries >= 1, "%s: side room needs an entry" % id)
			assert_eq(exits, 0, "%s: side rooms are dead ends (no exits)" % id)
			if spec.tags.has(&"vault"):
				assert_true(ChunkLibrary.slot_count(spec, &"tape") >= 1, "%s: a vault has a tape slot 't'" % id)
			if spec.tags.has(&"closet"):
				assert_true(ChunkLibrary.slot_count(spec, &"loot") >= 1, "%s: a closet has a loot slot 'i'" % id)
			if spec.tags.has(&"breaker"):
				assert_true(ChunkLibrary.slot_count(spec, &"breaker") >= 1, "%s: a breaker room has a breaker 'b'" % id)
		_:
			assert_true(false, "%s: unknown beat kind '%s'" % [id, spec.beat])


func _chunk_files(dir: String, out: PackedStringArray) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".chunk"):
			out.append("%s/%s" % [dir, f])
	for d in DirAccess.get_directories_at(dir):
		if d != "dev":
			_chunk_files("%s/%s" % [dir, d], out)


func test_all_chunks_parse_clean() -> void:
	## Parse every file ourselves (a broken room must FAIL here, not silently vanish from the pool), then check the
	## library holds exactly those rooms.
	var files := PackedStringArray()
	_chunk_files(ChunkLibrary.ROOT, files)
	assert_true(files.size() > 0, "no chunks found under res://content/chunks")
	var ids := {}
	for path in files:
		var spec := ChunkSpec.load_file(path)
		for e in spec.errors:
			assert_true(false, "chunk file problem: %s: %s" % [path, e])
		assert_false(ids.has(spec.id), "duplicate chunk id %s (%s)" % [spec.id, path])
		ids[spec.id] = true
	ChunkLibrary.reload()
	assert_eq(ChunkLibrary.all().size(), ids.size(), "ChunkLibrary dropped rooms that exist on disk")
	for e in ChunkLibrary.load_errors:
		assert_true(false, "chunk library problem: %s" % e)


func test_beat_contracts() -> void:
	ChunkLibrary.reload()
	for spec in ChunkLibrary.all():
		assert_true(spec.width <= MAX_SIDE and spec.height <= MAX_SIDE, "%s: too big (%dx%d)" % [spec.id, spec.width, spec.height])
		_beat_rules(spec)
		assert_true(spec.panels.size() > 0 or spec.beat == &"side", "%s: needs at least one light panel" % spec.id)


func test_every_floor_has_a_pool() -> void:
	ChunkLibrary.reload()
	for fid in FloorCatalog.ORDER:
		var def := FloorCatalog.get_def(fid)
		var kinds := {}
		for k in def.beat_grammar:
			kinds[k] = true
		for k in kinds:
			assert_true(ChunkLibrary.pool(fid, k).size() >= 1, "floor %s has no '%s' room" % [fid, k])
		assert_true(ChunkLibrary.pool(fid, &"side").size() >= 3, "floor %s needs >= 3 side rooms" % fid)
		var graffiti_hosts := 0
		var dead_hosts := 0
		var lit_hosts := 0
		for s in ChunkLibrary.pool(fid, &"choice") + ChunkLibrary.pool(fid, &"long"):
			var st := ChunkLibrary.panel_stats(s)
			if ChunkLibrary.slot_count(s, &"graffiti") > 0:
				graffiti_hosts += 1
			if st["dead"] + st["switchable"] > 0:
				dead_hosts += 1
			if st["lit"] > 0:
				lit_hosts += 1
		if fid != &"lobby":
			assert_true(graffiti_hosts >= 2, "floor %s needs >= 2 choice/long rooms with a graffiti slot 'g'" % fid)
			assert_true(dead_hosts >= 2 and lit_hosts >= 2, "floor %s needs rooms with dead panels and rooms with lit panels" % fid)


func test_yellow_vertical_slice_kit() -> void:
	ChunkLibrary.reload()
	var want := {&"arrival": 1, &"choice": 5, &"long": 2, &"exam": 1, &"rest": 1, &"departure": 1, &"side": 4}
	for k in want:
		assert_true(ChunkLibrary.pool(&"yellow", k).size() >= int(want[k]), "yellow needs >= %d '%s' rooms (has %d)" % [want[k], k, ChunkLibrary.pool(&"yellow", k).size()])


# --- physical reachability (props are solid; the generator can only promise doors, not prop-free floors) -------

## Floor-standing props that fill (most of) a tile. Wall-mounted lockers/cabinets leave a 0.65 m lane, which the
## 0.6 m guest capsule can only just use, so they must never sit beside a door.
const FILLS_TILE: Array[StringName] = [&"desk", &"hide_desk", &"plant", &"boxes", &"chair", &"wet_sign", &"stanchion", &"cooler"]
const BULKY_WALL: Array[StringName] = [&"hide_closet", &"cabinet"]


func _slot_kind_at(spec: ChunkSpec, t: Vector2i) -> StringName:
	for sl in spec.slots:
		if sl.tile == t:
			return sl.kind
	return &""


func test_nothing_bulky_beside_a_door() -> void:
	## "Keep a clear 1-tile apron in front of every socket" (room authoring rule): a closet on the tile next to
	## an exit leaves a lane the guest barely fits through, and a desk or plant there blocks the door outright.
	ChunkLibrary.reload()
	var bad := PackedStringArray()
	for spec in ChunkLibrary.all():
		for sock in spec.exits + spec.entries:
			for d in ChunkSpec.DIRS_ORDER:
				if not spec.can_step(sock.tile, d):
					continue
				var kind := _slot_kind_at(spec, sock.tile + d)
				if kind in FILLS_TILE or kind in BULKY_WALL:
					bad.append("%s: '%s' at %s is beside the %s socket at %s" % [spec.id, kind, sock.tile + d, sock.kind, sock.tile])
	assert_eq(bad.size(), 0, "bulky props beside doors:\n  " + "\n  ".join(bad))


func test_every_door_reaches_every_other_door_around_solid_props() -> void:
	ChunkLibrary.reload()
	var bad := PackedStringArray()
	for spec in ChunkLibrary.all():
		var socks: Array = spec.exits + spec.entries
		if socks.size() < 2:
			continue
		var seen := {}
		var q: Array[Vector2i] = [(socks[0] as ChunkSpec.SocketDef).tile]
		seen[q[0]] = true
		var head := 0
		while head < q.size():
			var cur: Vector2i = q[head]
			head += 1
			for d in ChunkSpec.DIRS_ORDER:
				var n := cur + d
				if seen.has(n) or not spec.can_step(cur, d):
					continue
				if _slot_kind_at(spec, n) in FILLS_TILE:
					continue
				seen[n] = true
				q.append(n)
		for sock in socks:
			if not seen.has((sock as ChunkSpec.SocketDef).tile):
				bad.append("%s: socket at %s cannot be reached around solid props" % [spec.id, (sock as ChunkSpec.SocketDef).tile])
	assert_eq(bad.size(), 0, "unreachable doors:\n  " + "\n  ".join(bad))


func test_chunk_rows_are_all_the_same_width() -> void:
	## A typo that adds or drops a character shifts everything after it (and a socket can slip off the wall line)
	## without any parse error, so check the raw files.
	var files := PackedStringArray()
	_chunk_files(ChunkLibrary.ROOT, files)
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		var parts := text.split("\n---\n", true, 1)
		if parts.size() < 2:
			parts = text.split("---\n", true, 1)
		assert_true(parts.size() == 2, "%s: no '---' separator" % path)
		if parts.size() < 2:
			continue
		var widths := {}
		for row in parts[1].strip_edges(false, true).split("\n"):
			widths[row.length()] = true
		assert_eq(widths.size(), 1, "%s: rows have different widths %s" % [path, widths.keys()])
