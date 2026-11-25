class_name FloorCatalog
extends RefCounted
## The six floors, their cards and their evidence (SPEC 5.3, 4.1, Appendix B). Defined in code as
## typed Resources; nothing here is rolled — the roll lives in RunState / FloorPlan.

const ORDER: Array[StringName] = [&"boiler", &"natatorium", &"blue", &"yellow", &"units", &"lobby"]
const P_INVERTED: Array[float] = [0.25, 0.35, 0.45, 0.50, 0.50, 0.50]

static var _cache: Dictionary = {}


static func get_def(id: StringName) -> FloorDef:
	if _cache.has(id):
		return _cache[id]
	var d: FloorDef
	match id:
		&"boiler": d = _boiler()
		&"natatorium": d = _natatorium()
		&"blue": d = _blue()
		&"yellow": d = _yellow()
		&"units": d = _units()
		&"lobby": d = _lobby()
		_: d = _yellow()
	_cache[id] = d
	return d


static func index_of(id: StringName) -> int:
	return ORDER.find(id)


static func id_at(i: int) -> StringName:
	return ORDER[clampi(i, 0, ORDER.size() - 1)]


static func next_of(id: StringName) -> StringName:
	var i := ORDER.find(id)
	return &"" if i < 0 or i + 1 >= ORDER.size() else ORDER[i + 1]


static func _rule(floor_id: StringName, n: int, kind: int, text: String, extra: Dictionary = {}) -> RuleDef:
	var r := RuleDef.new()
	r.id = StringName("%s_r%d" % [floor_id, n])
	r.floor_id = floor_id
	r.number = n
	r.kind = kind
	r.text = text
	r.instinct = StringName(extra.get("instinct", ""))
	r.law_key = StringName(extra.get("law", ""))
	r.foreshadow = String(extra.get("foreshadow", ""))
	r.clause_id = StringName(extra.get("clause", ""))
	return r


static func _ev(floor_id: StringName, id: String, kind: int, variant: int, prom: int, slot: StringName, text: String, note: String, params: Dictionary = {}) -> EvidenceDef:
	var e := EvidenceDef.new()
	e.id = StringName("%s_%s" % [floor_id, id])
	e.floor_id = floor_id
	e.kind = kind
	e.variant = variant
	e.prominence = prom
	e.slot_kind = slot
	e.text = text
	e.note = note
	e.params = params
	return e


static func _base(id: StringName, idx: int, title: String, short: String, theme: StringName, ent: StringName, instinct: StringName, grammar: Array[StringName]) -> FloorDef:
	var d := FloorDef.new()
	d.id = id
	d.index = idx
	d.title = title
	d.short_name = short
	d.theme_id = theme
	d.entity_id = ent
	d.instinct = instinct
	d.p_inverted = P_INVERTED[idx]
	d.beat_grammar = grammar
	d.chunk_dir = "res://content/chunks/%s" % id
	return d


const E := RuleDef.Kind.ENTITY
const L := RuleDef.Kind.LAW
const F := RuleDef.Kind.FLAVOR
const H := 0       # RunState.Truth.HOLDS
const I := 1       # RunState.Truth.INVERTED
const G := EvidenceDef.Kind.GRAFFITI
const P := EvidenceDef.Kind.PROP_STATE
const T := EvidenceDef.Kind.TAPE_CLIP


