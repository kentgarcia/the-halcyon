class_name LightCell
extends RefCounted
## One ceiling light panel and the floor region it owns (SPEC 9.3: ceiling light cells are the
## building's pulse and the map's logic). A cell is ON, FLICKER or DEAD.
##
##   lit      = has_tube AND powered          (Bulb moves tubes; breakers/switches move power)
##   FLICKER  = lit but unstable (damaged fixture, or a Director tell)
##
## The region (Voronoi over walkable tiles) is what gameplay asks about ("is the player in light?").
## The footprint (tile -> weight) is what the light field paints.

enum State { ON, FLICKER, DEAD }

const FOOTPRINT_RADIUS := 4          ## tiles of walking distance that receive light
const FOOTPRINT_FALLOFF := 1.1

var chunk: Node = null               ## owning Chunk (untyped to avoid a cyclic class reference)
var index: int = 0                   ## index within the chunk
var tile: Vector2i = Vector2i.ZERO   ## WORLD tile of the panel
var local_tile: Vector2i = Vector2i.ZERO
var position: Vector3 = Vector3.ZERO ## WORLD position of the fixture (ceiling)
var circuit: StringName = &""        ## &"" = mains; otherwise "<beat>:S" style key set by the chunk
var has_tube: bool = true
var powered: bool = true
var base_flicker: bool = false
var temp_flicker: float = 0.0        ## seconds of Director-driven flicker remaining
var state: int = State.ON
var brightness: float = 1.0          ## animated 0..1 (what the field paints)
var boost: float = 0.0               ## 0..0.25 temporary surge on top of ON (set by tells; fades)
var region: Array[Vector2i] = []     ## WORLD tiles owned by this cell
var footprint: Dictionary = {}       ## WORLD tile -> weight 0..1
var neighbors: Array[LightCell] = []
var home_tube: bool = true           ## state to restore when Housekeeping tidies
var home_powered: bool = true
var marks_dust: bool = true          ## evidence: fixture dust (dead fixtures are dusty)
var tags: Dictionary = {}


func is_lit() -> bool:
	return has_tube and powered


func is_dead() -> bool:
	return not is_lit()


func recompute() -> bool:
	## Returns true when the state changed.
	var s := State.DEAD
	if is_lit():
		s = State.FLICKER if (base_flicker or temp_flicker > 0.0) else State.ON
	if s == state:
		return false
	state = s
	return true


func set_tube(v: bool) -> void:
	if has_tube == v:
		return
	has_tube = v
	_changed()


func set_powered(v: bool) -> void:
	if powered == v:
		return
	powered = v
	_changed()


func set_base_flicker(v: bool) -> void:
	if base_flicker == v:
		return
	base_flicker = v
	_changed()


func pulse_flicker(seconds: float) -> void:
	temp_flicker = maxf(temp_flicker, seconds)
	_changed()


func tidy() -> void:
	## Housekeeping puts it back the way it was found.
	has_tube = home_tube
	powered = home_powered
	temp_flicker = 0.0
	_changed()


func _changed() -> void:
	if recompute():
		EventBus.light_changed.emit(self, state)
		if chunk != null and is_instance_valid(chunk):
			chunk.call("mark_panels_dirty")


func state_name() -> String:
	match state:
		State.ON: return "on"
		State.FLICKER: return "flicker"
	return "dead"
