class_name LightFixture
extends Node3D
## The tube in a ceiling panel can be moved (SPEC 3.2.3, Bulb): take it from a lit fixture (the cell goes
## DEAD), fit it into a dead one (the cell goes ON). You move the light.

var cell: LightCell = null
var interactable: Interactable = null


static func create(p_cell: LightCell) -> LightFixture:
	var f := LightFixture.new()
	f.cell = p_cell
	f.name = "Fixture_%d" % p_cell.index
	var it := Interactable.new()
	it.name = "Use"
	it.max_range = GameScale.INTERACT_RANGE + 0.35
	it.prompt_cb = f._prompt
	it.can_cb = f._can
	it.tap_cb = f._on_tap
	f.add_child(it)
	f.interactable = it
	return f


func _can(_player: Node) -> bool:
	if cell == null:
		return false
	if cell.has_tube:
		return RunState.pocket == &""
	return RunState.pocket == &"bulb"


func _prompt(_player: Node) -> String:
	if cell == null:
		return ""
	return "Take the tube" if cell.has_tube else "Fit the tube"


func _on_tap(_player: Node) -> void:
	if cell == null:
		return
	if cell.has_tube and RunState.pocket == &"":
		cell.set_tube(false)
		cell.home_tube = false
		RunState.set_pocket(&"bulb")
		AudioDirector.play_at(&"bulb_remove", global_position)
		EventBus.noise_emitted.emit(global_position, 0.2, &"bulb")
		EventBus.toast.emit("You take the tube. The light goes with it.")
	elif not cell.has_tube and RunState.pocket == &"bulb":
		cell.set_tube(true)
		cell.home_tube = true
		RunState.set_pocket(&"")
		AudioDirector.play_at(&"bulb_insert", global_position)
		EventBus.noise_emitted.emit(global_position, 0.2, &"bulb")
		cell.pulse_flicker(0.6)
