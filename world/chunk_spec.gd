class_name ChunkSpec
extends RefCounted
## A room chunk authored as ASCII (res://content/chunks/**/*.chunk) and parsed here (SPEC 8.2).
## The chunk is a grid of tiles (TILE = 1.25 m). Walls are thin planes on the edge between an open
## tile and a non-open tile, so a chunk is just "which tiles are open" plus markers.
##
## LEGEND (one character per tile)
##   #  solid wall            (space) void            P  pillar (solid tile, wall texture on all faces)
##   .  floor                 ,  floor, worn variant   o  floor with an OPEN ceiling tile (the void)
##   |  floor + thin wall on its EAST edge    _  floor + thin wall on its SOUTH edge    +  both
##      (thin full-height partitions between open tiles: cubicles, glass offices, pillar lines)
##   L  light panel, lit      l  light panel, dead (no tube)     S  switchable-circuit panel (lit)
##   ^ > v <   exit door socket on the N / E / S / W edge of this tile
##   1 2 3 4   entry socket (where we arrive from) on the N / E / S / W edge of this tile
##   Slots (open tiles carrying an object):
##   g graffiti(wall)  f floor mark  c ceiling mark  t tape pickup  i loot item  u entity anchor
##   h desk-hide  H closet-hide(wall)  d desk  k cabinet(wall)  b breaker(wall)  s switch(wall)
##   w water cooler(wall)  x suggestion box(wall)  r charger(wall)  m PA horn(wall)
##   a plant  z boxes  q chair  p poster(wall)  e vent grille(wall)  n note/sign(wall)
##   Y stanchion  J ticket dispenser(wall)  W wet-floor sign  T room-service tray  C clock(wall)
##
## Header (before a line containing only ---):  id, beat, floors, tags, intensity, weight,
## max_per_floor, ceiling (small|medium|large), floor_mat, wall_mat, floor_alt_mat, decay.

const DIRS_ORDER: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

const GEOMETRY_GLYPHS := "# .,oPLlS|_+"
const EXIT_GLYPHS := {"^": Vector2i(0, -1), ">": Vector2i(1, 0), "v": Vector2i(0, 1), "<": Vector2i(-1, 0)}
const ENTRY_GLYPHS := {"1": Vector2i(0, -1), "2": Vector2i(1, 0), "3": Vector2i(0, 1), "4": Vector2i(-1, 0)}

## glyph -> {kind, wall}. wall = wall-mounted (needs an adjacent solid edge; faces into the room).
const SLOT_TABLE := {
	"g": {"kind": &"graffiti", "wall": true},
	"f": {"kind": &"floor_mark", "wall": false},
	"c": {"kind": &"ceiling_mark", "wall": false},
	"t": {"kind": &"tape", "wall": false},
	"i": {"kind": &"loot", "wall": false},
	"u": {"kind": &"anchor", "wall": false},
	"h": {"kind": &"hide_desk", "wall": false},
	"H": {"kind": &"hide_closet", "wall": true},
	"d": {"kind": &"desk", "wall": false},
	"k": {"kind": &"cabinet", "wall": true},
	"b": {"kind": &"breaker", "wall": true},
	"s": {"kind": &"switch", "wall": true},
	"w": {"kind": &"cooler", "wall": true},
	"x": {"kind": &"suggestion_box", "wall": true},
	"r": {"kind": &"charger", "wall": true},
	"m": {"kind": &"pa_horn", "wall": true},
	"a": {"kind": &"plant", "wall": false},
	"z": {"kind": &"boxes", "wall": false},
	"q": {"kind": &"chair", "wall": false},
	"p": {"kind": &"poster", "wall": true},
	"e": {"kind": &"vent", "wall": true},
	"n": {"kind": &"sign", "wall": true},
	"Y": {"kind": &"stanchion", "wall": false},
	"J": {"kind": &"number_dispenser", "wall": true},
	"W": {"kind": &"wet_sign", "wall": false},
	"T": {"kind": &"tray", "wall": false},
	"C": {"kind": &"clock", "wall": true},
}


class SocketDef extends RefCounted:
	var tile: Vector2i = Vector2i.ZERO      ## open tile the edge belongs to
	var dir: Vector2i = Vector2i.ZERO       ## outward direction of that edge
	var kind: StringName = &"exit"          ## &"exit" | &"entry"
	var index: int = 0                      ## order within its kind (row-major)