static func _yellow() -> FloorDef:
	var d := _base(&"yellow", 3, "Floor 1 (Offices)", "1F Yellow", &"yellow", &"hum", &"seek_light",
		[&"arrival", &"choice", &"choice", &"long", &"choice", &"exam", &"rest", &"departure"])
	d.rules = [
		_rule(d.id, 1, L, "Walking is encouraged. Running is not.", {"law": "sprint_loud", "clause": "walk_encouraged"}),
		_rule(d.id, 2, E, "Lights are provided for your comfort. Please stay in them.", {"instinct": "seek_light", "clause": "stay_lit"}),
		_rule(d.id, 3, F, "Do not remove ceiling tiles.", {"foreshadow": "ceiling_void"}),
		_rule(d.id, 4, L, "Doors close behind you.", {"law": "doors_close", "clause": "doors_close"}),
		_rule(d.id, 5, F, "Management is always listening."),
	]
	d.evidence = [
		_ev(d.id, "graf_h", G, H, 3, &"graffiti", "STAY LIT", "Graffiti under a working fixture: STAY LIT."),
		_ev(d.id, "graf_i", G, I, 3, &"graffiti", "DARK IS KIND", "Graffiti in a lit corridor: DARK IS KIND."),
		_ev(d.id, "claw_h", P, H, 2, &"floor_mark", "", "Claw marks on the carpet under the dead lights. The lit floor is clean.", {"recipe": "claw", "under": "dead"}),
		_ev(d.id, "claw_i", P, I, 2, &"floor_mark", "", "Claw marks on the carpet under the lit lights. The dark floor is clean.", {"recipe": "claw", "under": "lit"}),
		_ev(d.id, "dust_h", P, H, 2, &"ceiling_mark", "", "Dead fixtures are furred with dust. Lit ones are clean.", {"recipe": "dust"}),
		_ev(d.id, "scorch_i", P, I, 2, &"ceiling_mark", "", "Scorched halos around the lit fixtures. The dead ones are dusty and untouched.", {"recipe": "scorch"}),
		_ev(d.id, "echo_h", T, H, 1, &"tape", "", "Tape: a Guest crouches in a lit cell; something passes through the dark beside them.", {"clip": "hum_hold"}),
		_ev(d.id, "echo_i", T, I, 1, &"tape", "", "Tape: a Guest crouches in the dark, lamp off; something circles a lit cell nearby.", {"clip": "hum_inv"}),
	]
	d.lab_beat = &"long"
	d.intro_pa = &"floor_yellow_intro"
	d.breaker_room = true
	return d


static func _boiler() -> FloorDef:
	var d := _base(&"boiler", 0, "Floor B3 (Boiler Rooms)", "B3 Boiler", &"boiler", &"foreman", &"run",
		[&"arrival", &"choice", &"choice", &"long", &"choice", &"exam", &"rest", &"departure"])
	d.rules = [
		_rule(d.id, 1, L, "Fire doors are for emergencies. They are loud.", {"law": "fire_alarm"}),
		_rule(d.id, 2, E, "If an alarm sounds, leave at once through the nearest exit.", {"instinct": "run", "clause": ""}),
		_rule(d.id, 3, F, "Steam is not a sign of danger."),
		_rule(d.id, 4, L, "Doors close behind you.", {"law": "doors_close", "clause": "doors_close"}),
		_rule(d.id, 5, F, "The boiler is not a Guest."),
	]
	d.evidence = [
		_ev(d.id, "graf_h", G, H, 3, &"graffiti", "WHEN IT RINGS, GO", "Graffiti beside an alarm bell: WHEN IT RINGS, GO."),
		_ev(d.id, "graf_i", G, I, 3, &"graffiti", "DON'T USE THE EXIT", "Graffiti by a fire door: DON'T USE THE EXIT."),
		_ev(d.id, "trail_h", P, H, 2, &"floor_mark", "", "Pipe-wrench scrapes lead away from the exits, toward the alarm bells.", {"recipe": "scrape", "toward": "alarm"}),
		_ev(d.id, "scratch_i", P, I, 2, &"floor_mark", "", "Scratches on the inside of the fire doors.", {"recipe": "door_scratch"}),
		_ev(d.id, "echo_h", T, H, 1, &"tape", "", "Tape: a Guest runs through an exit; behind them a hard hat turns toward the alarm.", {"clip": "foreman_hold"}),
		_ev(d.id, "echo_i", T, I, 1, &"tape", "", "Tape: a Guest runs through an exit. Something was already standing there.", {"clip": "foreman_inv"}),
	]
	d.intro_pa = &"floor_boiler_intro"
	d.fire_door_chance = 0.7
	d.alarm_floor = true
	return d


