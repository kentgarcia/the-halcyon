class_name EntityNotes
extends RefCounted
## Plain-language explanations of each entity, used by Autopsy / Inspection / the notebook. These describe
## what was TRUE for the run (Fairness Doctrine 1: the house may lie in what it says, never in what it shows).

const NAMES := {
	&"foreman": "The Foreman", &"lifeguard": "The Lifeguard", &"queue": "The Queue",
	&"hum": "The Hum", &"greeter": "The Greeter", &"audit": "Management",
}

const NOTES := {
	&"foreman": {
		0: "The alarm summoned him to the alarm. Leaving by the nearest exit was safe.",
		1: "He waited behind the nearest exit. The alarm called him to the door you were about to use.",
	},
	&"lifeguard": {
		0: "When the whistle blew he scanned the room. Standing still was safe; moving was not.",
		1: "When the whistle blew he walked the pool edge toward anyone standing still. Cover was safe.",
	},
	&"queue": {
		0: "The ticket was honest. The line only turned on guests who left it.",
		1: "The ticket was a claim. Every call, the line stepped toward you. Not taking a number was safe.",
	},
	&"hum": {
		0: "It moved only through dark cells. Lit cells were sanctuary.",
		1: "It was drawn to light and ignored a still guest in the dark. The lamp made you the brightest thing in the room.",
	},
	&"greeter": {
		0: "Answering him was safe: he nodded and opened a door. Ignoring him made him follow.",
		1: "Answering him was the mistake: he escorted you into a unit with no exit. Hiding and ignoring was safe.",
	},
	&"audit": {
		0: "Management was honest.",
		1: "Management was honest.",
	},
}


static func name_of(entity_id: StringName) -> String:
	return String(NAMES.get(entity_id, "The house"))


static func note(entity_id: StringName, truth: int) -> String:
	var n: Dictionary = NOTES.get(entity_id, {})
	return String(n.get(truth, ""))
