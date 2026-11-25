extends RefCounted
## P2 recipe `scrape` (B3 Boiler, HOLDS): pipe-wrench scrapes on the floor lead AWAY from the exits TOWARD the alarm
## bell. True evidence: the HOLDS Foreman comes in through an exit and walks to the bell (SPEC 6.2). Each streak
## ends in a chevron pointing the way he went, so the direction of travel can be read off the floor.

const NEAR_EXIT := [0.9, 2.4, 3.9, 5.4, 6.9, 8.4]       ## metres from the door where streaks lie
const NEAR_BELL := [2.6, 1.2]                           ## metres short of the bell
const MAX_MARKS := 20

const SCUFF := &"#25221e"
const STEEL := &"#a9aeb1"


static func can_host(spec: ChunkSpec, _e: EvidenceDef) -> bool:
	if spec.exits.is_empty():
		return false
	var probe := RandomNumberGenerator.new()
	return not AlarmSite.bell_site(spec, probe).is_empty()


static func place(chunk: Chunk, e: EvidenceDef, rng: RandomNumberGenerator, session: Node) -> void:
	var bell := AlarmSite.ensure_bell(chunk, session)
	if bell == null:
		return
	var placed := 0
	for s: ChunkSpec.SocketDef in chunk.spec.exits:
		if session != null:
			var ex := {"tile": chunk.local_tile_to_world(s.tile), "dir": chunk.local_dir_to_world(s.dir), "index": s.index}
			if AlarmSite.exit_door(session, ex) != null and not AlarmSite.usable(AlarmSite.exit_door(session, ex)):
				continue
		var route := AlarmSite.local_path(chunk.spec, s.tile, bell.local_tile)
		if route.size() < 3:
			continue
		placed += _trail(chunk, e, route, rng)
		if placed >= MAX_MARKS:
			break


static func _trail(chunk: Chunk, e: EvidenceDef, route: Array[Vector2i], rng: RandomNumberGenerator) -> int:
	## Streaks at fixed distances along the route (metres from the door), the last ones just before the bell.
	var pts: Array[Vector3] = []
	for t in route:
		pts.append(ChunkBuilder.local_center(t))
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	var dists: Array[float] = []
	for d: float in NEAR_EXIT:
		if d < total - 1.0:
			dists.append(d)
	for d: float in NEAR_BELL:
		var s := total - d
		if s > 0.5 and not dists.has(s):
			dists.append(s)
	var n := 0
	for s in dists:
		var at := _along(pts, s)
		var dir: Vector3 = at["dir"]
		var side := Vector3(-dir.z, 0.0, dir.x)
		var pos: Vector3 = at["pos"] + side * rng.randf_range(-0.16, 0.16)
		var mb := MeshBuilder.new()
		_streak(mb, Vector2(dir.x, dir.z), rng)
		var mark := MarkShapes.mark_node(e, mb)
		chunk.props_root.add_child(mark)
		mark.position = Vector3(pos.x, 0.0, pos.z)
		mark.read_radius = 7.5
		n += 1
	return n


static func _along(pts: Array[Vector3], s: float) -> Dictionary:
	var acc := 0.0
	for i in range(1, pts.size()):
		var seg := pts[i - 1].distance_to(pts[i])
		if acc + seg >= s or i == pts.size() - 1:
			var f := clampf((s - acc) / maxf(seg, 0.001), 0.0, 1.0)
			var dir := (pts[i] - pts[i - 1]).normalized()
			return {"pos": pts[i - 1].lerp(pts[i], f), "dir": dir}
		acc += seg
	return {"pos": pts[0], "dir": Vector3(1, 0, 0)}


static func _streak(mb: MeshBuilder, dir: Vector2, rng: RandomNumberGenerator) -> void:
	## A scuffed band, two bright scores, and a chevron at the leading end (direction of travel = dir).
	var o := Vector3.ZERO
	MarkShapes.floor_rect(mb, SCUFF, o, dir, 1.05, 0.17, 0.010)
	var side := Vector2(-dir.y, dir.x)
	for k in 2:
		var lat := side * (0.035 if k == 0 else -0.045)
		var len := 0.95 - 0.2 * float(k)
		MarkShapes.floor_rect(mb, STEEL, Vector3(lat.x, 0.0, lat.y), dir, len, 0.026, 0.013)
	var tip := dir * 0.52
	for sgn in [-1.0, 1.0]:
		var back := dir.rotated(PI + sgn * 0.6)
		var c := tip + back * 0.085
		MarkShapes.floor_rect(mb, STEEL, Vector3(c.x, 0.0, c.y), back, 0.17, 0.034, 0.014)
