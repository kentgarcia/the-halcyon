class_name Nerve
extends Node
## Nerve: 3 internal segments, no HP bar (SPEC 3.3). The first hit is always a warning (never lethal
## at full Nerve). Recovers 1 segment per 45 s while not in an active encounter. 0 = Blackout.

const REGEN_SECONDS := 45.0
const INVULN_SECONDS := 2.5

var invuln := 0.0
var regen_timer := 0.0
var in_danger := false              ## set by the Director while an Encounter is active
var blacked_out := false


func _process(delta: float) -> void:
	if blacked_out:
		return
	invuln = maxf(0.0, invuln - delta)
	if RunState.nerve < RunState.nerve_max and not in_danger:
		regen_timer += delta
		if regen_timer >= REGEN_SECONDS:
			regen_timer = 0.0
			RunState.set_nerve(RunState.nerve + 1)
	else:
		regen_timer = 0.0 if in_danger else regen_timer


func hit(source: StringName, amount: int = 1) -> bool:
	## Returns true if the hit landed.
	if blacked_out or invuln > 0.0:
		return false
	var dmg := amount
	if RunState.nerve >= RunState.nerve_max and dmg >= RunState.nerve:
		dmg = RunState.nerve - 1                  # the first hit is a warning, never lethal at full Nerve
	invuln = INVULN_SECONDS
	regen_timer = 0.0
	RunState.set_nerve(RunState.nerve - dmg)
	EventBus.player_hit.emit(source, dmg)
	if RunState.nerve <= 0:
		blacked_out = true
		EventBus.blackout.emit()
	return true


func lose_segment(source: StringName) -> void:
	## Costs (wrong Verdict, Housekeeping shown-out): bypasses invulnerability, can still not kill at full.
	if blacked_out:
		return
	RunState.set_nerve(RunState.nerve - 1)
	EventBus.player_hit.emit(source, 1)
	if RunState.nerve <= 0:
		blacked_out = true
		EventBus.blackout.emit()


func reset() -> void:
	blacked_out = false
	invuln = 0.0
	regen_timer = 0.0
	in_danger = false
