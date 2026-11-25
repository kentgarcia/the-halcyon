extends Node
## Buses, one-shots, positional sound, ambience layers, the PA queue and subtitles (SPEC 10).
## Reads res://audio/manifest.json (written by tools/audio) and res://data/pa_lines.json.
## Every call is safe when a sound is missing: it logs once and carries on, so the game never
## crashes because an asset hasn't been generated yet.

const MANIFEST_PATH := "res://audio/manifest.json"
const PA_LINES_PATH := "res://data/pa_lines.json"
const BUS_NAMES: Array[StringName] = [&"World", &"Hum", &"PA", &"Tape", &"Muzak", &"Dread", &"UI"]
const MAX_3D := 14
const MAX_2D := 10

signal pa_started(line_id: StringName)
signal pa_finished(line_id: StringName)

var manifest: Dictionary = {}
var pa_lines: Dictionary = {}                 ## id -> entry from pa_lines.json
var _missing_logged: Dictionary = {}
var _stream_cache: Dictionary = {}            ## path -> AudioStream
var _world_root: Node3D = null
var _players3d: Array[AudioStreamPlayer3D] = []
var _players2d: Array[AudioStreamPlayer] = []
var _ambience: Dictionary = {}                ## id -> {"player", "target_db", "base_db"}
var _pa_queue: Array = []
var _pa_player: AudioStreamPlayer = null
var _pa_busy := false
var _pa_current: StringName = &""
var _pa_timer: Timer = null
var _hum_pitch_target := 1.0
var _hum_duck := 0.0                          ## 0 normal .. 1 silent (silence is a tool)
var _mute_all := false
var headless := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	headless = DisplayServer.get_name() == "headless"
	_setup_buses()
	_load_manifest()
	_load_pa_lines()
	for i in MAX_2D:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players2d.append(p)
	_pa_player = AudioStreamPlayer.new()
	_pa_player.bus = "PA"
	add_child(_pa_player)
	_pa_timer = Timer.new()
	_pa_timer.one_shot = true
	_pa_timer.timeout.connect(_on_pa_timeout)
	add_child(_pa_timer)
	Settings.changed.connect(_on_settings_changed)
	apply_volumes()


func _process(delta: float) -> void:
	# Ease ambience layers toward their targets; hum pitch/duck are tell channels.
	for id in _ambience:
		var e: Dictionary = _ambience[id]
		var p: AudioStreamPlayer = e["player"]
		var tgt: float = e["target_db"]
		var cur := p.volume_db
		if id == &"amb_hum_bed" or id == &"amb_buzz_cell":
			tgt = lerpf(tgt, -60.0, _hum_duck)
		var step := 24.0 * delta
		p.volume_db = move_toward(cur, tgt, step)
		if tgt <= -59.0 and p.volume_db <= -59.0 and p.playing and not bool(e.get("keep", false)):
			p.stop()
		elif tgt > -59.0 and not p.playing:
			p.play()
		if id == &"amb_hum_bed":
			p.pitch_scale = lerpf(p.pitch_scale, _hum_pitch_target, clampf(delta * 3.0, 0.0, 1.0))


# --- setup ----------------------------------------------------------------------------------

func _setup_buses() -> void:
	for n in BUS_NAMES:
		if AudioServer.get_bus_index(n) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, n)
			AudioServer.set_bus_send(idx, &"Master")
	_add_effect(&"World", _reverb(0.35, 0.7, 0.10))
	var pa_hp := AudioEffectHighPassFilter.new()
	pa_hp.cutoff_hz = 320.0
	var pa_lp := AudioEffectLowPassFilter.new()
	pa_lp.cutoff_hz = 3600.0
	_add_effect(&"PA", pa_hp)
	_add_effect(&"PA", pa_lp)
	_add_effect(&"PA", _reverb(0.55, 0.6, 0.22))
	var tape_lp := AudioEffectLowPassFilter.new()
	tape_lp.cutoff_hz = 5200.0
	_add_effect(&"Tape", tape_lp)
	var muz_lp := AudioEffectLowPassFilter.new()
	muz_lp.cutoff_hz = 6500.0
	_add_effect(&"Muzak", muz_lp)


