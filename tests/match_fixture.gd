extends "res://games/anti_checkers/gameplay.gd"

## Exercises the real match without writing achievements or collection progression.

var observed_achievements := PackedStringArray()


func _reset_round_state() -> void:
	super()
	observed_achievements.clear()


func _unlock_round_achievement(id: String) -> void:
	observed_achievements.append(id)


func _record_round(_one: int, _two: int) -> String:
	return ""
