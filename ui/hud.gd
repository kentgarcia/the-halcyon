class_name Hud
extends Control
## In-world HUD (SPEC 11.1): nearly nothing. A dot, a context prompt, a pocket line, toasts and
## subtitles. Nerve shows as a vignette, never a bar. Camcorder chrome lives in Viewfinder.

const VIGNETTE: Shader = preload("res://shaders/ui_vignette.gdshader")
const SLATS: Shader = preload("res://shaders/hide_slats.gdshader")

var player: Player = null
var _dot: Control
var _prompt: Label
var _toast: Label
var _toast_t := 0.0
var _subtitle: Label
var _subtitle_t := 0.0
var _pocket: Label
var _ring: Control
var _vignette: ColorRect
var _vig_mat: ShaderMaterial
var _slats: ColorRect
var _slats_mat: ShaderMaterial
var _hit_flash: ColorRect
var _heart_t := 0.0
var _toast_queue: Array[String] = []
var _focus_ok := false
var _radar: SoundRadar


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UIKit.theme()

	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vig_mat = ShaderMaterial.new()
	_vig_mat.shader = VIGNETTE
	_vignette.material = _vig_mat
	add_child(_vignette)

	_slats = ColorRect.new()
	_slats.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slats_mat = ShaderMaterial.new()
	_slats_mat.shader = SLATS
	_slats.material = _slats_mat
	_slats.visible = false
	add_child(_slats)

	_hit_flash = ColorRect.new()
	_hit_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hit_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hit_flash.color = Color(0.6, 0.0, 0.0, 0.0)
	add_child(_hit_flash)

	_radar = SoundRadar.new()
	_radar.name = "SoundRadar"
	_radar.player = player
	add_child(_radar)

	_dot = Control.new()
	_dot.set_anchors_preset(Control.PRESET_CENTER)
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.draw.connect(_draw_dot)
	add_child(_dot)
	_ring = _dot

	_prompt = UIKit.label("", 20, UIKit.INK)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 0.62
	_prompt.anchor_bottom = 0.62
	_prompt.offset_left = -300
	_prompt.offset_right = 300
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_prompt)

	_toast = UIKit.label("", 22, UIKit.ACCENT, true)
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.anchor_top = 0.14
	_toast.anchor_bottom = 0.14
	_toast.offset_left = -420
	_toast.offset_right = 420
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.modulate.a = 0.0
	add_child(_toast)

	_subtitle = UIKit.label("", 22, UIKit.INK)
	_subtitle.anchor_left = 0.5
	_subtitle.anchor_right = 0.5
	_subtitle.anchor_top = 0.86
	_subtitle.anchor_bottom = 0.86
	_subtitle.offset_left = -480
	_subtitle.offset_right = 480
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.add_theme_stylebox_override("normal", UIKit.shadow_box())
	_subtitle.visible = false
	add_child(_subtitle)

	_pocket = UIKit.label("", 16, UIKit.INK_DIM)
	_pocket.anchor_left = 0.0
	_pocket.anchor_top = 1.0
	_pocket.anchor_bottom = 1.0
	_pocket.offset_left = 24
	_pocket.offset_top = -48
	_pocket.offset_bottom = -20
	add_child(_pocket)

	EventBus.prompt_changed.connect(_on_prompt)
	EventBus.toast.connect(_on_toast)
	EventBus.subtitle.connect(_on_subtitle)
	EventBus.pocket_changed.connect(_on_pocket)
	EventBus.hide_changed.connect(_on_hide)
	EventBus.nerve_changed.connect(_on_nerve)
	EventBus.player_hit.connect(_on_hit)
	_on_pocket(RunState.pocket)
	_on_nerve(RunState.nerve)


func _exit_tree() -> void:
	for pair in [[EventBus.prompt_changed, _on_prompt], [EventBus.toast, _on_toast], [EventBus.subtitle, _on_subtitle],
			[EventBus.pocket_changed, _on_pocket], [EventBus.hide_changed, _on_hide], [EventBus.nerve_changed, _on_nerve],
			[EventBus.player_hit, _on_hit]]:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])


