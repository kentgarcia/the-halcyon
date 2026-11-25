extends Node
## Typed signals only. No state lives here. Gameplay systems talk through this bus so they stay decoupled.

# --- sensing / noise
signal noise_emitted(pos: Vector3, loudness: float, kind: StringName)

# --- world
signal door_opened(door: Node, door_type: StringName)
signal door_closed(door: Node)
signal door_peeked(door: Node)
signal chunk_entered(chunk: Node)
signal chunk_unloaded(chunk_id: int)
signal light_changed(cell: Object, state: int)

# --- rules / evidence / verdicts
signal rule_marked(rule_id: StringName, mark: int)
signal evidence_found(evidence_id: StringName)
signal verdict_filed(floor_id: StringName, verdict: int)
signal clause_changed(clause_id: StringName)
signal clause_voided(clause_id: StringName)

# --- director / encounters
signal dread_changed(value: float)
signal tell_started(entity_id: StringName, kind: StringName, lead_time: float)
signal encounter_started(entity_id: StringName)
signal encounter_ended(entity_id: StringName)

# --- player state
signal nerve_changed(segments: int)
signal player_hit(source: StringName, amount: int)
signal blackout()
signal battery_changed(value: float)
signal pocket_changed(item_id: StringName)
signal hide_changed(hiding: bool)
signal camcorder_state_changed(state: int)
signal freeze_frame_taken(count: int)

# --- flow
signal floor_started(floor_id: StringName)
signal floor_cleared(floor_id: StringName)
signal run_started()
signal run_ended(ending: StringName)

# --- presentation
signal subtitle(text: String, duration: float)
signal sound_heard(id: StringName, pos: Vector3)      ## a positional world sound started (Sound radar, SPEC 11.3)
signal pa_line_requested(line_id: StringName, take: StringName)
signal prompt_changed(text: String)
signal toast(text: String)
