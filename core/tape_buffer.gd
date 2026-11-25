class_name TapeBuffer
extends RefCounted
## A ring buffer of small RGB frames (SPEC 12.5): the last N seconds of what the guest's camera saw.
## Frames are raw RGB8 byte arrays at TapeBuffer.W x H, so playback is just "upload bytes to a texture".

const W := 128
const H := 96
const FRAME_BYTES := W * H * 3

var capacity: int = 450                 ## frames (45 s at 10 fps)
var fps: float = 10.0
var _frames: Array[PackedByteArray] = []
var _head: int = 0                      ## next write index once full
var count: int = 0


func _init(p_capacity: int = 450, p_fps: float = 10.0) -> void:
	capacity = maxi(2, p_capacity)
	fps = p_fps
	_frames.resize(capacity)


func clear() -> void:
	count = 0
	_head = 0
	for i in capacity:
		_frames[i] = PackedByteArray()


func push_image(img: Image) -> void:
	if img.get_width() != W or img.get_height() != H:
		img = img.duplicate()
		img.resize(W, H, Image.INTERPOLATE_NEAREST)
	if img.get_format() != Image.FORMAT_RGB8:
		img = img.duplicate() if img.get_format() != Image.FORMAT_RGB8 else img
		img.convert(Image.FORMAT_RGB8)
	push_bytes(img.get_data())


func push_bytes(bytes: PackedByteArray) -> void:
	_frames[_head] = bytes
	_head = (_head + 1) % capacity
	count = mini(count + 1, capacity)


func frame_count() -> int:
	return count


func seconds() -> float:
	return float(count) / fps


func get_frame(i: int) -> PackedByteArray:
	## i = 0 is the OLDEST frame still held, count-1 the newest.
	if i < 0 or i >= count:
		return PackedByteArray()
	var start := (_head - count + capacity * 2) % capacity
	return _frames[(start + i) % capacity]


func last_frames(seconds_back: float) -> Array[PackedByteArray]:
	var n := mini(count, int(ceil(seconds_back * fps)))
	var out: Array[PackedByteArray] = []
	for i in range(count - n, count):
		out.append(get_frame(i))
	return out


static func to_image(bytes: PackedByteArray) -> Image:
	return Image.create_from_data(W, H, false, Image.FORMAT_RGB8, bytes)


## --- persistence (own-death tapes, SPEC 4.11) ---

static func pack(frames: Array[PackedByteArray], p_fps: float) -> PackedByteArray:
	var raw := PackedByteArray()
	for f in frames:
		raw.append_array(f)
	var out := PackedByteArray()
	out.resize(8)
	out.encode_u32(0, frames.size())
	out.encode_u32(4, int(p_fps))
	out.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return out


static func unpack(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 8:
		return {"frames": [], "fps": 10}
	var n := int(bytes.decode_u32(0))
	var f := int(bytes.decode_u32(4))
	var raw := bytes.slice(8).decompress(n * FRAME_BYTES, FileAccess.COMPRESSION_ZSTD)
	var frames: Array[PackedByteArray] = []
	for i in n:
		frames.append(raw.slice(i * FRAME_BYTES, (i + 1) * FRAME_BYTES))
	return {"frames": frames, "fps": f}
