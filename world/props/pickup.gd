class_name Pickup
extends Node3D
## An item lying in the world. Interact to take it; the old pocket item (if any) drops where you stand.

var item_id: StringName = &"battery"
var dropped := false                      ## a pocket item the guest put down (Housekeeping tidies these)
var interactable: Interactable = null
var _taken := false


static func create(id: StringName, rng: RandomNumberGenerator = null) -> Pickup:
	var p := Pickup.new()
	p.item_id = id
	p.name = "Pickup_%s" % id
	var vis := PropFactory.make(id, rng)
	p.add_child(vis)
	if rng != null:
		p.rotation.y = rng.randf() * TAU
	var it := Interactable.new()
	it.name = "Use"
	it.position = Vector3(0, 0.12, 0)
	it.max_range = GameScale.INTERACT_RANGE + 0.3
	it.prompt_cb = func(_pl): return Items.prompt_for(id)
	it.tap_cb = p._on_take
	p.add_child(it)
	p.interactable = it
	return p


func _on_take(player: Node) -> void:
	if _taken:
		return
	_taken = true
	var session: Node = Game.session
	if item_id == &"battery":
		RunState.set_battery(RunState.battery + 50.0)
		AudioDirector.play(&"battery_pickup")
		EventBus.toast.emit("Battery +50.")
		queue_free()
		return
	if RunState.pocket != &"":
		_drop_old(player)
	RunState.set_pocket(item_id)
	AudioDirector.play(&"pickup_item")
	EventBus.toast.emit("%s. %s" % [Items.display_name(item_id), Items.hint_for(item_id)])
	if session != null and session.has_method("on_item_taken"):
		session.on_item_taken(item_id, self)
	queue_free()


func _drop_old(player: Node) -> void:
	var old := RunState.pocket
	var drop := Pickup.create(old, null)
	drop.dropped = true                   # Housekeeping takes dropped pocket items (SPEC 6.9)
	var pl := player as Node3D
	var fwd := -pl.global_transform.basis.z
	fwd.y = 0.0
	var pos := pl.global_position + fwd.normalized() * 0.7
	pos.y = 0.0
	get_parent().add_child(drop)
	drop.global_position = pos