func _reverb(room: float, damp: float, wet: float) -> AudioEffectReverb:
	var r := AudioEffectReverb.new()
	r.room_size = room
	r.damping = damp
	r.wet = wet
	r.dry = 1.0
	return r


func _add_effect(bus_name: StringName, fx: AudioEffect) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.add_bus_effect(idx, fx)


func _load_manifest() -> void:
	manifest = {"sounds": {}, "voice": {}}
	if not FileAccess.file_exists(MANIFEST_PATH):
		return
	var f := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		manifest = parsed
		if not manifest.has("sounds"):
			manifest["sounds"] = {}
		if not manifest.has("voice"):
			manifest["voice"] = {}


func _load_pa_lines() -> void:
	pa_lines.clear()
	if not FileAccess.file_exists(PA_LINES_PATH):
		return
	var f := FileAccess.open(PA_LINES_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for entry in (parsed as Dictionary).get("lines", []):
		pa_lines[StringName(entry["id"])] = entry


func reload() -> void:
	_stream_cache.clear()
	_load_manifest()
	_load_pa_lines()


func apply_volumes() -> void:
	_set_bus_linear(&"Master", Settings.vol_master)
	_set_bus_linear(&"World", Settings.vol_world)
	_set_bus_linear(&"Hum", Settings.vol_hum)
	_set_bus_linear(&"PA", Settings.vol_pa)
	_set_bus_linear(&"Tape", Settings.vol_tape)
	_set_bus_linear(&"Muzak", Settings.vol_muzak)
	_set_bus_linear(&"Dread", Settings.vol_dread)


func _set_bus_linear(bus_name: StringName, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))


func _on_settings_changed(_key: StringName) -> void:
	apply_volumes()


# --- queries --------------------------------------------------------------------------------

func has_sound(id: StringName) -> bool:
	return (manifest["sounds"] as Dictionary).has(String(id))


func sound_duration(id: StringName) -> float:
	var e: Variant = (manifest["sounds"] as Dictionary).get(String(id), null)
	return float(e["dur"]) if e != null else 0.0


func line_text(line_id: StringName) -> String:
	if pa_lines.has(line_id):
		return String(pa_lines[line_id].get("text", ""))
	return ""


# --- world attachment (3D players live in the game viewport's world) -----------------------

func attach_world(root: Node3D) -> void:
	_world_root = root
	_players3d.clear()
	for i in MAX_3D:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 4.0
		p.max_distance = 40.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		root.add_child(p)
		_players3d.append(p)


func detach_world() -> void:
	for p in _players3d:
		if is_instance_valid(p):
			p.queue_free()
	_players3d.clear()
	_world_root = null


# --- one-shots ------------------------------------------------------------------------------

