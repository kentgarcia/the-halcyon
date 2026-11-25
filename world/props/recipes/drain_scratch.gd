extends RefCounted
## P2 recipe `drain_scratch` (B2 Natatorium, HOLDS): the water is calm and the drain grates are scored with
## fingernails. True evidence: in HOLDS a guest who moves during the freeze is pulled to a drain (SPEC 6.3); the
## grates are real (PoolSite builds them in every wet room, scratched or not) and the scratches sit only on
## HOLDS runs.

const SCORE := &"#d7dddf"
const RIM_SCORE := &"#9aa6aa"


static func can_host(spec: ChunkSpec, _e: EvidenceDef) -> bool:
	return PoolSite.has_pool(spec)


static func place(chunk: Chunk, e: EvidenceDef, rng: RandomNumberGenerator, session: Node) -> void:
	var info := PoolSite.ensure(chunk, session)
	if info.is_empty():
		return
	for gn: Node3D in info["grate_nodes"]:
		var mb := MeshBuilder.new()
		for i in 5:
			var x := (float(i) - 2.0) * 0.062 + rng.randf_range(-0.014, 0.014)
			var a := Vector3(x, 0.0, -0.44 + rng.randf_range(0.0, 0.08))
			var b := Vector3(x + rng.randf_range(-0.05, 0.05), 0.0, 0.44 - rng.randf_range(0.0, 0.08))
			MarkShapes.floor_line(mb, SCORE, a, b, 0.02, 0.043)
		for k in 3:
			var xr := (float(k) - 1.0) * 0.09
			MarkShapes.floor_line(mb, RIM_SCORE, Vector3(xr, 0.0, 0.5), Vector3(xr + 0.03, 0.0, 0.66), 0.018, 0.027)
		var mark := MarkShapes.mark_node(e, mb)
		chunk.props_root.add_child(mark)
		mark.position = gn.position
		mark.read_radius = 7.5
