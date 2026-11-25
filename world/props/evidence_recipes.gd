class_name EvidenceRecipes
extends RefCounted
## Floor-specific PROP_STATE evidence (SPEC 4.3). Each recipe lives in world/props/recipes/<recipe>.gd as
##   static func can_host(spec: ChunkSpec, e: EvidenceDef) -> bool      (optional; default true)
##   static func place(chunk: Chunk, e: EvidenceDef, rng: RandomNumberGenerator, session: Node) -> void
## `recipe` is EvidenceDef.params["recipe"]. Evidence must be TRUE for the run (Fairness Doctrine 1) and must be
## placed as EvidenceMark nodes (group "evidence") so the EvidenceTracker can tell when the guest actually saw it.
## The claw/dust/scorch recipes of the Yellow floor are built into SlotPopulator.


static func _script(recipe: String) -> GDScript:
	var path := "res://world/props/recipes/%s.gd" % recipe
	if recipe == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as GDScript


static func can_host(spec: ChunkSpec, e: EvidenceDef) -> bool:
	var scr := _script(String(e.params.get("recipe", "")))
	if scr == null or not scr.has_method(&"can_host"):
		return true
	return bool(scr.call(&"can_host", spec, e))


static func place(chunk: Chunk, e: EvidenceDef, rng: RandomNumberGenerator, session: Node) -> void:
	var scr := _script(String(e.params.get("recipe", "")))
	if scr != null and scr.has_method(&"place"):
		scr.call(&"place", chunk, e, rng, session)
