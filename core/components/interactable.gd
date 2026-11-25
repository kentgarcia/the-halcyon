class_name Interactable
extends Node3D
## Anything the player can use. Position the node where the player should "aim" (it is the gaze
## target). Behaviour is injected through callables so props stay plain nodes (SPEC 12.3).
##
## Modes (all on the single Interact button, mobile-safe):
##   TAP           press = action
##   HOLD_PROGRESS hold for `hold_duration` seconds, then tap_cb fires (pry, tear tape)
##   HOLD_LIVE     tap = tap_cb;  holding past `hold_threshold` = hold_start_cb ... release = hold_end_cb
##                 (doors: tap opens/closes, hold peeks)

enum Mode { TAP, HOLD_PROGRESS, HOLD_LIVE }

var mode: int = Mode.TAP
var prompt: String = "Use"
var enabled: bool = true
var max_range: float = GameScale.INTERACT_RANGE
var hold_duration: float = 1.0
var hold_threshold: float = 0.4
var tag: StringName = &""
var data: Dictionary = {}

var prompt_cb: Callable = Callable()      ## (player) -> String ; "" hides the prompt
var can_cb: Callable = Callable()         ## (player) -> bool
var tap_cb: Callable = Callable()         ## (player)
var hold_start_cb: Callable = Callable()  ## (player)
var hold_end_cb: Callable = Callable()    ## (player)


func _ready() -> void:
	add_to_group(&"interactable")


func available(player: Node) -> bool:
	if not enabled:
		return false
	if can_cb.is_valid():
		return bool(can_cb.call(player))
	return true


func current_prompt(player: Node) -> String:
	if prompt_cb.is_valid():
		return String(prompt_cb.call(player))
	return prompt


func do_tap(player: Node) -> void:
	if tap_cb.is_valid():
		tap_cb.call(player)


func do_hold_start(player: Node) -> void:
	if hold_start_cb.is_valid():
		hold_start_cb.call(player)


func do_hold_end(player: Node) -> void:
	if hold_end_cb.is_valid():
		hold_end_cb.call(player)
