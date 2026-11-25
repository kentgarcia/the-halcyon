class_name StubsRecipe
extends RefCounted
## P2 evidence of the Queue (SPEC 6.4): torn ticket stubs scattered AHEAD of the line (HOLDS: the line only ever
## moves forward, people were called and left their stubs at the window) vs BEHIND it (INVERTED: the line takes steps
## toward whoever holds a number, so the stubs lie where it came from). EvidenceDef.params {where: "ahead" | "behind"}.
## A room cannot show a line that is not there, so the room carries its own floor guide: a strip of yellow tape with
## chevrons pointing toward the window and a START bar across the tail. "Ahead" and "behind" are read off that guide.

const PLAIN := [".", ",", "L", "l", "S"]
const MIN_RUN := 5
const MAX_RUN := 9
const TAPE := &"#c9a227"
const CHEVRON := &"#7a1f1f"
const PAPER := &"#d9d3b6"
const STUB_RED := &"#8e2a2a"


static func find_runs(spec: ChunkSpec) -> Array[Dictionary]:
	## Straight runs of plain floor, >= MIN_RUN long: [{tiles: Array[Vector2i], dir: Vector2i}] (dir = E or S).
	var out: Array[Dictionary] = []
	for t: Vector2i in spec.open:
		for d in [Dir.E, Dir.S]:
			var prev: Vector2i = t - d
			if spec.open.has(prev) and PLAIN.has(String(spec.open[prev])) and spec.can_step(prev, d):
				continue
			var run: Array[Vector2i] = []
			var cur := t
			while spec.open.has(cur) and PLAIN.has(String(spec.open[cur])) and run.size() < MAX_RUN:
				run.append(cur)
				if not spec.can_step(cur, d):
					break
				cur += d
			if run.size() >= MIN_RUN:
				out.append({"tiles": run, "dir": d})
	return out


static func can_host(spec: ChunkSpec, _e: EvidenceDef) -> bool:
	return not find_runs(spec).is_empty()


static func place(chunk: Chunk, e: EvidenceDef, rng: RandomNumberGenerator, _session: Node) -> void:
	var runs := find_runs(chunk.spec)
	if runs.is_empty():
		return
	var pick: Dictionary = runs[rng.randi() % runs.size()]
	var tiles: Array[Vector2i] = []
	tiles.assign(pick["tiles"])
	var dir: Vector2i = pick["dir"]
	if rng.randf() < 0.5:                 # which way the guide points is rolled: the guest must read the chevrons
		tiles.reverse()
		dir = -dir
	var ahead := String(e.params.get("where", "ahead")) == "ahead"
	_floor_guide(chunk, tiles, dir)
	var n := tiles.size()
	var sites: Array[Vector3] = []
	if ahead:
		# in front of the head: the last two tiles of the run and the tile beyond when there is one
		sites.append(ChunkBuilder.local_center(tiles[n - 1]))
		sites.append(ChunkBuilder.local_center(tiles[n - 2]))
		var beyond := tiles[n - 1] + dir
		sites.append(ChunkBuilder.local_center(beyond if chunk.spec.open.has(beyond) else tiles[n - 1]) + Dir.to_vec3(Dir.rot(dir, 1)) * 0.45)
	else:
		sites.append(ChunkBuilder.local_center(tiles[0]))
		sites.append(ChunkBuilder.local_center(tiles[1]))
		var before := tiles[0] - dir
		sites.append(ChunkBuilder.local_center(before if chunk.spec.open.has(before) else tiles[0]) + Dir.to_vec3(Dir.rot(dir, 1)) * 0.45)
	for s in sites:
		_stub_cluster(chunk, e, s, rng)


static func _floor_guide(chunk: Chunk, tiles: Array[Vector2i], dir: Vector2i) -> void:
	var mb := MeshBuilder.new()
	var T := GameScale.TILE
	var a := ChunkBuilder.local_center(tiles[0])
	var b := ChunkBuilder.local_center(tiles[tiles.size() - 1])
	var along := Dir.to_vec3(dir)
	var side := Dir.to_vec3(Dir.rot(dir, 1))
	var y := 0.007
	# the tape strip along the run
	var mid := (a + b) * 0.5
	var len := (b - a).length() + T
	mb.box(TAPE, Vector3(mid.x, y, mid.z), Vector3(maxf(0.12, absf(along.x) * len), 0.004, maxf(0.12, absf(along.z) * len)))
	# START bar across the tail
	var sb := a - along * (T * 0.45)
	mb.box(TAPE, Vector3(sb.x, y, sb.z), Vector3(maxf(0.12, absf(side.x) * 1.0), 0.004, maxf(0.12, absf(side.z) * 1.0)))
	# chevrons pointing along `dir`, every second tile
	for i in range(1, tiles.size(), 2):
		var c := ChunkBuilder.local_center(tiles[i])
		for k in 3:
			var back := float(k) * 0.07
			for sgn in [-1.0, 1.0]:
				var p: Vector3 = c - along * back + side * (sgn * (0.18 - back * 0.9))
				mb.box(CHEVRON, Vector3(p.x, y + 0.002, p.z), Vector3(0.07, 0.004, 0.07))
	var mi := MeshInstance3D.new()
	mi.name = "QueueFloorGuide"
	mi.mesh = mb.build()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.props_root.add_child(mi)


static func _stub_cluster(chunk: Chunk, e: EvidenceDef, at: Vector3, rng: RandomNumberGenerator) -> void:
	var mark := EvidenceMark.create(e)
	chunk.props_root.add_child(mark)
	mark.position = Vector3(at.x, 0.012, at.z)
	var mb := MeshBuilder.new()
	for i in 4 + rng.randi() % 3:
		var p := Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.5, 0.5))
		var wide := rng.randf() < 0.5
		var sz := Vector3(0.09 if wide else 0.055, 0.004, 0.055 if wide else 0.09)
		mb.box(PAPER, p, sz)
		mb.box(STUB_RED, p + Vector3(0, 0.003, 0), Vector3(sz.x * 0.35, 0.002, sz.z * 0.35))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mark.add_child(mi)
	mark.needs_light = true
