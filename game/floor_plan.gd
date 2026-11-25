class_name FloorPlan
extends RefCounted
## One floor, planned up front and built lazily (SPEC 8.1): the beat grammar is instantiated per seed, door
## types/tells and evidence are decided here (Fairness Doctrine 1: tells honestly correlate with what is
## behind the door), and chunks are built only when a door opens. This object is the ChunkStreamer provider.

const SIDE_BASE := 100                       ## chunk beat_index of side rooms = SIDE_BASE + n

class BeatPlan extends RefCounted:
	var index: int = 0
	var kind: StringName = &"choice"
	var spec: ChunkSpec = null
	var main: bool = true
	var role: StringName = &""               ## side rooms: closet | vault | breaker
	var evidence: Array[EvidenceDef] = []
	var loot: Array[StringName] = []
	var forward_exit: int = -1
	var exits: Dictionary = {}               ## exit index -> exit plan Dictionary
	var visits: int = 0
	var decay: int = 0
	var entry_socket: int = -1               ## planned entry socket id (100 + entry index) when the main line was laid out
	var own_tape: Dictionary = {}            ## vault only: one of the guest's own old death tapes (SPEC 4.11), or {}

	func label() -> String:
		return "%s#%d(%s)" % [kind, index, spec.id if spec != null else "?"]


var def: FloorDef
var truth: int = RunState.Truth.HOLDS
var theme: FloorTheme
var streams: RngStreams
var mastered: bool = false                   ## floor already cleared: P3 graffiti is repainted away (SPEC 4.8)
var guided: bool = false

var main_beats: Array[BeatPlan] = []
var side_beats: Array[BeatPlan] = []
var by_index: Dictionary = {}                ## int -> BeatPlan
var exam_index: int = -1
var initial_circuits: Dictionary = {}        ## circuit key -> bool
var populator: Callable = Callable()         ## (chunk, plan_beat) -> void ; set by the FloorSession
var used_count: Dictionary = {}              ## spec id -> int
var _next_side := 0


static func create(p_def: FloorDef, p_truth: int, p_streams: RngStreams, opts: Dictionary = {}) -> FloorPlan:
	var p := FloorPlan.new()
	p.def = p_def
	p.truth = p_truth
	p.streams = p_streams
	p.theme = Themes.get_theme(p_def.theme_id)
	p.mastered = bool(opts.get("mastered", false))
	p.guided = bool(opts.get("guided", false))
	p._plan_main()
	p._assign_evidence()
	p._layout_main_line()
	return p


func rng_for(key: String) -> RandomNumberGenerator:
	## Independent of how much anything else has consumed: layout decisions never depend on the player's path.
	return streams.derive(&"layout", key.hash())


# --- planning -------------------------------------------------------------------------------

func _plan_main() -> void:
	var prev: StringName = &""
	var i := 0
	for kind in def.beat_grammar:
		var bp := BeatPlan.new()
		bp.index = i
		bp.kind = kind
		by_index[i] = bp
		main_beats.append(bp)
		if kind == &"exam":
			exam_index = i
		i += 1
	# specs are picked after kinds are known so the evidence assignment can constrain them
	var lab_done := false
	for bp in main_beats:
		var r := rng_for("beat:%d" % bp.index)
		var tags: Array = []
		if bp.kind == def.lab_beat and not lab_done:
			tags = [&"lab"]            # the authored Test room (SPEC App. B), when the floor has one
			lab_done = true
		bp.spec = _pick_spec(bp.kind, [], tags, r, prev)
		prev = bp.spec.id if bp.spec != null else &""
		bp.decay = clampi(int(float(bp.index) / maxf(1.0, float(main_beats.size())) * 2.2), 0, 2)
		_roll_loot(bp, r)
	_plan_exits()


