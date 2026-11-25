class_name ChunkBuilder
extends RefCounted
## ChunkSpec + FloorTheme + placement -> Chunk node: merged static geometry (one surface per material),
## a dynamic panel mesh (ceiling fixtures follow their LightCell state), colliders, light cells,
## and slot props. Everything is built in the chunk's LOCAL space; Chunk.setup_transform() places it.

const WALL_T := 0.2              ## collider thickness at room boundaries
const THIN_T := 0.14             ## collider thickness of interior thin partitions
const FLOOR_T := 0.3
const SEG_LEN := 4               ## wall material segment length in tiles

static var last_split := ""      ## dev/perf: where the last build spent its time


static func build(spec: ChunkSpec, theme: FloorTheme, rot: int, offset: Vector2i, uid: int,
		beat_index: int = -1, plan: Dictionary = {}) -> Chunk:
	var chunk := Chunk.new()
	chunk.name = "Chunk_%s_%d" % [spec.id, uid]
	chunk.spec = spec
	chunk.theme = theme
	chunk.uid = uid
	chunk.rot = rot
	chunk.offset = offset
	chunk.beat_index = beat_index
	chunk.plan = plan
	chunk.decay = clampi(int(plan.get("decay", spec.decay + theme.decay_bias)), 0, 3)
	chunk.setup_transform()

	for t: Vector2i in spec.open:
		chunk.world_open[chunk.local_tile_to_world(t)] = true

	var t0 := Time.get_ticks_usec()
	_build_static(chunk)
	var t1 := Time.get_ticks_usec()
	_build_collision(chunk)
	var t2 := Time.get_ticks_usec()
	_build_cells(chunk)
	var t3 := Time.get_ticks_usec()
	last_split = "static %.1f collision %.1f cells %.1f" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0]
	chunk.panels = MeshInstance3D.new()
	chunk.panels.name = "Panels"
	chunk.panels.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(chunk.panels)
	rebuild_panels(chunk)
	chunk.props_root = Node3D.new()
	chunk.props_root.name = "Props"
	chunk.add_child(chunk.props_root)

	for s in spec.exits:
		chunk.exit_world.append({"tile": chunk.local_tile_to_world(s.tile), "dir": chunk.local_dir_to_world(s.dir), "index": s.index})
	for s in spec.entries:
		chunk.entry_world.append({"tile": chunk.local_tile_to_world(s.tile), "dir": chunk.local_dir_to_world(s.dir), "index": s.index})
	return chunk


# --- helpers --------------------------------------------------------------------------------

static func _h(spec_id: StringName, a: int, b: int) -> int:
	return RngStreams.mix(RngStreams.mix(String(spec_id).hash(), a), b)


static func edge_line_along(t: Vector2i, d: Vector2i) -> Vector2i:
	## (line, along) of the wall edge toward d of tile t: line is the grid line the edge lies on,
	## along is the tile index along that line.
	if d.y == -1:
		return Vector2i(t.y, t.x)
	if d.y == 1:
		return Vector2i(t.y + 1, t.x)
	if d.x == -1:
		return Vector2i(t.x, t.y)
	return Vector2i(t.x + 1, t.y)


static func local_center(t: Vector2i, y: float = 0.0) -> Vector3:
	return Vector3((t.x + 0.5) * GameScale.TILE, y, (t.y + 0.5) * GameScale.TILE)


static func ceiling_material(size: StringName, kind: String) -> StringName:
	var name := StringName("ceiling_%s%s" % [size, kind])
	if MaterialLibrary.has_texture(name):
		return name
	# not every size ships every variant (e.g. small has no _open): fall back to a sibling
	for alt in [&"medium", &"large", &"small"]:
		var n2 := StringName("ceiling_%s%s" % [alt, kind])
		if MaterialLibrary.has_texture(n2):
			return n2
	return StringName("ceiling_%s" % size)


# --- static geometry ------------------------------------------------------------------------

static var _mesh_cache: Dictionary = {}     ## "spec|theme|decay" -> ArrayMesh (chunk-local space, shared)


static func warm(spec: ChunkSpec, theme: FloorTheme, decay: int) -> void:
	## Pre-compute everything about a room that does not depend on where it is placed, so the first time the
	## guest opens a door onto it the build is mostly node creation. Called a room or two at a time while idle.
	_static_mesh(spec, theme, clampi(decay, 0, 3))
	_collision_shapes(spec)
	if not spec.panels.is_empty():
		_cell_topology(spec)


