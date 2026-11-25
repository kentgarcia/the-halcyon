class_name Main
extends Control
## Render root (SPEC 9.2): the 3D world renders into a small SubViewport that is shown by a
## TextureRect with the tape finish shader; UI lives on CanvasLayers at native resolution.
##
##   Main
##    |- GameViewport (SubViewport, low-res, own World3D)   <- Stage, Player, entities
##    |- Screen (TextureRect + tape_finish.gdshader)
##    |- UI (CanvasLayer)                                    <- HUD, card, notebook, menus
##    '- TapeViewport (SubViewport 128x96, shares the world) <- camcorder tape capture

static var instance: Main = null

const TAPE_FINISH: Shader = preload("res://shaders/tape_finish.gdshader")

var game_viewport: SubViewport
var screen: TextureRect
var ui: CanvasLayer
var overlay: CanvasLayer              ## above the UI: fades, blackout, subtitles
var finish: ShaderMaterial
var tape_viewport: SubViewport
var _fade := 1.0
var _fade_color := Color.BLACK


func _ready() -> void:
	instance = self
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_render()
	get_viewport().size_changed.connect(_update_render_size)
	Settings.changed.connect(_on_setting_changed)
	_update_render_size()
	Game.attach_main(self)
	if DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().size() > 0:
		print("Main: display=%s adapter=%s renderer=%s" % [DisplayServer.get_name(), RenderingServer.get_video_adapter_name(),
			RenderingServer.get_current_rendering_method()])


func _build_render() -> void:
	game_viewport = SubViewport.new()
	game_viewport.name = "GameViewport"
	game_viewport.own_world_3d = true
	game_viewport.msaa_3d = Viewport.MSAA_DISABLED
	game_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	game_viewport.audio_listener_enable_3d = true
	game_viewport.handle_input_locally = true
	game_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	game_viewport.size = Vector2i(640, 360)
	add_child(game_viewport)

	screen = TextureRect.new()
	screen.name = "Screen"
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.stretch_mode = TextureRect.STRETCH_SCALE
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.texture = game_viewport.get_texture()
	finish = ShaderMaterial.new()
	finish.shader = TAPE_FINISH
	screen.material = finish
	add_child(screen)

	ui = CanvasLayer.new()
	ui.name = "UI"
	ui.layer = 10
	add_child(ui)
	overlay = CanvasLayer.new()
	overlay.name = "Overlay"
	overlay.layer = 20
	add_child(overlay)

	tape_viewport = SubViewport.new()
	tape_viewport.name = "TapeViewport"
	tape_viewport.size = Vector2i(128, 96)
	tape_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tape_viewport.msaa_3d = Viewport.MSAA_DISABLED
	# find_world_3d(), not world_3d: with own_world_3d the `world_3d` property is null (it only holds an explicitly
	# assigned world), which left the tape viewport rendering the window's empty default world (all-black tapes).
	tape_viewport.world_3d = game_viewport.find_world_3d()
	add_child(tape_viewport)
	_apply_settings()


func _update_render_size() -> void:
	var win := get_viewport().get_visible_rect().size
	if win.x < 2.0 or win.y < 2.0:
		win = Vector2(1280, 720)
	var h := Settings.render_height
	if h <= 0:
		h = int(win.y)
	var w := int(round(float(h) * win.x / win.y))
	w = clampi(w, 160, 3840)
	h = clampi(h, 120, 2160)
	if game_viewport.size != Vector2i(w, h):
		game_viewport.size = Vector2i(w, h)
	finish.set_shader_parameter("src_size", Vector2(w, h))


func _on_setting_changed(_key: StringName) -> void:
	_apply_settings()
	_update_render_size()


func _apply_settings() -> void:
	finish.set_shader_parameter("intensity", Settings.retro_intensity)
	finish.set_shader_parameter("safe_mode", 1.0 if Settings.safe_flicker else 0.0)
	finish.set_shader_parameter("reduce_motion", 1.0 if Settings.reduce_motion else 0.0)
	MaterialLibrary.set_vertex_snap(Settings.vertex_snap)


func _input(event: InputEvent) -> void:
	# Nodes inside the SubViewport (PlayerInput) only see events we forward to it.
	if game_viewport != null:
		game_viewport.push_input(event)


# --- presentation controls (used by Game, Player, Director) ---------------------------------

func set_dread_visual(d: float) -> void:
	finish.set_shader_parameter("dread", clampf(d, 0.0, 1.0))


func set_cam_mix(v: float) -> void:
	finish.set_shader_parameter("cam_mix", clampf(v, 0.0, 1.0))


func set_glitch(v: float) -> void:
	finish.set_shader_parameter("glitch_amount", clampf(v, 0.0, 1.0))


func set_desaturate(v: float) -> void:
	finish.set_shader_parameter("desaturate", clampf(v, 0.0, 1.0))


func set_fade(v: float, color: Color = Color.BLACK) -> void:
	## v = how far the screen is faded out (0 clear, 1 fully `color`), which is how every caller uses it. The finish
	## shader's own `fade` uniform runs the other way (1 = clear), so it gets the complement.
	_fade = clampf(v, 0.0, 1.0)
	_fade_color = color
	finish.set_shader_parameter("fade", 1.0 - _fade)
	finish.set_shader_parameter("fade_color", color)


func get_fade() -> float:
	return _fade


func fade_to(target: float, seconds: float, color: Color = Color.BLACK) -> Tween:
	_fade_color = color
	finish.set_shader_parameter("fade_color", color)
	var tw := create_tween()
	tw.tween_method(func(v: float): set_fade(v, color), _fade, target, maxf(0.01, seconds))
	return tw


func world_root() -> SubViewport:
	return game_viewport


## Playback / Echo tapes / Autopsy: the screen shows tape footage (4:3, nearest) through the same finish.
func show_footage(tex: Texture2D) -> void:
	screen.texture = tex
	screen.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	finish.set_shader_parameter("src_size", Vector2(TapeBuffer.W, TapeBuffer.H))


func hide_footage() -> void:
	screen.texture = game_viewport.get_texture()
	screen.stretch_mode = TextureRect.STRETCH_SCALE
	_update_render_size()


func showing_footage() -> bool:
	return screen.texture != game_viewport.get_texture()