static func _natatorium() -> FloorDef:
	var d := _base(&"natatorium", 1, "Floor B2 (Natatorium)", "B2 Natatorium", &"natatorium", &"lifeguard", &"freeze",
		[&"arrival", &"choice", &"choice", &"long", &"choice", &"exam", &"rest", &"departure"])
	d.rules = [
		_rule(d.id, 1, E, "No running. When the whistle blows, stop where you stand.", {"instinct": "freeze", "clause": "whistle"}),
		_rule(d.id, 2, L, "Lockers are for Guests only.", {"law": "hide_ok"}),
		_rule(d.id, 3, F, "No diving in the shallow end."),
		_rule(d.id, 4, L, "Doors close behind you.", {"law": "doors_close", "clause": "doors_close"}),
		_rule(d.id, 5, F, "Please shower before entering the pool."),
	]
	d.evidence = [
		_ev(d.id, "graf_h", G, H, 3, &"graffiti", "FREEZE WHEN IT BLOWS", "Graffiti: FREEZE WHEN IT BLOWS."),
		_ev(d.id, "graf_i", G, I, 3, &"graffiti", "STILL IS SEEN", "Graffiti: STILL IS SEEN."),
		_ev(d.id, "ripple_h", P, H, 2, &"floor_mark", "", "The water is calm. The drain grates are scored with fingernails.", {"recipe": "drain_scratch"}),
		_ev(d.id, "foot_i", P, I, 2, &"floor_mark", "", "Wet footprints lead to the places where Guests stood still.", {"recipe": "wet_prints"}),
		_ev(d.id, "echo_h", T, H, 1, &"tape", "", "Tape: a Guest stops on the whistle; a second whistle lets them go.", {"clip": "lifeguard_hold"}),
		_ev(d.id, "echo_i", T, I, 1, &"tape", "", "Tape: a Guest stops on the whistle. The chair is empty.", {"clip": "lifeguard_inv"}),
	]
	d.intro_pa = &"floor_natatorium_intro"
	return d


static func _blue() -> FloorDef:
	var d := _base(&"blue", 2, "Floor B1 (Annex)", "B1 Blue Annex", &"blue", &"queue", &"wait",
		[&"arrival", &"choice", &"choice", &"long", &"choice", &"exam", &"rest", &"departure"])
	d.rules = [
		_rule(d.id, 1, L, "Quiet, please. Sound carries.", {"law": "noise_matters"}),
		_rule(d.id, 2, F, "Management is not responsible for lost time."),
		_rule(d.id, 3, L, "Doors close behind you.", {"law": "doors_close", "clause": "doors_close"}),
		_rule(d.id, 4, E, "Please take a number and wait to be called. Do not leave the line.", {"instinct": "wait", "clause": "take_number"}),
		_rule(d.id, 5, F, "Your number is not your name."),
	]
	d.evidence = [
		_ev(d.id, "graf_h", G, H, 3, &"graffiti", "WAIT YOUR TURN", "Graffiti: WAIT YOUR TURN."),
		_ev(d.id, "graf_i", G, I, 3, &"graffiti", "DON'T TAKE ONE", "Graffiti: DON'T TAKE ONE."),
		_ev(d.id, "stubs_h", P, H, 2, &"floor_mark", "", "Ticket stubs are scattered ahead of the line.", {"recipe": "stubs", "where": "ahead"}),
		_ev(d.id, "stubs_i", P, I, 2, &"floor_mark", "", "Ticket stubs are scattered behind the line.", {"recipe": "stubs", "where": "behind"}),
		_ev(d.id, "echo_h", T, H, 1, &"tape", "", "Tape: a Guest holds number 14 and is called to the window.", {"clip": "queue_hold"}),
		_ev(d.id, "echo_i", T, I, 1, &"tape", "", "Tape: the line takes a step each time the board counts.", {"clip": "queue_inv"}),
	]
	d.intro_pa = &"floor_blue_intro"
	return d