func _pick_spec(kind: StringName, need_slots: Array, need_tags: Array, r: RandomNumberGenerator, avoid: StringName = &"") -> ChunkSpec:
	var cands: Array[ChunkSpec] = []
	var weights: Array = []
	for s in ChunkLibrary.pool(def.id, kind):
		if s.id == avoid and ChunkLibrary.pool(def.id, kind).size() > 1:
			continue
		if int(used_count.get(s.id, 0)) >= s.max_per_floor:
			continue
		var ok := true
		for sk in need_slots:
			if ChunkLibrary.slot_count(s, sk) == 0:
				ok = false
		for t in need_tags:
			if not s.tags.has(t):
				ok = false
		if not ok:
			continue
		cands.append(s)
		weights.append(maxf(0.01, s.weight))
	if cands.is_empty():
		# relax: ignore slot/tag needs rather than leave the floor without a room
		for s in ChunkLibrary.pool(def.id, kind):
			cands.append(s)
			weights.append(maxf(0.01, s.weight))
	if cands.is_empty():
		return null
	var pick := cands[RngStreams.weighted_index(r, weights)]
	used_count[pick.id] = int(used_count.get(pick.id, 0)) + 1
	return pick


func _roll_loot(bp: BeatPlan, r: RandomNumberGenerator) -> void:
	bp.loot.clear()
	match bp.kind:
		&"choice", &"long":
			var roll := r.randf()
			if roll < 0.40:
				bp.loot.append(&"battery")
			elif roll < 0.60:
				bp.loot.append(&"bulb")
			elif roll < 0.68:
				bp.loot.append(&"fuse")
		&"exam":
			if r.randf() < 0.25:
				bp.loot.append(&"battery")


func _assign_evidence() -> void:
	var pieces := def.evidence_for(truth)
	if pieces.is_empty():
		return
	var p3: Array[EvidenceDef] = []
	var p2: Array[EvidenceDef] = []
	var p1: Array[EvidenceDef] = []
	for e in pieces:
		match e.prominence:
			3: p3.append(e)
			2: p2.append(e)
			_: p1.append(e)
	var density: float = Settings.evidence_density
	var ordered: Array[EvidenceDef] = []
	# "Sparse": no plain-language graffiti when the floor still meets Doctrine 3 without it (same as a repainted floor)
	if (mastered or density < 1.0) and not guided and p2.size() >= 2:
		ordered.append_array(p2)            # "the house repaints": no plain-language graffiti on a cleared floor
		# (only when the floor still meets Doctrine 3 without it; floors with one prop-state piece keep the graffiti)
	else:
		ordered.append_array(p3)
		ordered.append_array(p2)
	var pre: Array[BeatPlan] = []
	for bp in main_beats:
		if (exam_index < 0 or bp.index < exam_index) and (bp.kind == &"choice" or bp.kind == &"long"):
			pre.append(bp)
	if pre.is_empty():
		pre = main_beats.duplicate()
	for i in ordered.size():
		var host: BeatPlan = pre[i % pre.size()]
		host.evidence.append(ordered[i])
		_ensure_slots(host, ordered[i])
	# "Generous" / "Plentiful": extra copies of the same TRUE evidence in other rooms before the exam. Copies never
	# re-pick a room (the first copy already did); a room that cannot host one simply gets none.
	var copies := clampi(1 + int(floorf((density - 1.0) / 0.5)), 1, 3)
	if copies > 1 and pre.size() > 1:
		for i in ordered.size():
			var placed := 1
			var k := 1
			while placed < copies and k < pre.size():
				var extra: BeatPlan = pre[(i + k) % pre.size()]
				k += 1
				if extra.evidence.has(ordered[i]) or not _spec_can_host(extra.spec, ordered[i]):
					continue
				extra.evidence.append(ordered[i])
				placed += 1
	for e in p1:
		# Echo tapes live in side rooms (vaults); remembered here, placed when a vault is built
		tape_evidence.append(e)


var tape_evidence: Array[EvidenceDef] = []
var layout_ok := false                       ## the main line was laid out with no room overlapping another
var layout_nodes := 0                        ## search effort (tests / tuning)


# --- main-line layout (so the forward path can never fold back onto itself) --------------------

const LAYOUT_BUDGET := 20000


