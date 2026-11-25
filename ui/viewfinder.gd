class_name Viewfinder
extends Control
## Camcorder chrome (SPEC 3.2.1, 9.4): corner brackets, REC dot, timecode, battery, lamp, playback bar.
## Drawn only while the camcorder is raised or in playback; native resolution so it stays crisp.

var camcorder: Camcorder = null
var _t := 0.0
var _hint_shown := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UIKit.theme()
	visible = false
	EventBus.camcorder_state_changed.connect(_on_state)


func _exit_tree() -> void:
	if EventBus.camcorder_state_changed.is_connected(_on_state):
		EventBus.camcorder_state_changed.disconnect(_on_state)


func _on_state(state: int) -> void:
	visible = state == Camcorder.State.RAISED or state == Camcorder.State.PLAYBACK
	if state == Camcorder.State.RAISED and not _hint_shown.has(&"raised") and RunState.freeze_frames_left > 0:
		_hint_shown[&"raised"] = true
		EventBus.toast.emit("[%s] playback   [%s] freeze frame   [%s] lamp   hold [%s] stakeout" % [
			UIKit.key_label(&"playback"), UIKit.key_label(&"freeze_frame"), UIKit.key_label(&"lamp"), UIKit.key_label(&"stakeout")])
	queue_redraw()


func _process(delta: float) -> void:
	if visible:
		_t += delta
		queue_redraw()


func _draw() -> void:
	if camcorder == null or not visible:
		return
	var sz := size
	var m := 36.0
	var c := UIKit.INK
	var thick := 2.0
	var l := 38.0
	# corner brackets
	for corner in [Vector2(m, m), Vector2(sz.x - m, m), Vector2(m, sz.y - m), Vector2(sz.x - m, sz.y - m)]:
		var sx := 1.0 if corner.x < sz.x * 0.5 else -1.0
		var sy := 1.0 if corner.y < sz.y * 0.5 else -1.0
		draw_line(corner, corner + Vector2(l * sx, 0), c, thick)
		draw_line(corner, corner + Vector2(0, l * sy), c, thick)
	var font := UIKit.font_bold()
	var playback := camcorder.state == Camcorder.State.PLAYBACK
	# REC / PLAY
	if playback:
		draw_string(font, Vector2(m + 8, m + 36), "▶ PLAY" if camcorder.pb_playing else "❚❚ PAUSE", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, c)
		if camcorder.echo_label != "":
			draw_string(font, Vector2(m + 8, m + 66), camcorder.echo_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIKit.INK_DIM)
	else:
		if fmod(_t, 1.2) < 0.7:
			draw_circle(Vector2(m + 18, m + 28), 8.0, UIKit.REC_RED)
		draw_string(font, Vector2(m + 36, m + 36), "REC", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, c)
	# timecode
	var secs := int(RunState.floor_clock) if not playback else int(camcorder.playback_time())
	var tc := "%02d:%02d" % [secs / 60, secs % 60]
	draw_string(font, Vector2(sz.x - m - 120, m + 36), tc, HORIZONTAL_ALIGNMENT_RIGHT, 110, 24, c)
	# battery
	var bx := sz.x - m - 120.0
	var by := sz.y - m - 30.0
	var frac := clampf(RunState.battery / 100.0, 0.0, 1.0)
	var bc := c if frac > 0.15 else (UIKit.INK_WARN if fmod(_t, 0.8) < 0.5 else c * 0.5)
	draw_rect(Rect2(bx, by, 80, 20), bc, false, 2.0)
	draw_rect(Rect2(bx + 82, by + 6, 5, 8), bc)
	draw_rect(Rect2(bx + 3, by + 3, 74.0 * frac, 14), bc)
	# lamp
	if not playback:
		draw_string(font, Vector2(m + 8, sz.y - m - 8), "LAMP %s" % ("ON" if camcorder.is_lamp_on() else "OFF"), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, c)
		if camcorder.stakeout_progress > 0.0:
			var cx := sz.x * 0.5
			var cy := sz.y * 0.5 + 60.0
			draw_arc(Vector2(cx, cy), 20.0, -PI * 0.5, -PI * 0.5 + TAU * camcorder.stakeout_progress, 32, UIKit.ACCENT, 4.0)
			draw_string(font, Vector2(cx - 80, cy + 46), "SETTING DOWN", HORIZONTAL_ALIGNMENT_CENTER, 160, 16, UIKit.ACCENT)
	else:
		# scrub bar
		var bw := sz.x * 0.6
		var bx2 := (sz.x - bw) * 0.5
		var y := sz.y - m - 24.0
		draw_rect(Rect2(bx2, y, bw, 8), c * Color(1, 1, 1, 0.35))
		var pos := camcorder.playback_time() / maxf(0.01, camcorder.playback_length())
		draw_rect(Rect2(bx2, y, bw * pos, 8), c)
		draw_string(font, Vector2(bx2, y - 8), "%s  /  %s" % [tc, "%02d:%02d" % [int(camcorder.playback_length()) / 60, int(camcorder.playback_length()) % 60]], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, c)
		draw_string(font, Vector2(bx2, y + 28), "[A/D] scrub   [%s] freeze frame   [%s] close   [%s] pause" % [UIKit.key_label(&"freeze_frame"), UIKit.key_label(&"playback"), UIKit.key_label(&"interact")], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIKit.INK_DIM)
