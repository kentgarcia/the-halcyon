extends Node
## Player-facing options: render scale, accessibility (SPEC 11.3), audio, controls.
## Persisted to user://settings.cfg. Gameplay reads these; nothing here is gameplay state.

signal changed(key: StringName)

const PATH := "user://settings.cfg"
const SECTION := "settings"

# --- render
var render_height: int = 360              ## internal 3D height in px; 0 = native
var retro_intensity: float = 1.0          ## tape finish strength 0..1
var vertex_snap: float = 0.0              ## PS1 wobble, off by default
var fullscreen: bool = false
var vsync: bool = true
var max_fps: int = 0

# --- camera / comfort
var fov: float = 75.0                     ## 60..110
var mouse_sensitivity: float = 0.0022
var invert_y: bool = false
var head_bob: bool = true
var reduce_motion: bool = false           ## disables bob, shake, vignette pulsing
var safe_flicker: bool = false            ## caps flicker amplitude + glitch band
var camcorder_toggle: bool = false        ## false = hold RMB to raise
var crouch_toggle: bool = true

# --- audio
var vol_master: float = 0.9
var vol_world: float = 1.0
var vol_hum: float = 0.8
var vol_pa: float = 1.0
var vol_tape: float = 1.0
var vol_muzak: float = 0.8
var vol_dread: float = 0.9

# --- accessibility / difficulty
var subtitles: bool = true
var sound_subtitles: bool = true          ## "[Scrape - left]" cues
var sound_radar: bool = false
var tell_time_mult: float = 1.0           ## 1.0 or 1.5
var nerve_hits: int = 3                   ## 2 / 3 / 4
var guided_rules: bool = false            ## gentle highlight on the lie AFTER inspection, never before
var evidence_density: float = 1.0
var housekeeping_enabled: bool = true

# --- meta
var first_launch_done: bool = false

var _loading := false


func _ready() -> void:
	InputSetup.ensure_actions()
	load_settings()
	apply()


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	_loading = true
	for p in _persisted_props():
		if cf.has_section_key(SECTION, p):
			var cur: Variant = get(p)
			var v: Variant = cf.get_value(SECTION, p, cur)
			if typeof(v) == typeof(cur):
				set(p, v)
			elif typeof(cur) == TYPE_FLOAT and typeof(v) == TYPE_INT:
				set(p, float(v))
	_loading = false
	_sanitize()


func save_settings() -> void:
	var cf := ConfigFile.new()
	for p in _persisted_props():
		cf.set_value(SECTION, p, get(p))
	cf.save(PATH)


func set_value(key: StringName, value: Variant) -> void:
	set(key, value)
	_sanitize()
	if not _loading:
		apply()
		changed.emit(key)
		save_settings()


func _sanitize() -> void:
	fov = clampf(fov, 60.0, 110.0)
	nerve_hits = clampi(nerve_hits, 2, 4)
	tell_time_mult = clampf(tell_time_mult, 1.0, 2.0)
	retro_intensity = clampf(retro_intensity, 0.0, 1.0)
	render_height = maxi(0, render_height)
	mouse_sensitivity = clampf(mouse_sensitivity, 0.0003, 0.02)


func apply() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
	var force_off := OS.get_cmdline_args().has("--disable-vsync")
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if (vsync and not force_off) else DisplayServer.VSYNC_DISABLED
	)
	Engine.max_fps = max_fps


func tell_lead_seconds(base: float = 4.0) -> float:
	## The Fairness Doctrine floor is 4 s (6 s on accessibility presets); the multiplier only adds.
	return base * tell_time_mult


func _persisted_props() -> PackedStringArray:
	return PackedStringArray([
		"render_height", "retro_intensity", "vertex_snap", "fullscreen", "vsync", "max_fps",
		"fov", "mouse_sensitivity", "invert_y", "head_bob", "reduce_motion", "safe_flicker",
		"camcorder_toggle", "crouch_toggle",
		"vol_master", "vol_world", "vol_hum", "vol_pa", "vol_tape", "vol_muzak", "vol_dread",
		"subtitles", "sound_subtitles", "sound_radar", "tell_time_mult", "nerve_hits",
		"guided_rules", "evidence_density", "housekeeping_enabled", "first_launch_done",
	])
