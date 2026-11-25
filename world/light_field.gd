class_name LightField
extends Node
## Paints the ceiling light cells into a small R8 texture (one texel per tile, bilinear) that every
## world material samples (see shaders/world_common.gdshaderinc). This is the cheap "fake lighting"
## that lets dozens of cells read correctly with <= 6 real lights (SPEC 9.3).
## Also animates cell brightness (fades, flicker) and flicker panel emission.

const N := 64                                  ## window size in tiles (80 m)
const RECENTER_MARGIN := 14                    ## recenter when the focus gets this close to the edge
const FADE_ON := 7.0
const FADE_OFF := 11.0
const HEADROOM := 1.25                         ## texture 1.0 = this much light; lets a cell "surge" past normal (the Hum's INVERTED tell)

var texture: ImageTexture
var image: Image
var origin: Vector2i = Vector2i(-N / 2, -N / 2)    ## world tile of texel (0, 0)
var cells: Array[LightCell] = []
var focus_tile: Vector2i = Vector2i.ZERO
var dirty: bool = true
var _buf: PackedFloat32Array = PackedFloat32Array()
var _bytes: PackedByteArray = PackedByteArray()
var _time: float = 0.0
var _accum: float = 0.0
var _dim_cache: float = 0.0
var enabled: bool = true


func _init() -> void:
	_buf.resize(N * N)
	_bytes.resize(N * N)
	image = Image.create_empty(N, N, false, Image.FORMAT_R8)
	texture = ImageTexture.create_from_image(image)
	_push_rect()
	MaterialLibrary.set_field(texture, _rect())


func register_chunk(chunk: Chunk) -> void:
	for c in chunk.cells:
		if not cells.has(c):
			cells.append(c)
	dirty = true


func unregister_chunk(chunk: Chunk) -> void:
	for c in chunk.cells:
		cells.erase(c)
	dirty = true


func clear() -> void:
	cells.clear()
	dirty = true


func set_focus(tile: Vector2i) -> void:
	focus_tile = tile
	var local := tile - origin
	if local.x < RECENTER_MARGIN or local.y < RECENTER_MARGIN \
			or local.x > N - RECENTER_MARGIN or local.y > N - RECENTER_MARGIN:
		origin = tile - Vector2i(N / 2, N / 2)
		_push_rect()
		dirty = true


func _rect() -> Vector4:
	var T := GameScale.TILE
	return Vector4(origin.x * T, origin.y * T, 1.0 / (N * T), 1.0 / (N * T))


func _push_rect() -> void:
	MaterialLibrary.set_field(texture, _rect())


func flicker_wave(t: float, seed_value: float, amplitude: float) -> float:
	## Irregular dips at well under 3 Hz (SPEC 11.3). amplitude is how deep the dips go.
	var tt := t * 2.1 + seed_value
	var n := sin(tt * 1.3) * sin(tt * 0.83 + 1.7) + sin(tt * 4.4 + seed_value) * 0.3
	var dip := smoothstep(0.35, 0.8, n)
	return 1.0 - dip * amplitude


func _process(delta: float) -> void:
	if not enabled:
		return
	_time += delta
	var amp := 0.35 if Settings.safe_flicker else 0.85
	var any_change := false
	for c in cells:
		if c.temp_flicker > 0.0:
			c.temp_flicker = maxf(0.0, c.temp_flicker - delta)
			if c.temp_flicker == 0.0:
				c._changed()
		var target := 0.0
		match c.state:
			LightCell.State.ON:
				target = 1.0
			LightCell.State.FLICKER:
				target = flicker_wave(_time, float(c.index) * 3.7 + float(c.tile.x) * 0.31 + float(c.tile.y) * 0.17, amp)
		var b := c.brightness
		if c.state == LightCell.State.FLICKER:
			b = target
		else:
			b = move_toward(b, target, (FADE_ON if target > b else FADE_OFF) * delta)
		if not is_equal_approx(b, c.brightness):
			c.brightness = b
			any_change = true
	if any_change:
		dirty = true
	# the shared flicker-panel materials pulse together
	var fw := flicker_wave(_time, 1.0, amp)
	for m in MaterialLibrary.flicker_materials():
		m.set_shader_parameter("emission_boost", 0.1 + 0.55 * fw)
		m.set_shader_parameter("tint", Color(0.55 + 0.45 * fw, 0.55 + 0.45 * fw, 0.55 + 0.45 * fw))
	_accum += delta
	if dirty and _accum >= 0.04:
		_accum = 0.0
		dirty = false
		_rebuild()


func _rebuild() -> void:
	_buf.fill(0.0)
	for c in cells:
		var b := c.brightness + (c.boost if c.brightness > 0.5 else 0.0)
		if b <= 0.002:
			continue
		for t: Vector2i in c.footprint:
			var lx: int = t.x - origin.x
			var ly: int = t.y - origin.y
			if lx < 0 or ly < 0 or lx >= N or ly >= N:
				continue
			var idx := ly * N + lx
			_buf[idx] = minf(HEADROOM, _buf[idx] + b * float(c.footprint[t]))
	for i in N * N:
		_bytes[i] = int(clampf(_buf[i] / HEADROOM, 0.0, 1.0) * 255.0)
	image.set_data(N, N, false, Image.FORMAT_R8, _bytes)
	texture.update(image)


func level_at_tile(t: Vector2i) -> float:
	## Light level 0..1 at a world tile (what the player is standing in), for gameplay and tests.
	var lx := t.x - origin.x
	var ly := t.y - origin.y
	if lx < 0 or ly < 0 or lx >= N or ly >= N:
		return 0.0
	var s := 0.0
	for c in cells:
		if c.footprint.has(t):
			s += c.brightness * float(c.footprint[t])
	return minf(1.0, s)
