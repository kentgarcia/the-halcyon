class_name RngStreams
extends RefCounted
## Named, independently-seeded RNG streams derived from one seed (SPEC 8.5).
## Gameplay code must never call global randf()/randi(); it asks a stream instead.
## Consuming one stream never perturbs another, so adding a cosmetic roll cannot change a floor layout.

const NAMES: Array[StringName] = [
	&"layout", &"rules", &"evidence", &"director", &"loot", &"cosmetic", &"entity",
]

var base_seed: int = 0
var _streams: Dictionary = {}   # StringName -> RandomNumberGenerator


func _init(seed_value: int = 0) -> void:
	reseed(seed_value)


func reseed(seed_value: int) -> void:
	base_seed = seed_value
	_streams.clear()
	for n in NAMES:
		_streams[n] = _make(n, 0)


func stream(stream_name: StringName) -> RandomNumberGenerator:
	if not _streams.has(stream_name):
		_streams[stream_name] = _make(stream_name, 0)
	return _streams[stream_name]


func derive(stream_name: StringName, salt: int) -> RandomNumberGenerator:
	## A fresh, independent generator for (stream, salt). Same inputs always give the same sequence.
	return _make(stream_name, salt)


func _make(stream_name: StringName, salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = RngStreams.mix(RngStreams.mix(base_seed, String(stream_name).hash()), salt)
	return r


func to_dict() -> Dictionary:
	var states := {}
	for n in _streams:
		states[String(n)] = (_streams[n] as RandomNumberGenerator).state
	return {"seed": base_seed, "states": states}


func from_dict(d: Dictionary) -> void:
	reseed(int(d.get("seed", 0)))
	var states: Dictionary = d.get("states", {})
	for k in states:
		var r := stream(StringName(k))
		r.state = int(states[k])


static func mix(a: int, b: int) -> int:
	## 64-bit integer hash combine (splitmix-style). Deterministic across platforms.
	var x: int = a ^ (b + 0x1E3779B97F4A7C15 + (a << 6) + (a >> 2))
	x = (x ^ (x >> 30)) * -4658895280553007687   # 0xBF58476D1CE4E5B9 as signed
	x = (x ^ (x >> 27)) * -7723592293110705685   # 0x94D049BB133111EB as signed
	return x ^ (x >> 31)


# --- pick helpers (take an explicit generator; never touch globals) -------------------------

static func pick(r: RandomNumberGenerator, arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[r.randi_range(0, arr.size() - 1)]


static func shuffled(r: RandomNumberGenerator, arr: Array) -> Array:
	var out := arr.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var t: Variant = out[i]
		out[i] = out[j]
		out[j] = t
	return out


static func weighted_index(r: RandomNumberGenerator, weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	if total <= 0.0:
		return -1
	var roll := r.randf() * total
	var acc := 0.0
	for i in weights.size():
		acc += maxf(0.0, float(weights[i]))
		if roll < acc:
			return i
	return weights.size() - 1
