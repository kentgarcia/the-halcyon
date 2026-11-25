class_name ChunkLibrary
extends RefCounted
## Loads every authored room (res://content/chunks/**/*.chunk) once and answers "which rooms can serve this
## beat on this floor". Specs are immutable after parsing, so they are shared by every run.

const ROOT := "res://content/chunks"

static var _specs: Dictionary = {}       ## StringName id -> ChunkSpec
static var _loaded := false
static var load_errors: Array[String] = []


static func reload() -> void:
	_specs.clear()
	load_errors = []
	_scan(ROOT)
	_loaded = true


static func _scan(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".chunk"):
			var spec := ChunkSpec.load_file("%s/%s" % [dir, f])
			if spec.errors.size() > 0:
				for e in spec.errors:
					load_errors.append("%s/%s: %s" % [dir, f, e])
				continue
			if _specs.has(spec.id):
				load_errors.append("%s/%s: duplicate id %s" % [dir, f, spec.id])
				continue
			_specs[spec.id] = spec
	for d in DirAccess.get_directories_at(dir):
		if d != "dev":
			_scan("%s/%s" % [dir, d])


static func all() -> Array[ChunkSpec]:
	if not _loaded:
		reload()
	var out: Array[ChunkSpec] = []
	for k in _specs:
		out.append(_specs[k])
	return out


static func get_spec(id: StringName) -> ChunkSpec:
	if not _loaded:
		reload()
	return _specs.get(id, null)


static func serves(spec: ChunkSpec, floor_id: StringName) -> bool:
	return spec.floors.is_empty() or spec.floors.has(floor_id)


static func pool(floor_id: StringName, beat_kind: StringName) -> Array[ChunkSpec]:
	var out: Array[ChunkSpec] = []
	for s in all():
		if s.beat == beat_kind and serves(s, floor_id):
			out.append(s)
	out.sort_custom(func(a: ChunkSpec, b: ChunkSpec): return String(a.id) < String(b.id))
	return out


static func slot_count(spec: ChunkSpec, kind: StringName) -> int:
	var n := 0
	for sl in spec.slots:
		if sl.kind == kind:
			n += 1
	return n


static func panel_stats(spec: ChunkSpec) -> Dictionary:
	## {lit, dead, switchable}: how many panels start lit / dead / on a switchable circuit.
	var lit := 0
	var dead := 0
	var sw := 0
	for p in spec.panels:
		if p.circuit != &"":
			sw += 1
		elif p.lit:
			lit += 1
		else:
			dead += 1
	return {"lit": lit, "dead": dead, "switchable": sw}