func _layout_main_line() -> void:
	## Rooms are placed by door position and socket, so the main line's geometry is fully determined by which
	## exit leads on and which entry the next room is entered through. Search for a choice of those (and, when
	## needed, an interchangeable room) such that no two main-line rooms overlap. Without this, a long hall can
	## be walked back into by a later room and the forward door never builds.
	var n := main_beats.size()
	layout_ok = false
	layout_nodes = 0
	if n < 2 or main_beats[0].spec == null:
		return
	var occ := {}
	for t in ChunkPlacer.world_tiles(main_beats[0].spec, 0, Vector2i.ZERO):
		occ[t] = true
	var chosen: Array[Dictionary] = [{"spec": main_beats[0].spec, "rot": 0, "offset": Vector2i.ZERO, "entry": -1, "exit": -1}]
	if not _layout_step(1, chosen, occ):
		return
	layout_ok = true
	for i in n:
		var c: Dictionary = chosen[i]
		var bp := main_beats[i]
		if bp.spec != c["spec"]:
			used_count[bp.spec.id] = maxi(0, int(used_count.get(bp.spec.id, 1)) - 1)
			used_count[(c["spec"] as ChunkSpec).id] = int(used_count.get((c["spec"] as ChunkSpec).id, 0)) + 1
			bp.spec = c["spec"]
		bp.entry_socket = -1 if int(c["entry"]) < 0 else 100 + int(c["entry"])
		if i + 1 < n:
			bp.forward_exit = int((chosen[i + 1] as Dictionary)["exit"])
		else:
			bp.forward_exit = -1


func _layout_step(i: int, chosen: Array[Dictionary], occ: Dictionary) -> bool:
	if i >= main_beats.size():
		return true
	var prev: Dictionary = chosen[i - 1]
	var prev_spec: ChunkSpec = prev["spec"]
	var bp := main_beats[i]
	var r := rng_for("layout:%d" % i)
	var specs: Array[ChunkSpec] = [bp.spec]
	for alt in RngStreams.shuffled(r, _layout_alternates(bp)):
		specs.append(alt)
	var preferred_exit := main_beats[i - 1].forward_exit
	var exits: Array = range(prev_spec.exits.size())
	exits = RngStreams.shuffled(r, exits)
	if preferred_exit >= 0 and exits.has(preferred_exit):
		exits.erase(preferred_exit)
		exits.push_front(preferred_exit)
	for sp: ChunkSpec in specs:
		if sp.entries.is_empty() or (i < main_beats.size() - 1 and sp.exits.is_empty()):
			continue
		var entries: Array = RngStreams.shuffled(r, range(sp.entries.size()))
		for ex_i in exits:
			var se: ChunkSpec.SocketDef = prev_spec.exits[ex_i]
			var door_tile := ChunkPlacer.tile_to_world(se.tile, int(prev["rot"]), prev["offset"])
			var wdir := Dir.rot(se.dir, int(prev["rot"]))
			var beyond := door_tile + wdir
			for en_i in entries:
				layout_nodes += 1
				if layout_nodes > LAYOUT_BUDGET:
					return false
				var pl := ChunkPlacer.placement_for_socket(sp.entries[en_i], beyond, -wdir)
				var tiles := ChunkPlacer.world_tiles(sp, int(pl["rot"]), pl["offset"])
				var clash := false
				for t in tiles:
					if occ.has(t):
						clash = true
						break
				if clash:
					continue
				for t in tiles:
					occ[t] = true
				chosen.append({"spec": sp, "rot": pl["rot"], "offset": pl["offset"], "entry": en_i, "exit": ex_i})
				if _layout_step(i + 1, chosen, occ):
					return true
				chosen.pop_back()
				for t in tiles:
					occ.erase(t)
	return false


