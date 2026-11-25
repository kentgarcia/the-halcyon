extends Node
## Everything about the current run that must be saveable and reproducible (SPEC 12.2).
## Serializable. Co-op ready: entities act via intent, truth lives here.

enum Truth { HOLDS, INVERTED }
enum Mark { UNKNOWN, TRUST, LIE }

const NERVE_MAX_DEFAULT := 3

var run_seed: int = 0
var rng: RngStreams = RngStreams.new(0)

var guest_number: int = 1
var floor_index: int = 0                     ## index into FloorCatalog.ORDER
var floor_attempt: int = 0                   ## +1 on every Blackout (re-roll)
var floor_id: StringName = &""
var floor_seed: int = 0

var truths: Dictionary = {}                  ## floor_id -> Truth (the entity rule's variant this run)
var marks: Dictionary = {}                   ## rule_id -> Mark (this floor's notebook marks)
var verdict: int = -1                        ## -1 none, else Mark.TRUST / Mark.LIE filed in the Suggestion Box
var verdict_correct: int = -1                ## -1 undecided, 0 wrong, 1 right (set at exam/inspection)

var nerve: int = NERVE_MAX_DEFAULT
var nerve_max: int = NERVE_MAX_DEFAULT
var battery: float = 100.0
var pocket: StringName = &""
var freeze_frames_left: int = 3

var evidence_found: Dictionary = {}          ## evidence_id -> true
var clause: StringName = &""                 ## the one Clause in force (SPEC 4.10, v0.3)
var clause_void: bool = false
var courtesies: Array[StringName] = []       ## unspent Courtesies

var floor_clock: float = 0.0                 ## seconds on this floor (Housekeeping)
var housekeeping_warned: bool = false
var deaths_this_run: int = 0
var correct_inspections: int = 0
var wrong_inspections: int = 0
var cleared_floors: Array[StringName] = []   ## floors cleared in THIS run
var entity_mark_ok: Dictionary = {}          ## floor_id -> bool: entity rule marked correctly at Inspection (Burn the Card)

## Reproducible counters used by systems that need unique ids within a run.
var _next_id: int = 1


func new_run(seed_value: int, guest_n: int = 1) -> void:
	run_seed = seed_value
	guest_number = guest_n
	floor_index = 0
	floor_attempt = 0
	floor_id = &""
	truths.clear()
	marks.clear()
	verdict = -1
	verdict_correct = -1
	nerve_max = maxi(2, Settings.nerve_hits)
	nerve = nerve_max
	battery = 100.0
	pocket = &""
	freeze_frames_left = 3
	evidence_found.clear()
	clause = &""
	clause_void = false
	courtesies.clear()
	floor_clock = 0.0
	housekeeping_warned = false
	deaths_this_run = 0
	correct_inspections = 0
	wrong_inspections = 0
	cleared_floors.clear()
	entity_mark_ok.clear()
	_next_id = 1
	_seed_floor()


func begin_floor(new_floor_id: StringName, index: int) -> void:
	floor_id = new_floor_id
	floor_index = index
	marks.clear()
	verdict = -1
	verdict_correct = -1
	floor_clock = 0.0
	housekeeping_warned = false
	clause_void = false
	freeze_frames_left = 3
	_seed_floor()


func reroll_floor_after_blackout() -> void:
	## New layout, new truth; notebook intact (SPEC 3.3).
	floor_attempt += 1
	deaths_this_run += 1
	begin_floor(floor_id, floor_index)


func _seed_floor() -> void:
	floor_seed = RngStreams.mix(run_seed, floor_index * 1009 + floor_attempt * 7919 + 17)
	rng.reseed(floor_seed)


func stream(stream_name: StringName) -> RandomNumberGenerator:
	return rng.stream(stream_name)


func entity_truth(for_floor: StringName = &"") -> int:
	var key := for_floor if for_floor != &"" else floor_id
	return int(truths.get(key, Truth.HOLDS))


func set_truth(for_floor: StringName, truth: int) -> void:
	truths[for_floor] = truth