func play(id: StringName, db_offset: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer:
	## Non-positional sound (UI, tape, foley on the player, stingers).
	var entry := _entry(id)
	if entry.is_empty() or _mute_all:
		return null
	var stream := _pick_stream(entry, id)
	if stream == null:
		return null
	var p := _free_2d()
	if p == null:
		return null
	p.stream = stream
	p.bus = String(entry.get("bus", "World"))
	p.volume_db = float(entry.get("db", 0.0)) + db_offset
	p.pitch_scale = pitch
	p.play()
	return p


func play_at(id: StringName, pos: Vector3, db_offset: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer3D:
	var entry := _entry(id)
	if entry.is_empty() or _mute_all:
		return null
	if Settings.sound_radar:
		EventBus.sound_heard.emit(id, pos)
	if _world_root == null or _players3d.is_empty():
		play(id, db_offset - 6.0, pitch)
		return null
	var stream := _pick_stream(entry, id)
	if stream == null:
		return null
	var p := _free_3d()
	if p == null:
		return null
	p.stream = stream
	p.bus = String(entry.get("bus", "World"))
	p.volume_db = float(entry.get("db", 0.0)) + db_offset
	p.pitch_scale = pitch
	p.global_position = pos
	p.play()
	return p


func play_looped_at(id: StringName, parent: Node3D, db_offset: float = 0.0) -> AudioStreamPlayer3D:
	## A dedicated positional looping emitter parented to a world node (a light fixture, a cart).
	## The caller owns it and frees it with the parent.
	var entry := _entry(id)
	if entry.is_empty():
		return null
	var stream := _pick_stream(entry, id)
	if stream == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = String(entry.get("bus", "World"))
	p.volume_db = float(entry.get("db", 0.0)) + db_offset
	p.unit_size = 3.0
	p.max_distance = 30.0
	parent.add_child(p)
	p.play()
	return p


func stop_player(p: Node) -> void:
	if p != null and is_instance_valid(p):
		p.call("stop")


# --- ambience layers -----------------------------------------------------------------------

func set_ambience(id: StringName, enabled: bool, db_offset: float = 0.0) -> void:
	var entry := _entry(id)
	if entry.is_empty():
		return
	var base := float(entry.get("db", -20.0)) + db_offset
	if not _ambience.has(id):
		var stream := _pick_stream(entry, id)
		if stream == null:
			return
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.bus = String(entry.get("bus", "World"))
		p.volume_db = -60.0
		add_child(p)
		_ambience[id] = {"player": p, "target_db": -60.0, "base_db": base}
	var e: Dictionary = _ambience[id]
	e["base_db"] = base
	e["target_db"] = base if enabled else -60.0
	if enabled and not (e["player"] as AudioStreamPlayer).playing:
		(e["player"] as AudioStreamPlayer).play()


func set_ambience_level(id: StringName, linear: float) -> void:
	## linear 0..1 of the layer's authored loudness (used by dread layers).
	if not _ambience.has(id):
		return
	var e: Dictionary = _ambience[id]
	e["target_db"] = lerpf(-60.0, float(e["base_db"]), clampf(linear, 0.0, 1.0)) if linear > 0.01 else -60.0


func stop_all_ambience() -> void:
	for id in _ambience:
		(_ambience[id] as Dictionary)["target_db"] = -60.0


func set_hum_pitch(ratio: float) -> void:
	_hum_pitch_target = clampf(ratio, 0.7, 1.3)


func set_hum_duck(amount: float) -> void:
	_hum_duck = clampf(amount, 0.0, 1.0)


func stop_everything() -> void:
	stop_all_ambience()
	for p in _players2d:
		p.stop()
	for p in _players3d:
		p.stop()
	_pa_queue.clear()
	_pa_player.stop()
	_pa_busy = false
	_pa_timer.stop()
	_hum_duck = 0.0
	_hum_pitch_target = 1.0


# --- subtitles for non-speech cues ---------------------------------------------------------

func cue(text: String, duration: float = 2.0) -> void:
	## e.g. cue("[Scrape - left]"). Shown only when sound subtitles are on (SPEC 11.3).
	if Settings.sound_subtitles:
		EventBus.subtitle.emit(text, duration)


# --- PA -------------------------------------------------------------------------------------

func say(line_id: StringName, take: StringName = &"true", priority: bool = false) -> void:
	## Queue a Management line. take = "true" or "false" (the Secret Tell take, SPEC 4.5).
	var item := {"id": line_id, "take": take}
	if priority:
		_pa_queue.push_front(item)
	else:
		_pa_queue.append(item)
	_pump_pa()


func is_pa_busy() -> bool:
	return _pa_busy or not _pa_queue.is_empty()


func clear_pa() -> void:
	_pa_queue.clear()


func _pump_pa() -> void:
	if _pa_busy or _pa_queue.is_empty():
		return
	var item: Dictionary = _pa_queue.pop_front()
	var line_id: StringName = item["id"]
	var take: StringName = item["take"]
	var text := line_text(line_id)
	var voice: Dictionary = (manifest["voice"] as Dictionary).get(String(line_id), {})
	var path := ""
	var dur := 0.0
	if not voice.is_empty():
		var key := String(take)
		var p: Variant = voice.get(key, null)
		if p == null:
			p = voice.get("true", null)
			key = "true"
		if p != null:
			path = String(p)
			dur = float(voice.get("dur_" + key, 0.0))
		if text == "":
			text = String(voice.get("text", ""))
	if dur <= 0.0:
		dur = maxf(1.5, text.length() * 0.062)   # no audio yet: still show the subtitle for a sane time
	_pa_busy = true
	_pa_current = line_id
	pa_started.emit(line_id)
	EventBus.pa_line_requested.emit(line_id, take)
	play(&"pa_click_on")
	if path != "" and ResourceLoader.exists(path):
		var stream := _load_stream(path)
		if stream != null and not _mute_all:
			_pa_player.stream = stream
			_pa_player.volume_db = 0.0
			_pa_player.play()
			dur = maxf(dur, stream.get_length())
	if text != "" and Settings.subtitles:
		EventBus.subtitle.emit(text, dur + 0.6)
	_pa_timer.start(dur + 0.35)


func _on_pa_timeout() -> void:
	play(&"pa_click_off")
	_pa_busy = false
	var finished := _pa_current
	_pa_current = &""
	pa_finished.emit(finished)
	_pump_pa()


# --- internals -----------------------------------------------------------------------------

func _entry(id: StringName) -> Dictionary:
	var e: Variant = (manifest["sounds"] as Dictionary).get(String(id), null)
	if e == null:
		if not _missing_logged.has(id):
			_missing_logged[id] = true
			if not headless:
				push_warning("AudioDirector: no sound '%s' in manifest" % id)
		return {}
	return e


func _pick_stream(entry: Dictionary, id: StringName) -> AudioStream:
	var files: Array = entry.get("files", [])
	if files.is_empty():
		return null
	var path := String(files[0]) if files.size() == 1 else String(RngStreams.pick(RunState.stream(&"cosmetic"), files))
	var stream := _load_stream(path)
	if stream == null:
		return null
	if bool(entry.get("loop", false)):
		stream = _looped(stream, path)
	return stream


func _load_stream(path: String) -> AudioStream:
	if _stream_cache.has(path):
		return _stream_cache[path]
	if not ResourceLoader.exists(path):
		if not _missing_logged.has(path):
			_missing_logged[path] = true
			if not headless:
				push_warning("AudioDirector: file missing %s" % path)
		return null
	var s := load(path) as AudioStream
	_stream_cache[path] = s
	return s


func _looped(stream: AudioStream, path: String) -> AudioStream:
	var key := path + "#loop"
	if _stream_cache.has(key):
		return _stream_cache[key]
	var out: AudioStream = stream
	if stream is AudioStreamWAV:
		var w := (stream as AudioStreamWAV).duplicate() as AudioStreamWAV
		var bytes_per_frame := 1
		match w.format:
			AudioStreamWAV.FORMAT_16_BITS: bytes_per_frame = 2
			AudioStreamWAV.FORMAT_8_BITS: bytes_per_frame = 1
			_: bytes_per_frame = 2
		if w.stereo:
			bytes_per_frame *= 2
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = maxi(1, w.data.size() / bytes_per_frame)
		out = w
	elif stream is AudioStreamOggVorbis:
		var o := (stream as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
		o.loop = true
		out = o
	_stream_cache[key] = out
	return out


func _free_2d() -> AudioStreamPlayer:
	for p in _players2d:
		if not p.playing:
			return p
	return _players2d[0]


func _free_3d() -> AudioStreamPlayer3D:
	for p in _players3d:
		if is_instance_valid(p) and not p.playing:
			return p
	return null
