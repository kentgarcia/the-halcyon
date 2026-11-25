extends TestCase
## Seed soak (SPEC 15): generate many floors for every floor def and both truths; every plan must validate
## (Doctrine 3 evidence budget, rooms that fit the beat, no missing sockets) and every door must resolve.

const DEFAULT_SEEDS := 60


func _seeds() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--soak="):
			return int(a.substr(7))
	return DEFAULT_SEEDS


func test_plans_validate_for_every_floor_seed_and_truth() -> void:
	ChunkLibrary.reload()
	var n := _seeds()
	for fid in FloorCatalog.ORDER:
		var def := FloorCatalog.get_def(fid)
		for truth in [RunState.Truth.HOLDS, RunState.Truth.INVERTED]:
			for s in n:
				var streams := RngStreams.new(RngStreams.mix(s + 1, fid.hash()))
				var plan := FloorPlan.create(def, truth, streams, {"mastered": s % 5 == 0})
				var errs := plan.validate()
				for e in errs:
					assert_true(false, "%s seed %d truth %d: %s" % [fid, s, truth, e])
				if errs.size() > 0:
					return        # first failing seed is enough to debug


func test_every_door_resolves() -> void:
	ChunkLibrary.reload()
	for fid in FloorCatalog.ORDER:
		var def := FloorCatalog.get_def(fid)
		for s in 20:
			var plan := FloorPlan.create(def, s % 2, RngStreams.new(RngStreams.mix(s + 7, fid.hash())))
			for bp in plan.main_beats.duplicate():
				var chunk := Chunk.new()
				chunk.beat_index = bp.index
				for sock in bp.spec.exits:
					var info := plan.door_type_for(chunk, sock)
					assert_true(DoorTypes.has_type(StringName(info.get("type", &""))), "%s: bad door type %s" % [fid, info])
					var dest := int(info.get("dest", -1))
					assert_true(dest >= 0 and plan.beat_by_index(dest) != null and plan.beat_by_index(dest).spec != null,
						"%s seed %d: exit %d of %s leads nowhere" % [fid, s, sock.index, bp.label()])
				chunk.free()


func test_forward_path_needs_no_item() -> void:
	## The forward doors must open without a pocket item: boarded/sealed doors are only ever shortcuts.
	ChunkLibrary.reload()
	for fid in FloorCatalog.ORDER:
		var def := FloorCatalog.get_def(fid)
		for s in 20:
			var plan := FloorPlan.create(def, s % 2, RngStreams.new(RngStreams.mix(s + 99, fid.hash())))
			for bp in plan.main_beats:
				if bp.forward_exit < 0:
					continue
				var chunk := Chunk.new()
				chunk.beat_index = bp.index
				var sock: ChunkSpec.SocketDef = bp.spec.exits[bp.forward_exit]
				var info := plan.door_type_for(chunk, sock)
				var t := StringName(info["type"])
				assert_true(not DoorTypes.get_def(t).has("needs"), "%s: forward door of %s needs an item (%s)" % [fid, bp.label(), t])
				chunk.free()


func test_main_line_never_overlaps_itself() -> void:
	## Independent re-simulation of the committed layout: place every main room exactly as the streamer will
	## (through the planned forward exit and entry socket) and require that no tile is used twice. This is what
	## stops a long hall being walked back into by a later room (the forward door would never build).
	ChunkLibrary.reload()
	var n := mini(_seeds(), 40)
	for fid in FloorCatalog.ORDER:
		var def := FloorCatalog.get_def(fid)
		for truth in [RunState.Truth.HOLDS, RunState.Truth.INVERTED]:
			for s in n:
				var plan := FloorPlan.create(def, truth, RngStreams.new(RngStreams.mix(s + 31, fid.hash())))
				var label := "%s seed %d truth %d" % [fid, s, truth]
				var occ := {}
				var rot := 0
				var offset := Vector2i.ZERO
				for i in plan.main_beats.size():
					var bp: FloorPlan.BeatPlan = plan.main_beats[i]
					if i > 0:
						var pb: FloorPlan.BeatPlan = plan.main_beats[i - 1]
						assert_true(pb.forward_exit >= 0 and pb.forward_exit < pb.spec.exits.size(), "%s: forward exit of %s valid" % [label, pb.label()])
						assert_true(bp.entry_socket >= 100 and bp.entry_socket - 100 < bp.spec.entries.size(), "%s: planned entry of %s valid" % [label, bp.label()])
						if pb.forward_exit < 0 or bp.entry_socket < 100:
							return
						var se: ChunkSpec.SocketDef = pb.spec.exits[pb.forward_exit]
						var door_tile := ChunkPlacer.tile_to_world(se.tile, rot, offset)
						var wdir := Dir.rot(se.dir, rot)
						var pl := ChunkPlacer.placement_for_socket(bp.spec.entries[bp.entry_socket - 100], door_tile + wdir, -wdir)
						rot = int(pl["rot"])
						offset = pl["offset"]
					for t in ChunkPlacer.world_tiles(bp.spec, rot, offset):
						assert_false(occ.has(t), "%s: %s overlaps an earlier main room at %s" % [label, bp.label(), t])
						if occ.has(t):
							return
						occ[t] = true


func test_evidence_density_keeps_floors_valid_and_scales_copies() -> void:
	## The setting must never break the Fairness budget (Sparse) and must add TRUE copies only (Generous/Plentiful).
	ChunkLibrary.reload()
	var saved := Settings.evidence_density
	for fid in FloorCatalog.ORDER:
		var def := FloorCatalog.get_def(fid)
		for s in 12:
			var counts := {}
			for d in [0.75, 1.0, 1.5, 2.0]:
				Settings.evidence_density = d
				var plan := FloorPlan.create(def, s % 2, RngStreams.new(RngStreams.mix(s + 55, fid.hash())))
				for e in plan.validate():
					assert_true(false, "%s seed %d density %.2f: %s" % [fid, s, d, e])
				var total := 0
				for bp in plan.main_beats:
					total += bp.evidence.size()
					for ev: EvidenceDef in bp.evidence:
						assert_eq(ev.variant, plan.truth, "%s: only evidence true for this run is ever placed" % fid)
				counts[d] = total
			assert_true(counts[2.0] >= counts[1.0], "%s seed %d: Plentiful never has less evidence than Standard" % [fid, s])
			assert_true(counts[0.75] <= counts[1.0], "%s seed %d: Sparse never has more evidence than Standard" % [fid, s])
	Settings.evidence_density = saved