func mark_rule(rule_id: StringName, mark: int) -> void:
	marks[rule_id] = mark
	EventBus.rule_marked.emit(rule_id, mark)


func mark_of(rule_id: StringName) -> int:
	return int(marks.get(rule_id, Mark.UNKNOWN))


func set_nerve(value: int) -> void:
	var v := clampi(value, 0, nerve_max)
	if v == nerve:
		return
	nerve = v
	EventBus.nerve_changed.emit(nerve)


func set_battery(value: float) -> void:
	var v := clampf(value, 0.0, 100.0)
	if is_equal_approx(v, battery):
		return
	battery = v
	EventBus.battery_changed.emit(battery)


func set_pocket(item: StringName) -> void:
	pocket = item
	EventBus.pocket_changed.emit(pocket)


func record_evidence(evidence_id: StringName) -> bool:
	if evidence_found.has(evidence_id):
		return false
	evidence_found[evidence_id] = true
	EventBus.evidence_found.emit(evidence_id)
	return true


func next_id() -> int:
	_next_id += 1
	return _next_id


func to_dict() -> Dictionary:
	return {
		"v": 1,
		"run_seed": run_seed,
		"rng": rng.to_dict(),
		"guest_number": guest_number,
		"floor_index": floor_index,
		"floor_attempt": floor_attempt,
		"floor_id": String(floor_id),
		"truths": _stringify_keys(truths),
		"marks": _stringify_keys(marks),
		"verdict": verdict,
		"nerve": nerve,
		"nerve_max": nerve_max,
		"battery": battery,
		"pocket": String(pocket),
		"freeze_frames_left": freeze_frames_left,
		"evidence_found": evidence_found.keys().map(func(k): return String(k)),
		"clause": String(clause),
		"clause_void": clause_void,
		"courtesies": courtesies.map(func(k): return String(k)),
		"floor_clock": floor_clock,
		"deaths_this_run": deaths_this_run,
		"correct_inspections": correct_inspections,
		"wrong_inspections": wrong_inspections,
		"cleared_floors": cleared_floors.map(func(k): return String(k)),
		"entity_mark_ok": _stringify_keys(entity_mark_ok),
	}


func from_dict(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	rng.from_dict(d.get("rng", {}))
	guest_number = int(d.get("guest_number", 1))
	floor_index = int(d.get("floor_index", 0))
	floor_attempt = int(d.get("floor_attempt", 0))
	floor_id = StringName(d.get("floor_id", ""))
	floor_seed = RngStreams.mix(run_seed, floor_index * 1009 + floor_attempt * 7919 + 17)
	truths = _name_keys(d.get("truths", {}))
	marks = _name_keys(d.get("marks", {}))
	verdict = int(d.get("verdict", -1))
	nerve = int(d.get("nerve", NERVE_MAX_DEFAULT))
	nerve_max = int(d.get("nerve_max", NERVE_MAX_DEFAULT))
	battery = float(d.get("battery", 100.0))
	pocket = StringName(d.get("pocket", ""))
	freeze_frames_left = int(d.get("freeze_frames_left", 3))
	evidence_found.clear()
	for k in d.get("evidence_found", []):
		evidence_found[StringName(k)] = true
	clause = StringName(d.get("clause", ""))
	clause_void = bool(d.get("clause_void", false))
	courtesies.clear()
	for k in d.get("courtesies", []):
		courtesies.append(StringName(k))
	floor_clock = float(d.get("floor_clock", 0.0))
	deaths_this_run = int(d.get("deaths_this_run", 0))
	correct_inspections = int(d.get("correct_inspections", 0))
	wrong_inspections = int(d.get("wrong_inspections", 0))
	cleared_floors.clear()
	for k in d.get("cleared_floors", []):
		cleared_floors.append(StringName(k))
	entity_mark_ok.clear()
	for k in d.get("entity_mark_ok", {}):
		entity_mark_ok[StringName(k)] = bool(d["entity_mark_ok"][k])


static func _stringify_keys(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		out[String(k)] = src[k]
	return out


static func _name_keys(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		out[StringName(k)] = int(src[k])
	return out