func _layout_alternates(bp: BeatPlan) -> Array[ChunkSpec]:
	## Rooms that can stand in for a beat's planned room: same kind, same role tags, can host the beat's evidence,
	## and (for the exam) at least as many exits and every tag the planned room has.
	var out: Array[ChunkSpec] = []
	var roles: Array[StringName] = []
	for t in ROLE_TAGS:
		if bp.spec.tags.has(t):
			roles.append(t)
	for sp in ChunkLibrary.pool(def.id, bp.kind):
		if sp.id == bp.spec.id or sp.entries.is_empty():
			continue
		if int(used_count.get(sp.id, 0)) >= sp.max_per_floor:
			continue
		if not roles.all(func(t): return sp.tags.has(t)):
			continue
		if not bp.evidence.all(func(e): return _spec_can_host(sp, e)):
			continue
		if bp.kind == &"exam" and (sp.exits.size() < bp.spec.exits.size() or not bp.spec.tags.all(func(t): return sp.tags.has(t))):
			continue
		out.append(sp)
	return out


func _ensure_slots(bp: BeatPlan, e: EvidenceDef) -> void:
	## Re-pick the host's room when it cannot hold the evidence (needs a graffiti slot / the right panels).
	if _spec_can_host(bp.spec, e):
		return
	var r := rng_for("rehost:%d:%s" % [bp.index, e.id])
	used_count[bp.spec.id] = maxi(0, int(used_count.get(bp.spec.id, 1)) - 1)
	var need: Array = []
	if e.kind == EvidenceDef.Kind.GRAFFITI:
		need.append(&"graffiti")
	for _try in 12:
		var cand := _pick_spec(bp.kind, need, [], r)
		if cand != null and _spec_can_host(cand, e):
			bp.spec = cand
			return
	# nothing suitable: keep the room (validate() will flag it)


func _spec_can_host(spec: ChunkSpec, e: EvidenceDef) -> bool:
	if e.kind == EvidenceDef.Kind.GRAFFITI:
		return ChunkLibrary.slot_count(spec, &"graffiti") > 0
	var recipe := String(e.params.get("recipe", ""))
	var stats := ChunkLibrary.panel_stats(spec)
	match recipe:
		"claw":
			return (stats["dead"] + stats["switchable"] > 0) if String(e.params.get("under", "")) == "dead" else (stats["lit"] > 0)
		"dust":
			return stats["dead"] + stats["switchable"] > 0
		"scorch":
			return stats["lit"] > 0
		_:
			return EvidenceRecipes.can_host(spec, e)


func _plan_exits() -> void:
	for bp in main_beats:
		if bp.spec == null:
			continue
		var n := bp.spec.exits.size()
		if n == 0:
			continue
		var r := rng_for("fwd:%d" % bp.index)
		# the forward door is the one that leads to the next main beat (the last beat has none)
		bp.forward_exit = r.randi() % n if bp.index < main_beats.size() - 1 else -1


# --- the provider interface (ChunkStreamer) -------------------------------------------------

func theme_for(_beat: int) -> FloorTheme:
	return theme


func first_spec() -> ChunkSpec:
	return main_beats[0].spec


func beat_by_index(i: int) -> BeatPlan:
	return by_index.get(i, null)


func door_type_for(chunk: Chunk, socket: ChunkSpec.SocketDef) -> Dictionary:
	if socket.kind == &"entry":
		return {"type": &"stuck"}
	var bp: BeatPlan = beat_by_index(chunk.beat_index)
	if bp == null:
		return {"type": &"unit"}
	if bp.exits.has(socket.index):
		return bp.exits[socket.index]
	var ex := _make_exit(bp, socket.index)
	bp.exits[socket.index] = ex
	return ex


func _make_exit(bp: BeatPlan, idx: int) -> Dictionary:
	var r := rng_for("exit:%d:%d" % [bp.index, idx])
	var out := {"role": &"forward", "type": &"unit", "tells": [], "dest": -1}
	if not bp.main:
		return out        # side rooms are dead ends
	var is_forward := idx == bp.forward_exit
	if is_forward:
		var nxt: BeatPlan = main_beats[bp.index + 1]
		out["role"] = &"forward"
		out["dest"] = nxt.index
		out["type"] = _forward_door(bp, nxt, r)
	else:
		var role := _side_role(bp, idx, r)
		if role == &"shortcut":
			var tgt_i := mini(bp.index + 2, main_beats.size() - 2)
			if tgt_i <= bp.index + 1 or main_beats[tgt_i].kind == &"departure":
				role = &"closet"
			else:
				out["dest"] = tgt_i
				out["type"] = &"fire" if r.randf() < def.fire_door_chance else &"boarded"
		out["role"] = role
		if role != &"shortcut":
			var sb := _new_side(role, r)
			out["dest"] = sb.index
			match role:
				&"vault": out["type"] = &"management" if r.randf() < 0.6 else &"management_light"
				&"breaker": out["type"] = &"quiet"
				_: out["type"] = &"quiet" if r.randf() < 0.7 else &"unit"
	out["tells"] = _tells_for(out, r)
	return out