static func _static_mesh(spec: ChunkSpec, theme: FloorTheme, decay: int) -> Mesh:
	var key := "%s|%s|%d" % [spec.id, theme.id, decay]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var mesh := _make_static_mesh(spec, theme, decay)
	_mesh_cache[key] = mesh
	return mesh


static func _build_static(chunk: Chunk) -> void:
	var mesh := _static_mesh(chunk.spec, chunk.theme, chunk.decay)
	chunk.geometry = MeshInstance3D.new()
	chunk.geometry.name = "Geometry"
	chunk.geometry.mesh = mesh
	chunk.geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	chunk.add_child(chunk.geometry)


static func _make_static_mesh(spec: ChunkSpec, theme: FloorTheme, decay: int) -> Mesh:
	var T := GameScale.TILE
	var H := GameScale.WALL_H
	var mb := MeshBuilder.new()
	var socket_edges := spec.socket_edges()
	var panel_tiles := {}
	for p: ChunkSpec.PanelDef in spec.panels:
		panel_tiles[p.tile] = true

	var floor_override: StringName = spec.floor_mat
	for t: Vector2i in spec.open:
		var x0 := t.x * T
		var z0 := t.y * T
		var glyph: String = spec.open[t]
		# floor
		var fm: StringName
		if floor_override != &"":
			fm = floor_override
		elif glyph == ",":
			fm = spec.floor_alt_mat if spec.floor_alt_mat != &"" else theme.floor_alt
		else:
			fm = theme.pick_floor(_h(spec.id, t.x, t.y))
		mb.floor_quad(fm, x0, z0, x0 + T, z0 + T, 0.0)
		# ceiling (panel tiles are drawn by the dynamic panel mesh)
		if not panel_tiles.has(t):
			var cm: StringName
			if spec.ceiling_holes.has(t):
				cm = ceiling_material(spec.ceiling, "_open")
			elif float(absi(_h(spec.id, t.x * 3 + 1, t.y * 5 + 2)) % 1000) / 1000.0 < theme.ceiling_uneven_chance:
				cm = ceiling_material(spec.ceiling, "_uneven")
			else:
				cm = ceiling_material(spec.ceiling, "")
			mb.ceiling_quad(cm, x0, z0, x0 + T, z0 + T, H)

	# walls: boundary edges + thin partitions. Collect, then assign materials per 4-tile segment.
	var damaged_chance: float = [0.0, 0.12, 0.3, 0.55][decay]
	for t: Vector2i in spec.open:
		for di in ChunkSpec.DIRS_ORDER.size():
			var d: Vector2i = ChunkSpec.DIRS_ORDER[di]
			var key := ChunkSpec.edge_key(t, d)
			var is_wall := false
			if spec.open.has(t + d):
				is_wall = spec.thin_walls.has(key)
			else:
				is_wall = not socket_edges.has(key)
			if not is_wall:
				continue
			var la := edge_line_along(t, d)
			var line := la.x
			var along := la.y
			var seg := floori(float(along) / SEG_LEN)
			var mat: StringName
			if spec.pillars.has(t + d):
				mat = theme.pillar_mat
			elif spec.wall_mat != &"":
				mat = spec.wall_mat
			else:
				mat = theme.pick_wall(_h(spec.id, di * 100003 + line * 31 + 7, seg * 977 + 13), damaged_chance)
			var edge_center := Vector3((t.x + 0.5 + d.x * 0.5) * T, 0.0, (t.y + 0.5 + d.y * 0.5) * T)
			mb.wall_quad(mat, edge_center, d, T, H)

	return mb.build()


# --- collision ------------------------------------------------------------------------------

static var _shape_cache: Dictionary = {}    ## ChunkSpec -> Array of [Shape3D, Vector3] (chunk-local, shared)


static func _build_collision(chunk: Chunk) -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = GameScale.LAYER_WORLD
	body.collision_mask = 0
	chunk.body = body
	chunk.add_child(body)
	for entry: Array in _collision_shapes(chunk.spec):
		var cs := CollisionShape3D.new()
		cs.shape = entry[0]
		cs.position = entry[1]
		body.add_child(cs)


