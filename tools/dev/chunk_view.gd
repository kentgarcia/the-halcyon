class_name ChunkViewScene
extends Node
## Dev scene: build one or more authored chunks (res://content/chunks/**) with the real builder and
## populator and look at them from above or at eye level. For authoring and screenshots.
##   --scene=chunkview --chunk=id1,id2 [--theme=yellow] [--view=top|eye] [--eye=x,z,yawdeg] [--truth=0|1]

var stage: Stage
var cam: Camera3D


func _ready() -> void:
	var args := DevHarness.parse_args(OS.get_cmdline_user_args())
	var theme_id := StringName(args.get("theme", "yellow"))
	var theme := Themes.get_theme(theme_id)
	stage = Game.make_stage()
	stage.apply_theme(theme)
	var ids := String(args.get("chunk", "dev_greybox_hall")).split(",")
	var x_off := 0
	var focus := Vector2i.ZERO
	var min_t := Vector2i(1 << 20, 1 << 20)
	var max_t := Vector2i(-(1 << 20), -(1 << 20))
	var uid := 1
	for id in ids:
		var spec: ChunkSpec = ChunkLibrary.get_spec(StringName(id))
		if spec == null and FileAccess.file_exists(id):
			spec = ChunkSpec.load_file(id)
		if spec == null:
			spec = ChunkSpec.load_file("res://content/chunks/dev/%s.chunk" % id)
		if spec == null or spec.errors.size() > 0:
			push_error("chunkview: cannot use %s: %s" % [id, spec.errors if spec != null else "not found"])
			continue
		var chunk := ChunkBuilder.build(spec, theme, 0, Vector2i(x_off, 0), uid, 1, {})
		stage.add_chunk(chunk)
		SlotPopulator.populate(chunk, null, null)
		for t in chunk.world_open:
			min_t = Vector2i(mini(min_t.x, t.x), mini(min_t.y, t.y))
			max_t = Vector2i(maxi(max_t.x, t.x), maxi(max_t.y, t.y))
		x_off += spec.width + 3
		uid += 1
	focus = (min_t + max_t) / 2
	stage.light_field.set_focus(focus)
	cam = Camera3D.new()
	stage.actors_root.add_child(cam)
	cam.current = true
	var view := String(args.get("view", "top"))
	var cx := (min_t.x + max_t.x + 1) * 0.5 * GameScale.TILE
	var cz := (min_t.y + max_t.y + 1) * 0.5 * GameScale.TILE
	if view == "eye":
		var parts := String(args.get("eye", "%f,%f,0" % [cx, cz])).split(",")
		cam.position = Vector3(float(parts[0]) * GameScale.TILE, 1.55, float(parts[1]) * GameScale.TILE)
		cam.rotation.y = deg_to_rad(float(parts[2]))
		cam.fov = 75.0
	else:
		var w := float(max_t.x - min_t.x + 3) * GameScale.TILE
		var h := float(max_t.y - min_t.y + 3) * GameScale.TILE
		var dist := maxf(w / (2.0 * tan(deg_to_rad(30.0)) * 1.7), h / (2.0 * tan(deg_to_rad(30.0)))) + 3.0
		cam.fov = 60.0
		cam.position = Vector3(cx, dist, cz + 0.001)
		cam.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		cam.far = 400.0
	stage.environment.fog_enabled = view != "top"
	MaterialLibrary.set_ambient(maxf(theme.ambient_floor, 0.55) if view == "top" else theme.ambient_floor, theme.light_gain)