static func _units() -> FloorDef:
	var d := _base(&"units", 4, "Floor 2 (Residential)", "2F Units", &"units", &"greeter", &"answer",
		[&"arrival", &"choice", &"choice", &"long", &"choice", &"exam", &"rest", &"departure"])
	d.rules = [
		_rule(d.id, 1, L, "A closed door is a quiet place.", {"law": "hide_ok"}),
		_rule(d.id, 2, F, "Room service is complimentary."),
		_rule(d.id, 3, L, "Doors close behind you.", {"law": "doors_close", "clause": "doors_close"}),
		_rule(d.id, 4, F, "Please do not disturb the Guests in Unit 0."),
		_rule(d.id, 5, E, "Staff are here to help. If addressed by staff, please answer politely.", {"instinct": "answer", "clause": "staff_knock"}),
	]
	d.evidence = [
		_ev(d.id, "graf_h", G, H, 3, &"graffiti", "BE POLITE", "Graffiti: BE POLITE."),
		_ev(d.id, "graf_i", G, I, 3, &"graffiti", "DON'T ANSWER", "Graffiti: DON'T ANSWER."),
		_ev(d.id, "tray_h", P, H, 2, &"floor_mark", "", "Untouched room-service trays sit by doors that stand open.", {"recipe": "tray", "doors": "open"}),
		_ev(d.id, "tray_i", P, I, 2, &"floor_mark", "", "Untouched room-service trays sit by doors that are shut.", {"recipe": "tray", "doors": "shut"}),
		_ev(d.id, "echo_h", T, H, 1, &"tape", "", "Tape: a Guest answers; a bellhop nods and opens a door.", {"clip": "greeter_hold"}),
		_ev(d.id, "echo_i", T, I, 1, &"tape", "", "Tape: a Guest answers; a bellhop walks them into a room.", {"clip": "greeter_inv"}),
	]
	d.intro_pa = &"floor_units_intro"
	return d


static func _lobby() -> FloorDef:
	var d := _base(&"lobby", 5, "The Lobby", "Lobby", &"lobby", &"management", &"obey",
		[&"arrival", &"choice", &"long", &"exam"])
	d.rules = [
		_rule(d.id, 1, L, "All previous rules remain in force."),
		_rule(d.id, 2, E, "Management is here to help. Please obey.", {"instinct": "obey"}),
		_rule(d.id, 3, F, "Checking out is a decision, not an event."),
		_rule(d.id, 4, L, "Doors close behind you.", {"law": "doors_close", "clause": "doors_close"}),
		_rule(d.id, 5, F, "The desk is always staffed."),
	]
	d.intro_pa = &"floor_lobby_intro"
	d.housekeeping_seconds = 1200.0
	return d


static func clause_defs() -> Array[ClauseDef]:
	## The six authored Clauses (SPEC 4.10). Keyed to the rules that can be torn off a card.
	var out: Array[ClauseDef] = []
	out.append(_clause("walk_encouraged", "yellow_r1", "Walking is encouraged. Running is not.",
		"Nothing moves faster than a walk while it can see you.", "Do not sprint in sight of staff."))
	out.append(_clause("doors_close", "yellow_r4", "Doors close behind you.",
		"No staff may open a door within 8 seconds of you closing it.", "You may not reopen a door you came through."))
	out.append(_clause("staff_knock", "units_r5", "Staff must knock before entering.",
		"All staff knock three times (about 5 s) before opening any door.", "You must knock too: closed doors take 2 s and make noise.", true))
	out.append(_clause("stay_lit", "yellow_r2", "Lights are provided for your comfort. Please stay in them.",
		"Lit cells are sanctuary from every entity on later floors.", "Do not spend more than 20 s continuously in the dark.", true))
	out.append(_clause("take_number", "blue_r4", "Please take a number and wait to be called.",
		"Staff serve one at a time: only one entity pursues you at once.", "You may not use an elevator until its call chime has sounded (a 15 s wait).", true))
	out.append(_clause("whistle", "natatorium_r1", "When the whistle blows, stop where you stand.",
		"You carry a whistle: one blast freezes all staff for 3 s, once per floor.", "Any whistle you hear binds you too.", true))
	return out


static func _clause(id: String, rule: String, printed: String, house: String, guest: String, needs_holds: bool = false) -> ClauseDef:
	var c := ClauseDef.new()
	c.id = StringName(id)
	c.source_rule = StringName(rule)
	c.printed = printed
	c.house_side = house
	c.guest_side = guest
	c.requires_holds = needs_holds
	return c


static func clause_def(id: StringName) -> ClauseDef:
	for c in clause_defs():
		if c.id == id:
			return c
	return null