static func _collision_shapes(spec: ChunkSpec) -> Array:
	if _shape_cache.has(spec):
		return _shape_cache[spec]
	var out: Array = []
	var T := GameScale.TILE
	var H := GameScale.WALL_H

	# floor slab under the bounding rectangle of open tiles
	var minx := 1 << 30
	var miny := 1 << 30
	var maxx := -(1 << 30)
	var maxy := -(1 << 30)
	for t: Vector2i in spec.open:
		minx = mini(minx, t.x)
		miny = mini(miny, t.y)
		maxx = maxi(maxx, t.x)
		maxy = maxi(maxy, t.y)
	var fb := BoxShape3D.new()
	fb.size = Vector3((maxx - minx + 1) * T + 0.6, FLOOR_T, (maxy - miny + 1) * T + 0.6)
	out.append([fb, Vector3((minx + maxx + 1) * 0.5 * T, -FLOOR_T * 0.5, (miny + maxy + 1) * 0.5 * T)])

	var socket_edges := spec.socket_edges()
	# collect wall edges by (dir, line, thin) -> list of tile indices along the line
	var groups: Dictionary = {}
	for t: Vector2i in spec.open:
		for d in ChunkSpec.DIRS_ORDER:
			var key := ChunkSpec.edge_key(t, d)
			var is_boundary := not spec.open.has(t + d) and not socket_edges.has(key)
			var is_thin := spec.open.has(t + d) and spec.thin_walls.has(key)
			if not is_boundary and not is_thin:
				continue
			# a thin wall is recorded from both sides; keep the E/S record only
			if is_thin and (d.y == -1 or d.x == -1):
				continue
			var la := edge_line_along(t, d)
			var gk := "%d:%d:%d:%s" % [d.x, d.y, la.x, "t" if is_thin else "b"]
			if not groups.has(gk):
				groups[gk] = {"dir": d, "line": la.x, "thin": is_thin, "alongs": []}
			(groups[gk]["alongs"] as Array).append(la.y)

	for gk in groups:
		var g: Dictionary = groups[gk]
		var alongs: Array = g["alongs"]
		alongs.sort()
		var d: Vector2i = g["dir"]
		var thin: bool = g["thin"]
		var thick := THIN_T if thin else WALL_T
		var run_start: int = alongs[0]
		var prev: int = run_start
		for i in range(1, alongs.size() + 1):
			var cur: int = alongs[i] if i < alongs.size() else -999999
			if cur == prev + 1:
				prev = cur
				continue
			out.append(_wall_shape(d, int(g["line"]), run_start, prev, thick, thin, T, H))
			run_start = cur
			prev = cur
	_shape_cache[spec] = out
	return out


static func _wall_shape(d: Vector2i, line: int, a0: int, a1: int,
		thick: float, thin: bool, T: float, H: float) -> Array:
	var length := (a1 - a0 + 1) * T + thick
	var mid := (a0 + a1 + 1) * 0.5 * T
	var bs := BoxShape3D.new()
	var pos: Vector3
	var shift := 0.0 if thin else thick * 0.5
	if d.y != 0:   # horizontal wall (runs along x)
		bs.size = Vector3(length, H, thick)
		pos = Vector3(mid, H * 0.5, line * T + d.y * shift)
	else:          # vertical wall (runs along z)
		bs.size = Vector3(thick, H, length)
		pos = Vector3(line * T + d.x * shift, H * 0.5, mid)
	return [bs, pos]


# --- light cells ----------------------------------------------------------------------------

static var _topology: Dictionary = {}    ## ChunkSpec -> cell topology in local tiles (rotation-independent)


