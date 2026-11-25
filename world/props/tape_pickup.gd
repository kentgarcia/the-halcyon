class_name TapePickup
extends Node3D
## A VHS tape lying about. Interact to put it in the camcorder: plays an Echo clip (SPEC 4.3, 4.11).
## The footage is real behaviour of this run's variant (Doctrine 1), or your own old death tape.

var clip_id: StringName = &""
var evidence_id: StringName = &""
var label_text: String = ""
var own_death: Dictionary = {}           ## set for "your own tapes" (SPEC 4.11)
var interactable: Interactable = null


static func create(p_clip: StringName, p_evidence: StringName) -> TapePickup:
	var t := TapePickup.new()
	t.clip_id = p_clip
	t.evidence_id = p_evidence
	t.name = "Tape_%s" % p_clip
	t.add_child(PropFactory.make(&"tape"))
	var it := Interactable.new()
	it.name = "Use"
	it.position = Vector3(0, 0.1, 0)
	it.max_range = GameScale.INTERACT_RANGE + 0.3
	it.prompt_cb = func(_pl): return "Play the tape"
	it.tap_cb = t._on_tap
	t.add_child(it)
	t.interactable = it
	return t


func _on_tap(_player: Node) -> void:
	AudioDirector.play_at(&"cam_tape_insert", global_position)
	var session: Node = Game.session
	if session != null and session.has_method("play_echo"):
		session.play_echo(self)
