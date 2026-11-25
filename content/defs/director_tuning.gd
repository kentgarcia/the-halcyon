class_name DirectorTuning
extends Resource
## Dread Director tunables (SPEC 7, Appendix C). One resource; loaded from res://data/director_tuning.tres.

@export var tell_lead_seconds: float = 4.0
@export var encounter_cooldown: float = 45.0
@export var relief_interval: float = 150.0
@export var max_major_per_floor: int = 1
@export var max_minor_per_floor: int = 2
@export var phantom_weight: float = 3.0
@export var tell_weight: float = 2.0
@export var encounter_weight: float = 1.0
@export var dread_decay_per_s: float = 0.55
@export var dread_in_dark_per_s: float = 0.9
@export var dread_in_light_per_s: float = -0.5
@export var dread_noise_gain: float = 6.0
@export var phantom_min_gap: float = 28.0
@export var first_event_delay: float = 35.0
@export var hum_cell_seconds: float = 0.8
@export var hum_lamp_stun: float = 4.0
@export var housekeeping_warn_fraction: float = 0.8
@export var pa_remark_gap: float = 40.0
@export var brace_min: float = 4.0
@export var brace_max: float = 8.0
@export var handle_try_seconds: float = 1.5

# --- Foreman (B3 Boiler, SPEC 6.2) -------------------------------------------------------------
@export var foreman_run_speed: float = 4.0            ## m/s, running to the alarm (capped to a walk by the walk_encouraged Clause)
@export var foreman_walk_speed: float = 2.2           ## m/s while searching / returning
@export var foreman_search_seconds: float = 20.0      ## HOLDS: how long he combs the alarm source before going home
@export var foreman_sight_range: float = 12.0         ## line-of-sight range (SPEC 6.2 Senses)
@export var foreman_strike_range: float = 1.8         ## he only hurts what is this close (searching / ambush)
@export var foreman_ambush_windup: float = 0.6        ## INVERTED: seconds between the door swinging open and the strike
@export var foreman_reloc_seconds: float = 4.5        ## INVERTED: time to reach a different exit (the exit sign flickers throughout)
@export var foreman_alarm_seconds: float = 24.0       ## how long a tripped alarm rings

# --- Lifeguard (B2 Natatorium, SPEC 6.3) ----------------------------------------------------------
@export var lifeguard_freeze_min: float = 7.0         ## HOLDS: shortest freeze before the second blast
@export var lifeguard_freeze_max: float = 10.5
@export var lifeguard_move_grace: float = 0.7         ## seconds after the whistle to come to a stop
@export var lifeguard_still_speed: float = 0.35       ## m/s: below this the guest counts as standing still
@export var lifeguard_walk_speed: float = 1.7         ## INVERTED: m/s along the pool edge
@export var lifeguard_still_delay: float = 0.8        ## INVERTED: seconds of stillness before he climbs down
@export var lifeguard_strike_range: float = 1.6
@export var lifeguard_pull_speed: float = 2.4         ## HOLDS: m/s the drain vent drags a guest who moved
@export var lifeguard_pull_seconds: float = 1.1
@export var lifeguard_pitch_inverted: float = 0.8     ## whistle pitch ratio when the card lies (SPEC 6.3 Tells)
