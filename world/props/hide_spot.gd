class_name HideSpot
extends Node3D
## A place to hide: under a desk, inside a wardrobe/locker/cupboard (SPEC 3.2, 5.3). The node sits at the
## spot where the guest's body goes and faces OUT of the hiding place (-Z = outward).
## Entities look at `occupied` / `player.hidden`; "The knock" and "The handle" scares hook in here later.

signal entered(spot: HideSpot)
signal left(spot: HideSpot)

var kind: StringName = &"desk"             ## &"desk" | &"closet"
var sfx_open: StringName = &"wardrobe_open"  ## &"locker_open" on the Natatorium
var sfx_close: StringName = &"wardrobe_close"
var occupied := false
var interactable: Interactable = null
var door_node: Node3D = null               ## optional visual swing for closets
var tell_active := false                   ## something is outside right now (set by entities)


static func create(p_kind: StringName) -> HideSpot:
	var h := HideSpot.new()
	h.kind = p_kind
	h.name = "HideSpot_%s" % p_kind
	var it := Interactable.new()
	it.name = "Use"
	it.max_range = GameScale.INTERACT_RANGE + 0.2
	it.prompt_cb = h._prompt
	it.can_cb = h._can
	it.tap_cb = h._on_tap
	h.add_child(it)
	h.interactable = it
	return h


func eye_height() -> float:
	return 1.0 if kind == &"desk" else 1.4


func exit_position() -> Vector3:
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	var p := global_position + fwd.normalized() * (0.85 if kind == &"closet" else 0.8)
	p.y = 0.0
	return p


func _prompt(_player: Node) -> String:
	return "Hide"


func _can(player: Node) -> bool:
	return not occupied and not (player as Player).hidden


func _on_tap(player: Node) -> void:
	var p := player as Player
	if p == null:
		return
	# The interactable aims at the opening, so we place the body a little behind it.
	occupied = true
	p.enter_hide(self, eye_height(), 55.0 if kind == &"closet" else 70.0)
	AudioDirector.play_at(sfx_open if kind == &"closet" else &"step_carpet", global_position, -4.0 if kind == &"closet" else -14.0)
	EventBus.noise_emitted.emit(global_position, 0.1, &"hide")
	entered.emit(self)


func on_exit() -> void:
	occupied = false
	AudioDirector.play_at(sfx_close if kind == &"closet" else &"step_carpet", global_position, -6.0 if kind == &"closet" else -14.0)
	left.emit(self)