func _forward_door(from: BeatPlan, to: BeatPlan, r: RandomNumberGenerator) -> StringName:
	if from.kind == &"arrival" or to.kind == &"departure":
		return &"elevator"
	match to.kind:
		&"rest": return &"quiet" if r.randf() < 0.75 else &"unit"
		&"exam": return &"unit"
		_:
			var roll := r.randf()
			return &"unit" if roll < 0.62 else &"quiet"


func _side_role(bp: BeatPlan, idx: int, r: RandomNumberGenerator) -> StringName:
	## Roles for the non-forward doors of a Choice room. The room before the exam offers the Breaker Room
	## (when the floor has one) and a boarded shortcut; earlier ones offer a vault and closets.
	var nxt_kind: StringName = main_beats[bp.index + 1].kind if bp.index + 1 < main_beats.size() else &""
	var taken := 0
	for k in bp.exits:
		taken += 1
	if nxt_kind == &"exam" and def.breaker_room and not _has_role(bp, &"breaker"):
		return &"breaker"
	if bp.kind == &"choice" and bp.index + 2 < main_beats.size() - 1 and not _has_role(bp, &"shortcut") and r.randf() < 0.45 and main_beats[bp.index + 2].kind != &"departure":
		return &"shortcut"
	if not _has_role(bp, &"vault") and not tape_evidence.is_empty() and not _vault_done:
		return &"vault"
	return &"closet" if r.randf() < 0.75 else &"vault"


var _vault_done := false


func _has_role(bp: BeatPlan, role: StringName) -> bool:
	for k in bp.exits:
		if bp.exits[k].get("role", &"") == role:
			return true
	return false


func _new_side(role: StringName, r: RandomNumberGenerator) -> BeatPlan:
	var sb := BeatPlan.new()
	sb.index = SIDE_BASE + _next_side
	_next_side += 1
	sb.kind = &"side"
	sb.main = false
	sb.role = role
	var tags: Array = []
	match role:
		&"breaker": tags = [&"breaker"]
		&"vault": tags = [&"vault"]
		_: tags = [&"closet"]
	sb.spec = _pick_spec(&"side", [], tags, r)
	sb.decay = 1
	if role == &"vault":
		_vault_done = true
		if not tape_evidence.is_empty():
			sb.evidence.append(tape_evidence.pop_front())
		sb.loot.append(&"battery")
		sb.own_tape = _own_tape_for(sb)
	elif role == &"closet":
		var pick := r.randf()
		sb.loot.append(&"crowbar" if pick < 0.25 else (&"bulb" if pick < 0.55 else (&"battery" if pick < 0.85 else &"fuse")))
	by_index[sb.index] = sb
	side_beats.append(sb)
	return sb


const OWN_TAPE_CHANCE := 0.35


func _own_tape_for(sb: BeatPlan) -> Dictionary:
	## SPEC 4.11: one of the guest's own old death tapes may be lying in a vault, but only on a run whose rolled
	## variant is the one that killed them (it is real footage, so it is only ever true). Drawn from its own derived
	## stream: it never disturbs the layout draws, and a save with no deaths changes nothing.
	var matching: Array[Dictionary] = []
	for d in SaveService.deaths_on(def.id):
		var path := String(d.get("tape", ""))
		if int(d.get("truth", -1)) == truth and path != "" and FileAccess.file_exists(path):
			matching.append(d)
	if matching.is_empty():
		return {}
	var r := rng_for("owntape:%d" % sb.index)
	if r.randf() >= OWN_TAPE_CHANCE:
		return {}
	return matching[r.randi() % matching.size()]