func _process(delta: float) -> void:
	if _radar != null and _radar.player != player:
		_radar.player = player
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / 0.6, 0.0, 1.0) if _toast_t < 0.6 else minf(1.0, (3.2 - _toast_t) / 0.15 + 0.0)
		if _toast_t <= 0.0:
			_toast.modulate.a = 0.0
			if not _toast_queue.is_empty():
				_show_toast(_toast_queue.pop_front())
	if _subtitle_t > 0.0:
		_subtitle_t -= delta
		if _subtitle_t <= 0.0:
			_subtitle.visible = false
	if _hit_flash.color.a > 0.0:
		_hit_flash.color.a = maxf(0.0, _hit_flash.color.a - delta * 1.4)
	# nerve vignette + heartbeat pulse
	var missing := 1.0 - float(RunState.nerve) / float(maxi(1, RunState.nerve_max))
	var dread := DreadDirector.normalized()
	var pulse := 0.0
	if not Settings.reduce_motion:
		_heart_t += delta * (1.0 + missing * 1.6 + dread * 0.8)
		pulse = (0.5 + 0.5 * sin(_heart_t * TAU * 0.9)) * (missing * 0.8 + dread * 0.25)
	_vig_mat.set_shader_parameter("strength", clampf(missing * 0.9 + dread * 0.18, 0.0, 1.0))
	_vig_mat.set_shader_parameter("pulse", pulse)
	if player != null:
		var p := player.interact_progress
		if p > 0.0 or _focus_ok:
			_dot.queue_redraw()
	if _ring != null and player != null and player.interact_progress > 0.0:
		_ring.queue_redraw()


func _draw_dot() -> void:
	var c := UIKit.INK if not _focus_ok else UIKit.ACCENT
	var r := 2.5 if not _focus_ok else 4.0
	_dot.draw_circle(Vector2.ZERO, r + 1.5, Color(0, 0, 0, 0.55))
	_dot.draw_circle(Vector2.ZERO, r, c)
	if player != null and player.interact_progress > 0.0:
		_dot.draw_arc(Vector2.ZERO, 16.0, -PI * 0.5, -PI * 0.5 + TAU * player.interact_progress, 40, UIKit.ACCENT, 3.0)


func _on_prompt(text: String) -> void:
	_focus_ok = text != ""
	if text == "":
		_prompt.text = ""
	else:
		_prompt.text = "[%s]  %s" % [UIKit.key_label(&"interact"), text]
	_dot.queue_redraw()


func _on_toast(text: String) -> void:
	if _toast_t > 0.0 and _toast.text != text:
		if _toast_queue.size() < 3:
			_toast_queue.append(text)
		return
	_show_toast(text)


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast_t = 3.2 + float(text.length()) * 0.02
	_toast.modulate.a = 1.0


func _on_subtitle(text: String, duration: float) -> void:
	if not Settings.subtitles:
		return
	_subtitle.text = " %s " % text
	_subtitle.visible = text != ""
	_subtitle_t = maxf(0.5, duration)


func _on_pocket(item: StringName) -> void:
	_pocket.text = "" if item == &"" else "Pocket: %s" % Items.display_name(item)


func _on_hide(hiding: bool) -> void:
	var closet := player != null and player.hide_spot != null and (player.hide_spot as HideSpot).kind == &"closet"
	_slats.visible = hiding and closet
	_slats_mat.set_shader_parameter("amount", 1.0 if hiding else 0.0)
	if hiding:
		EventBus.toast.emit("Hidden. [%s] to come out." % UIKit.key_label(&"interact"))


func _on_nerve(_n: int) -> void:
	pass


func _on_hit(_source: StringName, _amount: int) -> void:
	_hit_flash.color.a = 0.55
