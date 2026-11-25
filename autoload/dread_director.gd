extends Node
## Dread Director (SPEC 7). Placeholder shell — the pacing logic lives in core/director_core.gd and is
## wired up in the Director milestone. Holds the dread value everything else reads.

var dread: float = 0.0              ## 0..100
var enabled: bool = false


func reset() -> void:
	dread = 0.0
	EventBus.dread_changed.emit(dread)


func add_dread(amount: float) -> void:
	set_dread(dread + amount)


func set_dread(value: float) -> void:
	var v := clampf(value, 0.0, 100.0)
	if is_equal_approx(v, dread):
		return
	dread = v
	EventBus.dread_changed.emit(dread)


func normalized() -> float:
	return dread / 100.0
