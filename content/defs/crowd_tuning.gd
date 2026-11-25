class_name CrowdTuning
extends Resource
## Tunables for the three "people" entities: the Queue (B1), the Greeter (2F) and the Lobby Audit (SPEC 6.4, 6.6,
## 6.7, Appendix C). One resource, loaded from res://data/crowd_tuning.tres; tests shrink the clocks.

# --- The Queue ---
@export var queue_board_period: float = 20.0          ## the board counts every ~20 s (SPEC 6.4)
@export var queue_chime_window: float = 3.0           ## all faces turn to the board for 3 s on a call
@export var queue_wait_ticks_min: int = 6             ## a ticket is called after 6..9 board ticks (2-3 min)
@export var queue_wait_ticks_max: int = 9
@export var queue_head_creep_deg_per_min: float = 8.0 ## heads turn "a few degrees per minute" toward the guest
@export var queue_suspicion_gain: float = 1.6         ## x guest noise per second while out of line
@export var queue_suspicion_decay: float = 0.18
@export var queue_stare_time: float = 3.0             ## all turned, before the line moves
@export var queue_step_time: float = 1.4              ## one tile per lurch while the line closes in (alert)
@export var queue_leave_radius: float = 4.5           ## metres from the tail slot that counts as "left the line"
@export var queue_hit_dist: float = 1.25
@export var queue_exam_duration: float = 200.0        ## the forced stillness: ~3 minutes of waiting + the walk
@export var queue_minor_duration: float = 110.0

# --- The Greeter ---
@export var greeter_speed: float = 3.0                ## only ever while unobserved
@export var greeter_greet_dist: float = 2.7
@export var greeter_answer_window: float = 14.0
@export var greeter_follow_dist: float = 5.0
@export var greeter_insist_dist: float = 1.7
@export var greeter_escort_hold: float = 10.0         ## the unit with no exit stays shut this long
@export var greeter_knock_gap: float = 1.2            ## rhythmic knocks (HOLDS); INVERTED jitters around this
@export var greeter_exam_duration: float = 80.0
@export var greeter_minor_duration: float = 50.0

# --- The Audit ---
@export var audit_check_seconds: float = 25.0
@export var audit_intro_gap: float = 2.0
@export var audit_rule_gap: float = 3.5               ## breathing room between PA lines
@export var audit_retry_once: bool = true
@export var audit_danger_rate: float = 0.12           ## per second while the guest is doing the wrong thing
@export var audit_duration: float = 900.0


static func load_default() -> CrowdTuning:
	var t := load("res://data/crowd_tuning.tres") as CrowdTuning
	return t if t != null else CrowdTuning.new()
