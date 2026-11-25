class_name EvidenceMark
extends Node3D
## World evidence (SPEC 4.3). Always TRUE for the current run (Fairness Doctrine 1). A mark counts as
## found once the guest has looked at it, in enough light, for a moment (EvidenceTracker).

var def: EvidenceDef = null
var found := false
var needs_light := true
var read_radius := 6.5


static func create(p_def: EvidenceDef) -> EvidenceMark:
	var m := EvidenceMark.new()
	m.def = p_def
	m.name = "Evidence_%s" % p_def.id
	m.add_to_group(&"evidence")
	return m
