extends PanelContainer

## An explicit turn briefing and scrollable ledger alongside the shared round HUD.

signal flip_requested
signal reset_camera_requested
signal zoom_requested(steps: float)
signal resign_requested

const CREAM := Color("fff0dc")
const GOLD := Color("edbe83")
var _turn: Label
var _rule: Label
var _selection: Label
var _last_move: Label
var _history: RichTextLabel
var _keys: Label
var _resign: Button
var _column: VBoxContainer
var _labels: Array[Label] = []
var _buttons: Array[Button] = []
var _key_hint := ""
var _compact := false


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("241b29")
	style.border_color = Color("78594c")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		style.set_content_margin(side, 22)
	add_theme_stylebox_override("panel", style)
	var frame := VBoxContainer.new()
	frame.add_theme_constant_override("separation", 12)
	add_child(frame)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	frame.add_child(scroll)
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 12)
	scroll.add_child(_column)
	_label("LESS IS VICTORY", 16, GOLD)
	_turn = _label("Red to move", 32, CREAM)
	_rule = _label("Choose a checker", 21, GOLD)
	_selection = _label("Click a checker, then its destination.", 20, CREAM)
	_column.add_child(HSeparator.new())
	_last_move = _label("Red moves first.", 18, Color("d2c4be"))
	_label("MOVE LEDGER", 14, GOLD)
	_history = RichTextLabel.new()
	_history.name = "MoveLedger"
	_history.custom_minimum_size.y = 110
	_history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history.bbcode_enabled = false
	_history.scroll_following = true
	_history.add_theme_font_size_override("normal_font_size", 18)
	_history.add_theme_color_override("default_color", CREAM)
	_history.accessibility_name = "Move ledger"
	_column.add_child(_history)
	_keys = _label("", 16, Color("d2c4be"))
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 10)
	buttons.add_theme_constant_override("v_separation", 10)
	frame.add_child(buttons)
	_button(buttons, "Flip", "View the board from the other side.",
		func() -> void: flip_requested.emit())
	_button(buttons, "Reset View", "Restore the complete board.",
		func() -> void: reset_camera_requested.emit())
	_button(buttons, "-", "Zoom out.", func() -> void: zoom_requested.emit(-1.0))
	_button(buttons, "+", "Zoom in.", func() -> void: zoom_requested.emit(1.0))
	_resign = _button(buttons, "Resign", "Concede this match after confirmation.",
		func() -> void: resign_requested.emit())


## Compulsory captures and same-piece continuations stay textual with hints disabled.
func present(
	turn_text: String, forced_capture: bool, continuation: String,
	thinking: bool, finished: bool
) -> void:
	_turn.text = turn_text
	_rule.text = (
		"MATCH COMPLETE" if finished else
		"KEEP JUMPING FROM " + continuation.to_upper() if not continuation.is_empty() else
		"CAPTURE REQUIRED" if forced_capture else "NO CAPTURE - CHOOSE A MOVE"
	)
	if not continuation.is_empty() and not finished:
		_rule.text += "\nSame checker. Your turn is not over."
	if thinking and not finished:
		_rule.text += "\nCPU is thinking..."
	for button in _buttons:
		button.disabled = finished


## Selection and invalid-move feedback is available to assistive technology.
func describe_square(text: String) -> void:
	_selection.text = text
	_selection.accessibility_description = text


## Replaces the ledger so replay cannot leak an earlier match's moves.
func set_ledger(lines: PackedStringArray, last_move: String) -> void:
	_history.text = "\n".join(lines)
	_last_move.text = last_move


## Live key labels come from the controller rather than an autoload dependency.
func set_key_hint(text: String) -> void:
	_key_hint = text
	_keys.text = text.replace("\n", " | ") if _compact else text


## Keep the physically small phone view readable despite the host's virtual canvas.
func set_readability_scale(factor: float, compact: bool) -> void:
	_compact = compact
	for label in _labels:
		label.add_theme_font_size_override("font_size",
			roundi(float(label.get_meta("font_size")) * factor))
	_history.add_theme_font_size_override("normal_font_size", roundi(18 * factor))
	_history.custom_minimum_size.y = (80 if compact else 110) * factor
	_column.add_theme_constant_override("separation", roundi(12 * factor))
	for button in _buttons:
		button.add_theme_font_size_override("font_size", roundi(22 * factor))
		button.custom_minimum_size = Vector2(50, 66 if compact else 48) * factor
	set_key_hint(_key_hint)


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.set_meta("font_size", font_size)
	_labels.append(label)
	_column.add_child(label)
	return label


func _button(parent: Node, text: String, hint: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = hint
	button.accessibility_name = hint
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(50, 48)
	button.pressed.connect(action)
	parent.add_child(button)
	_buttons.append(button)
	return button