static func _cell_topology(spec: ChunkSpec) -> Dictionary:
	## Which panel owns each walkable tile, the light footprint of each panel, and which cells touch. All of it
	## depends only on the spec (not on rotation/offset), so it is computed once per spec and mapped per build.
	if _topology.has(spec):
		return _topology[spec]
	var panels := spec.panels
	var owner_of: Dictionary = {}              # local tile -> cell index
	var queue: Array[Vector2i] = []
	for i in panels.size():
		var p: ChunkSpec.PanelDef = panels[i]
		owner_of[p.tile] = i
		queue.append(p.tile)
	# multi-source BFS: each walkable tile belongs to its nearest panel (ties -> lower index)
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		for d in ChunkSpec.DIRS_ORDER:
			if not spec.can_step(cur, d):
				continue
			var n := cur + d
			if owner_of.has(n):
				continue
			owner_of[n] = owner_of[cur]
			queue.append(n)
	# footprints: walking distance from each panel up to FOOTPRINT_RADIUS, walls block light
	var foot_tiles: Array = []
	var foot_w: Array = []
	for i in panels.size():
		var start: Vector2i = (panels[i] as ChunkSpec.PanelDef).tile
		var seen := {start: 0}
		var q: Array[Vector2i] = [start]
		var tiles: Array[Vector2i] = []
		var weights := PackedFloat32Array()
		var qh := 0
		while qh < q.size():
			var cur2: Vector2i = q[qh]
			qh += 1
			var dd: int = seen[cur2]
			tiles.append(cur2)
			weights.append(pow(maxf(0.0, 1.0 - float(dd) / float(LightCell.FOOTPRINT_RADIUS + 1)), LightCell.FOOTPRINT_FALLOFF))
			if dd >= LightCell.FOOTPRINT_RADIUS:
				continue
			for d2 in ChunkSpec.DIRS_ORDER:
				if spec.can_step(cur2, d2) and not seen.has(cur2 + d2):
					seen[cur2 + d2] = dd + 1
					q.append(cur2 + d2)
		foot_tiles.append(tiles)
		foot_w.append(weights)
	# adjacency between cells (regions touching without a thin wall between)
	var adj: Array[Vector2i] = []
	var adj_seen := {}
	for lt: Vector2i in owner_of:
		for d3 in ChunkSpec.DIRS_ORDER:
			if not spec.can_step(lt, d3):
				continue
			var n2 := lt + d3
			if not owner_of.has(n2):
				continue
			var ia: int = owner_of[lt]
			var ib: int = owner_of[n2]
			if ia != ib and not adj_seen.has(Vector2i(ia, ib)):
				adj_seen[Vector2i(ia, ib)] = true
				adj_seen[Vector2i(ib, ia)] = true
				adj.append(Vector2i(ia, ib))
	var topo := {"owner": owner_of, "foot_tiles": foot_tiles, "foot_w": foot_w, "adj": adj}
	_topology[spec] = topo
	return topo


static func _build_cells(chunk: Chunk) -> void:
	var spec := chunk.spec
	var panels := spec.panels
	if panels.is_empty():
		return
	var H := GameScale.WALL_H
	for i in panels.size():
		var p: ChunkSpec.PanelDef = panels[i]
		var c := LightCell.new()
		c.chunk = chunk
		c.index = i
		c.local_tile = p.tile
		c.tile = chunk.local_tile_to_world(p.tile)
		c.position = chunk.transform * local_center(p.tile, H - 0.05)
		c.has_tube = p.lit
		c.powered = true
		c.home_tube = p.lit
		c.home_powered = true
		c.circuit = &"" if p.circuit == &"" else StringName("%d:%s" % [chunk.beat_index, p.circuit])
		c.recompute()
		c.brightness = 1.0 if c.is_lit() else 0.0
		chunk.cells.append(c)
	var topo := _cell_topology(spec)
	var wmap: Dictionary = {}                   # local tile -> world tile, computed once per tile
	var owner_of: Dictionary = topo["owner"]
	for lt: Vector2i in owner_of:
		var wt := chunk.local_tile_to_world(lt)
		wmap[lt] = wt
		var cell: LightCell = chunk.cells[owner_of[lt]]
		cell.region.append(wt)
		chunk.tile_cell[wt] = cell
	var foot_tiles: Array = topo["foot_tiles"]
	var foot_w: Array = topo["foot_w"]
	for i in chunk.cells.size():
		var c: LightCell = chunk.cells[i]
		var tiles: Array = foot_tiles[i]
		var weights: PackedFloat32Array = foot_w[i]
		for k in tiles.size():
			var lt2: Vector2i = tiles[k]
			var wt2: Vector2i = wmap[lt2] if wmap.has(lt2) else chunk.local_tile_to_world(lt2)
			c.footprint[wt2] = weights[k]
	for pair: Vector2i in topo["adj"]:
		var a: LightCell = chunk.cells[pair.x]
		var b: LightCell = chunk.cells[pair.y]
		a.neighbors.append(b)
		b.neighbors.append(a)


static func rebuild_panels(chunk: Chunk) -> void:
	if chunk.panels == null:
		return
	var T := GameScale.TILE
	var H := GameScale.WALL_H
	var mb := MeshBuilder.new()
	var size := chunk.spec.ceiling
	for c in chunk.cells:
		var x0 := c.local_tile.x * T
		var z0 := c.local_tile.y * T
		var kind := "_light_on"
		match c.state:
			LightCell.State.FLICKER: kind = "_light_flicker"
			LightCell.State.DEAD: kind = "_light_off"
		mb.ceiling_quad(ceiling_material(size, kind), x0, z0, x0 + T, z0 + T, H)
	chunk.panels.mesh = mb.build() if not mb.is_empty() else null
