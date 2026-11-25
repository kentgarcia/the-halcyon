class_name PlantedCamcorder
extends Node3D
## The Stakeout (SPEC 3.2.1): the camcorder set down on the floor or a flat prop, recording in time-lapse.
## The guest walks away blind and lampless; retrieve it and rewind to see what the room did while unwatched.
## It pins its chunk so the room stays built; Housekeeping may tidy it to Lost & Found.

var chunk: Chunk = null
var interactable: Interactable = null
var recorder: TapeRecorder = null
var planted_at := 0.0
var yaw := 0.0


static func create(p_recorder: TapeRecorder, p_chunk: Chunk, pos: Vector3, p_yaw: float) -> PlantedCamcorder:
	var n := PlantedCamcorder.new()
	n.name = "PlantedCamcorder"
	n.recorder = p_recorder
	n.chunk = p_chunk
	n.yaw = p_yaw
	n.add_child(PropFactory.make(&"camcorder"))
	n.position = pos
	n.rotation.y = p_yaw
	var it := Interactable.new()
	it.name = "Use"
	it.position = Vector3(0, 0.12, 0)
	it.max_range = GameScale.INTERACT_RANGE + 0.5
	it.prompt_cb = func(_pl): return "Take the camcorder back"
	it.tap_cb = n._on_retrieve
	n.add_child(it)
	n.interactable = it
	if p_chunk != null:
		p_chunk.pinned = true
	return n


func lens_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), global_position + Vector3(0, 0.13, 0))


func _on_retrieve(_player: Node) -> void:
	var session: Node = Game.session
	if session != null and session.has_method("retrieve_camcorder"):
		session.retrieve_camcorder(self)


func release() -> void:
	if chunk != null and is_instance_valid(chunk):
		chunk.pinned = false
	queue_free()
