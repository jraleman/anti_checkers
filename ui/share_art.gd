extends Control

## Original cover art and explicitly side-labelled match facts, independent of autoloads.

const POSTER := preload("res://games/anti_checkers/assets/poster.svg")
const ART_SIZE := Vector2(1200, 630)
const GOLD := Color("edbe83")
const CREAM := Color("fff0dc")
var _pieces_left: Array[int] = []
var _turn_count := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


## Clears old facts when the host reuses this art for a generic promotion card.
func configure(data: Dictionary) -> void:
	_pieces_left.clear()
	_turn_count = -1
	if data.has("pieces_left"):
		var counts: Variant = data["pieces_left"]
		if (
			counts is Array and counts.size() == 2
			and counts[0] is int and counts[1] is int
			and counts[0] >= 0 and counts[0] <= 12
			and counts[1] >= 0 and counts[1] <= 12
		):
			_pieces_left.assign(counts)
		else:
			push_warning("Anti Checkers share art needs Red/Ivory counts from 0 to 12.")
	if data.has("turn_count"):
		var turns: Variant = data["turn_count"]
		if turns is int and turns >= 0:
			_turn_count = turns
		else:
			push_warning("Anti Checkers share art needs a non-negative turn count.")
	queue_redraw()


func _draw() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	var fit := minf(size.x / ART_SIZE.x, size.y / ART_SIZE.y)
	draw_set_transform((size - ART_SIZE * fit) * 0.5, 0.0, Vector2.ONE * fit)
	draw_texture_rect(POSTER, Rect2(Vector2.ZERO, ART_SIZE), false)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(65, 189), "ANTI", HORIZONTAL_ALIGNMENT_LEFT, 470, 78, CREAM)
	draw_string(font, Vector2(65, 268), "CHECKERS", HORIZONTAL_ALIGNMENT_LEFT, 470, 70, CREAM)
	draw_string(font, Vector2(68, 321), "JUMP. GIVE. WIN.",
		HORIZONTAL_ALIGNMENT_LEFT, 430, 30, GOLD)
	draw_string(font, Vector2(68, 392), "Nothing left? You win.",
		HORIZONTAL_ALIGNMENT_LEFT, 430, 27, CREAM)
	if not _pieces_left.is_empty():
		draw_string(font, Vector2(68, 463),
			"Left: Red %d  /  Ivory %d" % [_pieces_left[0], _pieces_left[1]],
			HORIZONTAL_ALIGNMENT_LEFT, 430, 26, CREAM)
	if _turn_count >= 0:
		draw_string(font, Vector2(68, 507), "%d %s played" % [
			_turn_count, "turn" if _turn_count == 1 else "turns",
		],
			HORIZONTAL_ALIGNMENT_LEFT, 430, 24, GOLD)
