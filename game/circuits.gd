class_name Circuits
extends RefCounted
## Switchable light circuits (SPEC 9.3, Appendix B). A circuit key is "<beat_index>:S", the key the chunk
## builder stamps on its `S` panels. Breakers and wall switches flip a circuit; chunks built later pick the
## current power up when they spawn, so a breaker thrown in one room still lights a corridor that is not
## built yet.

signal changed(key: StringName, on: bool)

var power: Dictionary = {}               ## StringName -> bool (absent = on)
var streamer: ChunkStreamer = null


func is_on(key: StringName) -> bool:
	return bool(power.get(key, true))


func set_default(key: StringName, on: bool) -> void:
	power[key] = on


func set_power(key: StringName, on: bool) -> void:
	power[key] = on
	_apply_live(key, on)
	changed.emit(key, on)
	EventBus.noise_emitted.emit(Vector3.ZERO, 0.0, &"circuit")


func toggle(key: StringName) -> bool:
	var now := not is_on(key)
	set_power(key, now)
	return now


func apply_to_chunk(chunk: Chunk) -> void:
	for c in chunk.cells:
		if c.circuit != &"":
			var on := is_on(c.circuit)
			c.home_powered = on
			c.set_powered(on)


func _apply_live(key: StringName, on: bool) -> void:
	if streamer == null:
		return
	for uid in streamer.chunks:
		var chunk: Chunk = streamer.chunks[uid]
		for c in chunk.cells:
			if c.circuit == key:
				c.home_powered = on
				c.set_powered(on)
