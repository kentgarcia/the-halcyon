class_name GreyboxScene
extends Node
## M0 exit-criterion scene: a textured hallway at 640x360 with fog, light cells and the tape finish.
## Built from a real ChunkSpec through ChunkBuilder, so it exercises the same path the game uses.

var stage: Stage
var cam: Camera3D


func _ready() -> void:
	stage = Game.make_stage()
	var theme := Themes.get_theme(&"yellow")
	stage.apply_theme(theme)
	var spec := ChunkSpec.load_file("res://content/chunks/dev/greybox_hall.chunk")
	if not spec.is_valid():
		for e in spec.errors:
			push_error("greybox spec: %s" % e)
	var t0 := Time.get_ticks_usec()
	var chunk := ChunkBuilder.build(spec, theme, 0, Vector2i(0, 0), 1, 0)
	var t1 := Time.get_ticks_usec()
	stage.add_chunk(chunk)
	var amb := float(DevHarness.parse_args(OS.get_cmdline_user_args()).get("ambient", "-1"))
	if amb >= 0.0:
		MaterialLibrary.set_ambient(amb, 0.0)
	var dbg := String(DevHarness.parse_args(OS.get_cmdline_user_args()).get("debugmat", ""))
	if dbg == "std":
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.8, 0.7, 0.2)
		chunk.geometry.material_override = m
	elif dbg == "std2":
		var m2 := StandardMaterial3D.new()
		m2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m2.cull_mode = BaseMaterial3D.CULL_DISABLED
		m2.albedo_color = Color(0.8, 0.7, 0.2)
		chunk.geometry.material_override = m2
	print("GreyboxScene: built '%s' in %.2f ms, %d open tiles, %d light cells" % [spec.id, (t1 - t0) / 1000.0, spec.open.size(), chunk.cells.size()])
	cam = Camera3D.new()
	cam.fov = Settings.fov
	cam.current = true
	cam.position = Vector3(2.5 * GameScale.TILE, GameScale.EYE_HEIGHT, 5.5 * GameScale.TILE)
	stage.add_child(cam)
	cam.look_at(cam.position + Vector3(1.0, -0.04, 0.0), Vector3.UP)
	stage.light_field.set_focus(GameScale.world_to_tile(cam.position))
