extends Node
var frames := 0
var t0 := 0
func _ready() -> void:
	t0 = Time.get_ticks_msec()
func _process(_d: float) -> void:
	frames += 1
	if frames % 20 == 0:
		print("fps_probe frame %d  t=%.2f  fps=%d" % [frames, (Time.get_ticks_msec() - t0) / 1000.0, Engine.get_frames_per_second()])
	if frames >= 100:
		get_tree().quit()