class SlotDef extends RefCounted:
	var kind: StringName = &""
	var glyph: String = ""
	var tile: Vector2i = Vector2i.ZERO
	var wall_dir: Vector2i = Vector2i.ZERO  ## toward the wall it is mounted on (zero for floor slots)
	var index: int = 0                      ## order within its kind (row-major)


class PanelDef extends RefCounted:
	var tile: Vector2i = Vector2i.ZERO
	var lit: bool = true
	var circuit: StringName = &""           ## &"" = mains, &"S" = switchable circuit of this chunk


var id: StringName = &""
var rows: PackedStringArray = PackedStringArray()
var width: int = 0
var height: int = 0
var beat: StringName = &"choice"
var floors: Array[StringName] = []
var tags: Array[StringName] = []
var intensity: int = 0
var weight: float = 1.0
var max_per_floor: int = 99
var ceiling: StringName = &"medium"
var floor_mat: StringName = &""
var floor_alt_mat: StringName = &""
var wall_mat: StringName = &""
var decay: int = 0
var source_path: String = ""

var open: Dictionary = {}                  ## Vector2i -> glyph (all open tiles)
var ceiling_holes: Dictionary = {}         ## Vector2i -> true
var pillars: Dictionary = {}               ## Vector2i -> true (solid P tiles)
var thin_walls: Dictionary = {}            ## edge_key -> true (stored from BOTH sides of the edge)
var exits: Array[SocketDef] = []
var entries: Array[SocketDef] = []
var panels: Array[PanelDef] = []
var slots: Array[SlotDef] = []
var errors: PackedStringArray = PackedStringArray()


static func parse_text(text: String, source: String = "") -> ChunkSpec:
	var spec := ChunkSpec.new()
	spec.source_path = source
	var lines := text.split("\n")
	var in_body := false
	var body: PackedStringArray = PackedStringArray()
	for raw in lines:
		var line := raw.trim_suffix("\r")
		if not in_body:
			if line.strip_edges() == "---":
				in_body = true
				continue
			var s := line.strip_edges()
			if s == "" or s.begins_with(";") or s.begins_with("#"):
				continue
			var idx := s.find(":")
			if idx < 0:
				spec.errors.append("bad header line: %s" % s)
				continue
			spec._set_header(s.substr(0, idx).strip_edges(), s.substr(idx + 1).strip_edges())
		else:
			if line.strip_edges().begins_with(";;"):
				continue
			body.append(line)
	while body.size() > 0 and body[body.size() - 1].strip_edges() == "":
		body.remove_at(body.size() - 1)
	spec.rows = body
	spec._parse_grid()
	return spec


static func load_file(path: String) -> ChunkSpec:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		var bad := ChunkSpec.new()
		bad.errors.append("cannot open %s" % path)
		return bad
	return parse_text(f.get_as_text(), path)


func _set_header(key: String, value: String) -> void:
	match key:
		"id": id = StringName(value)
		"beat": beat = StringName(value)
		"floors": floors = _names(value)
		"tags": tags = _names(value)
		"intensity": intensity = int(value)
		"weight": weight = float(value)
		"max_per_floor": max_per_floor = int(value)
		"ceiling": ceiling = StringName(value)
		"floor_mat": floor_mat = StringName(value)
		"floor_alt_mat": floor_alt_mat = StringName(value)
		"wall_mat": wall_mat = StringName(value)
		"decay": decay = int(value)
		_: errors.append("unknown header key '%s'" % key)


