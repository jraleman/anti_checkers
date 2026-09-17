extends Control

## Explicit resignation: giving away checkers wins, but conceding does not.

signal resignation_confirmed
signal cancelled

const Options = preload("res://games/anti_checkers/anti_checkers_options.gd")
var _panel: PanelContainer
var _column: VBoxContainer
var _title: Label
var _description: Label
var _cancel: Button
var _confirm: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.02, 0.04, 0.85)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size.x = 500
	var style := StyleBoxFlat.new()
	style.bg_color = Color("241b29")
	style.border_color = Color("edbe83")
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, 28)
	_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_panel.add_child(scroll)
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 18)
	scroll.add_child(_column)
	_column.minimum_size_changed.connect(_queue_fit)
	_title = Label.new()
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_font_size_override("font_size", 30)
	_column.add_child(_title)
	_description = Label.new()
	_description.custom_minimum_size.x = 430
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.add_theme_font_size_override("font_size", 20)
	_description.text = (
		"Giving away all your checkers wins. Resigning is different: "
		+ "it awards this match to your opponent."
	)
	_column.add_child(_description)
	_cancel = Button.new()
	_cancel.text = "Keep playing"
	_cancel.custom_minimum_size.y = 54
	_cancel.pressed.connect(_cancel_decision)
	_column.add_child(_cancel)
	_confirm = Button.new()
	_confirm.text = "Resign this match"
	_confirm.custom_minimum_size.y = 54
	_confirm.pressed.connect(_confirm_resignation)
	_column.add_child(_confirm)
	for button in [_cancel, _confirm]:
		var other: Button = _confirm if button == _cancel else _cancel
		var path: NodePath = button.get_path_to(other)
		button.focus_next = path
		button.focus_previous = path
		button.focus_neighbor_top = path
		button.focus_neighbor_bottom = path
		button.focus_neighbor_left = path
		button.focus_neighbor_right = path
	hide()


## Focus starts on the safe choice, never on an accidental match-ending action.
func show_resignation(side_name: String) -> void:
	_title.text = "Resign as %s?" % side_name
	show()
	focus_decision()
	_queue_fit()


## Pause returns to this decision rather than a destroyed menu control.
func focus_decision() -> void:
	if visible:
		_cancel.grab_focus()


## Resizing keeps the confirmation scrollable and both actions reachable.
func set_readability_scale(factor: float, compact: bool) -> void:
	var width := minf(500 * factor, maxf(get_viewport_rect().size.x - 56, 1))
	_panel.custom_minimum_size.x = width
	_description.custom_minimum_size.x = maxf(width - 56, 1)
	_title.add_theme_font_size_override("font_size", roundi(30 * factor))
	_description.add_theme_font_size_override("font_size", roundi(20 * factor))
	for button in [_cancel, _confirm]:
		button.add_theme_font_size_override("font_size", roundi(22 * factor))
		button.custom_minimum_size.y = (66 if compact else 54) * factor
	_queue_fit()


## Replay and exit dismiss the decision without awarding a result.
func dismiss() -> void:
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(Options.CANCEL_ACTION):
		get_viewport().set_input_as_handled()
		_cancel_decision()


func _confirm_resignation() -> void:
	hide()
	resignation_confirmed.emit()


func _cancel_decision() -> void:
	hide()
	cancelled.emit()


func _queue_fit() -> void:
	_fit_panel.call_deferred()


func _fit_panel() -> void:
	if is_inside_tree():
		_panel.custom_minimum_size.y = minf(
			_column.get_combined_minimum_size().y + 56,
			maxf(get_viewport_rect().size.y - 56, 1)
		)
