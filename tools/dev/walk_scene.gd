class_name WalkScene
extends Node
## Dev scene: a player, doors and the chunk streamer, fed by a trivial random provider.
## Used by bots and screenshots to exercise movement/doors/streaming end to end.

var stage: Stage
var streamer: ChunkStreamer
var player: Player
var provider: DevProvider
var first_chunk: Chunk


func _ready() -> void:
	stage = Game.make_stage()
	var theme := Themes.get_theme(&"yellow")
	stage.apply_theme(theme)
	provider = DevProvider.new()
	provider.theme = theme
	streamer = ChunkStreamer.new()
	streamer.name = "Streamer"
	stage.add_child(streamer)
	streamer.setup(stage, provider)

	var spec := ChunkSpec.load_file("res://content/chunks/dev/greybox_hall.chunk")
	first_chunk = streamer.spawn_initial(spec, 0, 0, Vector2i(0, 0))
	player = Player.new()
	stage.actors_root.add_child(player)
	player.teleport(GameScale.tile_to_world(Vector2i(3, 5)), -PI * 0.5)
	streamer.player = player
	player.surface = theme.surface
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if DisplayServer.get_name() != "headless" else Input.MOUSE_MODE_VISIBLE


class DevProvider extends RefCounted:
	var theme: FloorTheme
	var pool: Array[ChunkSpec] = []
	var n := 0

	func _init() -> void:
		for f in ["dev_corridor", "dev_closet", "dev_office"]:
			pool.append(ChunkSpec.load_file("res://content/chunks/dev/%s.chunk" % f))

	func theme_for(_beat: int) -> FloorTheme:
		return theme

	func door_type_for(_chunk: Chunk, s: ChunkSpec.SocketDef) -> Dictionary:
		if s.kind == &"entry":
			return {"type": &"stuck"}
		var types := [&"unit", &"quiet", &"fire", &"management"]
		n += 1
		return {"type": types[n % types.size()]}

	func resolve(_conn: DoorConnection, _near: Dictionary, _far: Dictionary) -> Dictionary:
		var spec: ChunkSpec = pool[n % pool.size()]
		n += 1
		return {"spec": spec, "beat": n, "socket": 100, "plan": {}}
