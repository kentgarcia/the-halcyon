extends TestCase
## Tile math, socket alignment, chunk parsing, light-cell regions.

const ROOM := "id: t_room\nbeat: choice\nceiling: medium\n---\n#######\n#.L...#\n#.....>\n3..L..#\n#..S..#\n#######\n"
const LSHAPE := "id: t_l\n---\n######\n#....#\n#.##.#\n#.#4.#\n#.####\n#v####\n######\n"


func _spec(text: String) -> ChunkSpec:
	return ChunkSpec.parse_text(text)


func test_parse_room() -> void:
	var s := _spec(ROOM)
	assert_true(s.is_valid(), "room parses: %s" % str(s.errors))
	assert_eq(s.exits.size(), 1, "one exit")
	assert_eq(s.entries.size(), 1, "one entry")
	assert_eq(s.exits[0].dir, Vector2i(1, 0), "exit faces east")
	assert_eq(s.entries[0].dir, Vector2i(0, 1), "entry faces south")
	assert_eq(s.panels.size(), 3, "three panels")
	var circuits := 0
	for p in s.panels:
		if p.circuit == &"S":
			circuits += 1
	assert_eq(circuits, 1, "one switchable panel")


func test_parse_errors_reported() -> void:
	var bad := _spec("id: bad\n---\n#####\n#.?.#\n#####\n")
	assert_false(bad.is_valid(), "unknown glyph rejected")
	var disconnected := _spec("id: bad2\n---\n#####\n#.#.#\n#####\n")
	assert_false(disconnected.is_valid(), "disconnected open tiles rejected")
	var nowall := _spec("id: bad3\n---\n#####\n#.g.#\n#####\n")
	assert_true(nowall.is_valid(), "wall slot with a wall is fine")


func test_thin_wall_splits_connectivity() -> void:
	var s := _spec("id: thin\n---\n#####\n#.|.#\n#####\n")
	assert_false(s.is_valid(), "a full thin partition disconnects the room")
	var s2 := _spec("id: thin2\n---\n#####\n#.|.#\n#...#\n#####\n")
	assert_true(s2.is_valid(), "partition with a gap is connected: %s" % str(s2.errors))
	assert_true(s2.has_thin_wall(Vector2i(2, 1), Vector2i(1, 0)), "thin wall east of the | tile")
	assert_true(s2.has_thin_wall(Vector2i(3, 1), Vector2i(-1, 0)), "...and recorded from the other side")


func test_chunk_tile_math_all_rotations() -> void:
	var spec := _spec(ROOM)
	for rot in 4:
		for off in [Vector2i(0, 0), Vector2i(7, -3), Vector2i(-12, 20)]:
			var chunk := ChunkBuilder.build(spec, Themes.get_theme(&"yellow"), rot, off, 1)
			for t: Vector2i in spec.open:
				var w := chunk.local_tile_to_world(t)
				assert_eq(w, ChunkPlacer.tile_to_world(t, rot, off), "chunk and placer agree")
				assert_eq(chunk.world_tile_to_local(w), t, "round trip rot=%d" % rot)
				var local_c := Vector3((t.x + 0.5) * GameScale.TILE, 0.0, (t.y + 0.5) * GameScale.TILE)
				var world_c := chunk.transform * local_c
				var expect := GameScale.tile_to_world(w)
				assert_near(world_c.x, expect.x, 0.001, "transform x rot=%d" % rot)
				assert_near(world_c.z, expect.z, 0.001, "transform z rot=%d" % rot)
			chunk.free()


func test_socket_alignment_every_direction() -> void:
	var spec := _spec(ROOM)
	var door_tile := Vector2i(10, 10)
	for d in Dir.ALL:
		for sock in spec.exits + spec.entries:
			var target_tile: Vector2i = door_tile + d
			var pl := ChunkPlacer.placement_for_socket(sock, target_tile, -d)
			var chunk := ChunkBuilder.build(spec, Themes.get_theme(&"yellow"), pl["rot"], pl["offset"], 2)
			assert_eq(chunk.local_tile_to_world(sock.tile), target_tile, "socket tile lands beyond the door")
			assert_eq(chunk.local_dir_to_world(sock.dir), -d, "socket faces the door")
			chunk.free()


func test_light_cell_regions_partition_open_tiles() -> void:
	var spec := _spec(ROOM)
	var chunk := ChunkBuilder.build(spec, Themes.get_theme(&"yellow"), 1, Vector2i(3, 4), 3)
	var owned := {}
	for c in chunk.cells:
		for t in c.region:
			assert_false(owned.has(t), "tile owned once")
			owned[t] = c
			assert_true(chunk.world_open.has(t), "region tile is open")
	assert_eq(owned.size(), chunk.world_open.size(), "every open tile belongs to a cell")
	for c in chunk.cells:
		assert_true(c.region.has(c.tile), "cell owns its own panel tile")
		assert_gt(c.footprint.size(), 3.0, "footprint has tiles")
	chunk.free()


func test_light_cell_state_machine() -> void:
	var spec := _spec(ROOM)
	var chunk := ChunkBuilder.build(spec, Themes.get_theme(&"yellow"), 0, Vector2i.ZERO, 4)
	var c: LightCell = chunk.cells[0]
	assert_eq(c.state, LightCell.State.ON, "starts on")
	c.set_tube(false)
	assert_eq(c.state, LightCell.State.DEAD, "no tube = dead")
	c.set_tube(true)
	c.set_powered(false)
	assert_eq(c.state, LightCell.State.DEAD, "no power = dead")
	c.set_powered(true)
	c.set_base_flicker(true)
	assert_eq(c.state, LightCell.State.FLICKER, "flicker flag")
	c.set_base_flicker(false)
	c.tidy()
	assert_eq(c.state, LightCell.State.ON, "tidy restores home state")
	chunk.free()


func test_walls_skip_sockets_and_count_edges() -> void:
	var spec := _spec("id: tiny\n---\n####\n#.^#\n####\n")
	var chunk := ChunkBuilder.build(spec, Themes.get_theme(&"yellow"), 0, Vector2i.ZERO, 5)
	# 2 open tiles, perimeter = 6 edges, minus the socket edge = 5 wall quads (+ 2 floor + 2 ceiling)
	var quads := 0
	for s in range(chunk.geometry.mesh.get_surface_count()):
		var arr: Array = chunk.geometry.mesh.surface_get_arrays(s)
		quads += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 6
	assert_eq(quads, 5 + 2 + 2 - 0, "wall, floor and ceiling quads")
	chunk.free()
