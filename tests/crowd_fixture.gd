class_name CrowdFixture
extends Node
## Test scaffolding for the people entities (Queue / Greeter / Lobby Audit): a real Stage, ChunkStreamer, one real
## authored chunk (populated by SlotPopulator), a Player and a FakeSession that offers the FloorSession surface the
## entities use. No Main, no SaveService, no screens: entities are stepped by hand (`manual`), never by the engine.

class FakeSession extends Node:
	var grid: WorldGrid = null
	var player: Player = null
	var streamer: ChunkStreamer = null
	var stage: Stage = null
	var tuning: DirectorTuning = DirectorTuning.new()
	var def: FloorDef = null
	var truth: int = RunState.Truth.HOLDS
	var plan: Variant = null
	var clauses: ClauseService = null
	var camcorder: Variant = null
	var director: Variant = null
	var hits: Array[StringName] = []
	var on_hit_cb: Callable = Callable()      ## a test hook run inside every hit (e.g. a lethal hit tearing the entity down)
	var staff_frozen_flag := false            ## a whistle froze staff

	func clause_active(clause_id: StringName) -> bool:
		return RunState.clause == clause_id and not RunState.clause_void

	func on_player_hit(_source: Object, source_name: StringName) -> void:
		hits.append(source_name)
		if on_hit_cb.is_valid():
			on_hit_cb.call()

	func staff_frozen() -> bool:
		return staff_frozen_flag

	func freeze_staff(_s: float) -> void:
		pass

	func register_pa_horn(_h: Node3D) -> void:
		pass

	func exit_position_of(chunk: Chunk) -> Vector3:
		if not chunk.entry_world.is_empty():
			return GameScale.tile_to_world(chunk.entry_world[0]["tile"])
		return GameScale.tile_to_world(chunk.world_open.keys()[0])


static var _current: CrowdFixture = null     ## only one room at a time: two would overlap in the physics world

var stage: Stage = null
var streamer: ChunkStreamer = null
var chunk: Chunk = null
var player: Player = null
var session: FakeSession = null
var beat: FloorPlan.BeatPlan = null


static func create(host: Node, floor_id: StringName, chunk_id: StringName, truth: int, beat_kind: StringName = &"exam") -> CrowdFixture:
	ChunkLibrary.reload()
	if _current != null and is_instance_valid(_current):
		_current.dispose()
	var fx := CrowdFixture.new()
	_current = fx
	host.add_child(fx)
	var def := FloorCatalog.get_def(floor_id)
	fx.stage = Stage.new()
	fx.add_child(fx.stage)
	var theme := Themes.get_theme(def.theme_id)
	fx.stage.apply_theme(theme)
	fx.streamer = ChunkStreamer.new()
	fx.stage.add_child(fx.streamer)
	fx.streamer.setup(fx.stage, null)
	var spec := ChunkLibrary.get_spec(chunk_id)
	fx.beat = FloorPlan.BeatPlan.new()
	fx.beat.kind = beat_kind
	fx.beat.main = true
	fx.beat.spec = spec
	fx.session = FakeSession.new()
	fx.session.def = def
	fx.session.truth = truth
	fx.session.stage = fx.stage
	fx.session.streamer = fx.streamer
	fx.add_child(fx.session)
	RunState.set_truth(floor_id, truth)
	fx.chunk = fx.streamer.spawn_initial(spec, 0, 0, Vector2i.ZERO, {"bp": fx.beat, "decay": 0})
	fx.streamer.current = fx.chunk
	SlotPopulator.populate(fx.chunk, fx.beat, fx.session, false)
	fx.session.grid = WorldGrid.new(fx.streamer)
	fx.player = Player.new()
	fx.stage.actors_root.add_child(fx.player)
	fx.player.frozen = true
	fx.session.player = fx.player
	fx.streamer.player = fx.player
	fx.session.clauses = ClauseService.new()
	fx.session.add_child(fx.session.clauses)
	fx.session.clauses.setup(fx.session)
	var entry: Vector2i = fx.chunk.entry_world[0]["tile"] if not fx.chunk.entry_world.is_empty() else fx.chunk.world_open.keys()[0]
	fx.put_player(GameScale.tile_to_world(entry), 0.0)
	return fx


func put_player(pos: Vector3, yaw: float = 0.0) -> void:
	player.teleport(pos, yaw)
	player.nerve.invuln = 0.0


func face(target: Vector3) -> void:
	var d := target - player.global_position
	player.rotation.y = atan2(-d.x, -d.z)


func add_entity(e: EntityBase) -> EntityBase:
	e.setup(session, session.truth)
	stage.actors_root.add_child(e)
	return e


func anchors() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for a: Node3D in chunk.slot_nodes.get(&"anchor", []):
		out.append(a)
	return out


func dispose() -> void:
	RunState.clause = &""
	RunState.clause_void = false
	RunState.set_nerve(RunState.nerve_max)
	if _current == self:
		_current = null
	if is_instance_valid(self) and get_parent() != null:
		get_parent().remove_child(self)
		queue_free()