func _tells_for(ex: Dictionary, r: RandomNumberGenerator) -> Array:
	var dest: BeatPlan = beat_by_index(int(ex.get("dest", -1)))
	var tells: Array = []
	if dest == null or dest.spec == null:
		return tells
	var stats := ChunkLibrary.panel_stats(dest.spec)
	var total := maxi(1, stats["lit"] + stats["dead"] + stats["switchable"])
	var lit_frac := float(stats["lit"]) / float(total)
	if dest.spec.tags.has(&"lit") or lit_frac >= 0.6:
		tells.append(&"light_under")
	elif dest.spec.tags.has(&"dark") or lit_frac <= 0.25:
		tells.append(&"dark_under")
	if dest.kind == &"rest":
		tells.append(&"muzak")
	if dest.main and dest.kind == &"long":
		tells.append(&"draft")
	if ex.get("type", &"") in [&"boarded", &"fire"]:
		tells.append(&"boards_creak" if ex["type"] == &"boarded" else &"alarm_bar")
	return tells


func resolve(conn: DoorConnection, near_side: Dictionary, far_side: Dictionary) -> Dictionary:
	var far_beat := int(far_side.get("beat", -1))
	if far_beat >= 0:
		return _revisit(far_beat, far_side)
	var ex: Dictionary = conn.plan
	var dest_i := int(ex.get("dest", -1))
	var dest: BeatPlan = beat_by_index(dest_i)
	if dest == null or dest.spec == null:
		return {}
	var entries := dest.spec.entries.size()
	if entries == 0:
		return {}
	var r := rng_for("entry:%d:%d" % [dest.index, dest.visits])
	dest.visits += 1
	var socket := 100 + (r.randi() % entries)
	if dest.entry_socket >= 100 and ex.get("role", &"") == &"forward":
		socket = dest.entry_socket              # the laid-out main line (no overlap by construction)
	return {"spec": dest.spec, "beat": dest.index, "socket": socket, "plan": {"bp": dest, "decay": dest.decay}}


func _revisit(beat_i: int, far_side: Dictionary) -> Dictionary:
	## "The house forgets rooms you aren't using" (SPEC 5.6): going back builds a fresh room of the same kind.
	var old: BeatPlan = beat_by_index(beat_i)
	if old == null:
		return {}
	var r := rng_for("revisit:%d:%d" % [beat_i, old.visits])
	old.visits += 1
	var want_socket := int(far_side.get("socket", 0))
	var cands: Array[ChunkSpec] = []
	for s in ChunkLibrary.pool(def.id, old.kind):
		if s.exits.size() > want_socket and (old.kind != &"side" or s.tags.any(func(t): return old.spec != null and old.spec.tags.has(t))):
			cands.append(s)
	if old.kind == &"side":
		# side rooms are dead ends: they were entered through an entry socket
		cands.clear()
		for s in ChunkLibrary.pool(def.id, &"side"):
			if s.entries.size() > 0 and (old.spec == null or s.tags.any(func(t): return old.spec.tags.has(t))):
				cands.append(s)
		if cands.is_empty():
			return {}
		var pickd := cands[r.randi() % cands.size()]
		return {"spec": pickd, "beat": old.index, "socket": 100, "plan": {"bp": old, "decay": mini(3, old.decay + 1), "fresh": true}}
	if cands.is_empty():
		return {}
	var pick := cands[r.randi() % cands.size()]
	return {"spec": pick, "beat": old.index, "socket": want_socket, "plan": {"bp": old, "decay": mini(3, old.decay + 1), "fresh": true}}


const ROLE_TAGS: Array[StringName] = [&"lab", &"dead_corridor", &"ctl_exam", &"breaker", &"vault", &"closet"]