static func _names(value: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for part in value.split(","):
		var p := part.strip_edges()
		if p != "":
			out.append(StringName(p))
	return out


func _parse_grid() -> void:
	height = rows.size()
	width = 0
	for r in rows:
		width = maxi(width, r.length())
	if id == &"":
		errors.append("missing id")
	if height == 0:
		errors.append("empty layout")
		return
	var ex_i := 0
	var en_i := 0
	var slot_counts: Dictionary = {}
	for y in height:
		var row := rows[y]
		for x in width:
			var g := row[x] if x < row.length() else " "
			var t := Vector2i(x, y)
			if g == "P":
				pillars[t] = true
				continue
			if g == " " or g == "#":
				continue
			if EXIT_GLYPHS.has(g):
				open[t] = g
				var s := SocketDef.new()
				s.tile = t
				s.dir = EXIT_GLYPHS[g]
				s.kind = &"exit"
				s.index = ex_i
				ex_i += 1
				exits.append(s)
			elif ENTRY_GLYPHS.has(g):
				open[t] = g
				var s2 := SocketDef.new()
				s2.tile = t
				s2.dir = ENTRY_GLYPHS[g]
				s2.kind = &"entry"
				s2.index = en_i
				en_i += 1
				entries.append(s2)
			elif g == "." or g == ",":
				open[t] = g
			elif g == "o":
				open[t] = g
				ceiling_holes[t] = true
			elif g == "|" or g == "_" or g == "+":
				open[t] = g
				if g == "|" or g == "+":
					thin_walls[edge_key(t, Vector2i(1, 0))] = true
					thin_walls[edge_key(t + Vector2i(1, 0), Vector2i(-1, 0))] = true
				if g == "_" or g == "+":
					thin_walls[edge_key(t, Vector2i(0, 1))] = true
					thin_walls[edge_key(t + Vector2i(0, 1), Vector2i(0, -1))] = true
			elif g == "L" or g == "l" or g == "S":
				open[t] = g
				var p := PanelDef.new()
				p.tile = t
				p.lit = g != "l"
				p.circuit = &"S" if g == "S" else &""
				panels.append(p)
			elif SLOT_TABLE.has(g):
				open[t] = g
				var info: Dictionary = SLOT_TABLE[g]
				var sl := SlotDef.new()
				sl.kind = info["kind"]
				sl.glyph = g
				sl.tile = t
				var n: int = int(slot_counts.get(sl.kind, 0))
				sl.index = n
				slot_counts[sl.kind] = n + 1
				slots.append(sl)
			else:
				errors.append("unknown glyph '%s' at (%d,%d)" % [g, x, y])
	# wall-mounted slots need a wall to hang on
	for sl in slots:
		var info: Dictionary = SLOT_TABLE[sl.glyph]
		if bool(info["wall"]):
			sl.wall_dir = _find_wall_dir(sl.tile)
			if sl.wall_dir == Vector2i.ZERO:
				errors.append("wall slot '%s' at %s has no adjacent wall" % [sl.glyph, sl.tile])
	_validate()


func is_open(t: Vector2i) -> bool:
	return open.has(t)


func has_thin_wall(t: Vector2i, d: Vector2i) -> bool:
	return thin_walls.has(edge_key(t, d))


func can_step(t: Vector2i, d: Vector2i) -> bool:
	## True when you can walk from open tile t to its neighbour in direction d (inside this chunk).
	return open.has(t + d) and not thin_walls.has(edge_key(t, d))


func is_solid_at(t: Vector2i) -> bool:
	return not open.has(t)


func socket_edges() -> Dictionary:
	## "x,y,dx,dy" -> SocketDef, for every socket edge (used so no wall is built there).
	var out := {}
	for s in exits:
		out[edge_key(s.tile, s.dir)] = s
	for s in entries:
		out[edge_key(s.tile, s.dir)] = s
	return out


static func edge_key(t: Vector2i, d: Vector2i) -> String:
	return "%d,%d,%d,%d" % [t.x, t.y, d.x, d.y]


func _find_wall_dir(t: Vector2i) -> Vector2i:
	var se := socket_edges()
	for d in DIRS_ORDER:
		if not open.has(t + d) and not se.has(edge_key(t, d)):
			return d
	return Vector2i.ZERO


func _validate() -> void:
	if open.is_empty():
		errors.append("no open tiles")
		return
	# sockets must point at a non-open neighbour
	for s in exits + entries:
		if open.has(s.tile + s.dir):
			errors.append("socket at %s faces another open tile" % s.tile)
	# open tiles must be one connected region
	var start: Vector2i = open.keys()[0]
	var seen := {start: true}
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in DIRS_ORDER:
			var n := c + d
			if open.has(n) and not seen.has(n) and not thin_walls.has(edge_key(c, d)):
				seen[n] = true
				stack.append(n)
	if seen.size() != open.size():
		errors.append("open tiles are not one connected region (%d of %d reachable)" % [seen.size(), open.size()])
	if ceiling != &"small" and ceiling != &"medium" and ceiling != &"large":
		errors.append("bad ceiling '%s'" % ceiling)


func slots_of(kind: StringName) -> Array[SlotDef]:
	var out: Array[SlotDef] = []
	for s in slots:
		if s.kind == kind:
			out.append(s)
	return out


func bounds() -> Rect2i:
	return Rect2i(0, 0, width, height)


func footprint_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for t: Vector2i in open:
		out.append(t)
	return out


func is_valid() -> bool:
	return errors.is_empty()


func debug_dump() -> String:
	return "\n".join(rows)
