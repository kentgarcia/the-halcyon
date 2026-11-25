class_name EvidenceTracker
extends Node
## Decides when the guest has actually *seen* a piece of world evidence (SPEC 4.3): looking at it, close
## enough, in enough light (or under the camcorder lamp) for a moment. Found evidence becomes a notebook
## sticker. Nothing is automatic: walk past a scrawl in the dark and you simply missed it.

const DWELL_NEEDED := 0.7
const CONE_DEG := 30.0
const CONE_DEG_RAISED := 18.0
const LIGHT_NEEDED := 0.32

var session: Node = null
var _dwell: Dictionary = {}              ## instance id -> seconds
var _accum := 0.0


func _process(delta: float) -> void:
	if session == null or session.player == null:
		return
	_accum += delta
	if _accum < 0.1:
		return
	var dt := _accum
	_accum = 0.0
	var pl: Player = session.player
	if pl.frozen or pl.look_locked:
		return
	var cc: Camcorder = session.camcorder
	var eye := pl.camera.global_position
	var fwd := pl.look_direction()
	var cone := deg_to_rad(CONE_DEG_RAISED if cc != null and cc.is_raised() else CONE_DEG)
	var space := pl.get_world_3d().direct_space_state
	for n in get_tree().get_nodes_in_group(&"evidence"):
		var m := n as EvidenceMark
		if m == null or m.found or not m.is_inside_tree():
			continue
		var p := m.global_position
		var to := p - eye
		var dist := to.length()
		var id := m.get_instance_id()
		if dist > m.read_radius or dist < 0.05 or fwd.angle_to(to) > cone or not _visible(space, pl, eye, p):
			_decay(id, dt)
			continue
		var lit := _lit_enough(p)
		if not lit and m.needs_light and cc != null and cc.lamp_hits(p):
			lit = true
		if not lit:
			_decay(id, dt)
			continue
		var d: float = float(_dwell.get(id, 0.0)) + dt
		_dwell[id] = d
		if d >= DWELL_NEEDED:
			_found(m)


func _visible(space: PhysicsDirectSpaceState3D, pl: Player, eye: Vector3, p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(eye, p, GameScale.LAYER_WORLD | GameScale.LAYER_DOORS)
	q.exclude = [pl.get_rid()]
	var hit := space.intersect_ray(q)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(p) < 0.45


func _lit_enough(p: Vector3) -> bool:
	var stage: Stage = session.stage
	if stage == null or stage.light_field == null:
		return true
	return stage.light_field.level_at_tile(GameScale.world_to_tile(p)) >= LIGHT_NEEDED


func _decay(id: int, dt: float) -> void:
	if _dwell.has(id):
		var d: float = float(_dwell[id]) - dt * 2.0
		if d <= 0.0:
			_dwell.erase(id)
		else:
			_dwell[id] = d


func _found(m: EvidenceMark) -> void:
	m.found = true
	_dwell.erase(m.get_instance_id())
	note(m.def)


func note(def: EvidenceDef) -> void:
	## Also called by other systems (tape clips watched, buzz heard) for evidence not tied to a mark.
	if def == null or not RunState.record_evidence(def.id):
		return
	AudioDirector.play(&"pen_scratch", -6.0)
	EventBus.toast.emit("Noted in the notebook.")