func fallback_candidates(conn: DoorConnection, _near_side: Dictionary, _far_side: Dictionary, tried: Dictionary) -> Array[Dictionary]:
	## The chosen room overlaps something live. Alternatives, best first: the SAME room through another of its entry
	## sockets (a different rotation often fits), then other rooms of the same kind that can still do the beat's job:
	## they have the planned forward-exit index, can host this beat's evidence, and carry the same role tags.
	## The streamer walks the list until one fits. `tried` = {spec_id: [socket ids already tried]}.
	var out: Array[Dictionary] = []
	var dest: BeatPlan = beat_by_index(int(conn.plan.get("dest", -1)))
	if dest == null or dest.spec == null:
		return out
	var r := rng_for("fallback:%d:%d" % [dest.index, dest.visits])
	dest.visits += 1
	var plan := {"bp": dest, "decay": dest.decay}
	var same: Array[Dictionary] = []
	for i in dest.spec.entries.size():
		if not (tried.get(dest.spec.id, []) as Array).has(100 + i):
			same.append({"spec": dest.spec, "beat": dest.index, "socket": 100 + i, "plan": plan})
	out.append_array(RngStreams.shuffled(r, same))
	var needs_exits := maxi(dest.forward_exit + 1, 0)
	for k in dest.exits:
		needs_exits = maxi(needs_exits, int(k) + 1)
	var roles: Array[StringName] = []
	for t in ROLE_TAGS:
		if dest.spec.tags.has(t):
			roles.append(t)
	var others: Array[Dictionary] = []
	for sp in ChunkLibrary.pool(def.id, dest.kind):
		if sp.id == dest.spec.id or sp.entries.is_empty() or sp.exits.size() < needs_exits:
			continue
		if not roles.all(func(t): return sp.tags.has(t)):
			continue
		if not dest.evidence.all(func(e): return _spec_can_host(sp, e)):
			continue
		for i in sp.entries.size():
			if not (tried.get(sp.id, []) as Array).has(100 + i):
				others.append({"spec": sp, "beat": dest.index, "socket": 100 + i, "plan": plan, "swap": true})
	out.append_array(RngStreams.shuffled(r, others))
	return out


func on_fallback_used(res: Dictionary) -> void:
	## A different room now stands where the plan expected another: keep the plan describing what is really there.
	if not bool(res.get("swap", false)):
		return
	var dest: BeatPlan = beat_by_index(int(res.get("beat", -1)))
	if dest != null:
		dest.spec = res["spec"]


func populate(chunk: Chunk, _streamer: Object) -> void:
	if populator.is_valid():
		populator.call(chunk, chunk.plan.get("bp", null))


# --- validation (SPEC 15: the generator never produces an unwinnable floor) ----------------

func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	if not layout_ok:
		errs.append("the main line could not be laid out without overlap (%d search nodes)" % layout_nodes)
	for bp in main_beats:
		if bp.spec == null:
			errs.append("beat %s has no room in the pool" % bp.label())
			continue
		match bp.kind:
			&"arrival":
				if bp.spec.exits.is_empty():
					errs.append("arrival %s has no exit" % bp.spec.id)
			&"departure":
				if bp.spec.entries.is_empty():
					errs.append("departure %s has no entry" % bp.spec.id)
			_:
				if bp.spec.entries.is_empty():
					errs.append("%s has no entry" % bp.label())
				if bp.index < main_beats.size() - 1 and bp.spec.exits.is_empty():
					errs.append("%s has no exit to continue" % bp.label())
	# Doctrine 3: before the exam, >= 2 pieces of evidence for the ACTIVE variant, >= 1 with prominence >= 2
	if exam_index >= 0 and def.entity_rule() != null and not def.evidence.is_empty():
		var n := 0
		var strong := 0
		for bp in main_beats:
			if bp.index >= exam_index:
				break
			for e in bp.evidence:
				if e.variant != truth:
					errs.append("evidence %s supports the wrong variant" % e.id)
				if not _spec_can_host(bp.spec, e):
					errs.append("room %s cannot host evidence %s" % [bp.spec.id, e.id])
				n += 1
				if e.prominence >= 2:
					strong += 1
		if n < 2:
			errs.append("only %d evidence pieces before the exam (need 2)" % n)
		if strong < 1:
			errs.append("no prominence>=2 evidence before the exam")
	return errs
