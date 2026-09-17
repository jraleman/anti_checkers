extends RefCounted

## A complete, discoverable giveaway-checkers product without host registration.

const OPTIONS := preload("res://games/anti_checkers/anti_checkers_options.gd")
const GAME_ID := OPTIONS.GAME_ID


## Matches end by their own rules; all surrounding screens remain the shared shell.
static func manifest() -> GameManifest:
	var game := GameManifest.new()
	game.id = GAME_ID
	game.title = "Anti Checkers"
	game.tagline = "Jump. Give. Win."
	game.menu_order = 6
	game.gameplay_scene_path = "res://games/anti_checkers/gameplay.tscn"
	game.intro_scene_path = "res://games/anti_checkers/intro.tscn"
	game.tutorial_poster_path = "res://games/anti_checkers/assets/poster.svg"
	game.share_art_scene_path = "res://games/anti_checkers/ui/share_art.tscn"
	game.share_art_style = GAME_ID
	game.stats_url = "https://deskcansaw.com"
	game.supports_single_player = true
	game.supports_multiplayer = true
	game.supports_cpu_opponent = false
	game.uses_shell_round_rules = false
	game.default_lives_mode = false
	game.control_style = GameManifest.CONTROL_STYLE_CUSTOM_KEYS
	game.tunables = OPTIONS.TUNABLES
	game.control_bindings = OPTIONS.CONTROL_BINDINGS
	game.solo_setup_choices = [OPTIONS.PLAYER_SIDE_KEY]
	var controls := (
		"Click or tap a checker, then its destination. The shared cursor keys "
		+ "below browse squares; Select chooses a piece or destination. "
		+ "Complete every jump in a chain with the same piece.\n"
		+ "Right-drag or hold the camera keys to orbit in solo or pan in local "
		+ "play. The wheel and +/- buttons zoom; Flip changes the view and "
		+ "Reset View restores it. Esc pauses. Rebind keys in Settings > Controls."
	)
	var cpu := (
		"The CPU takes the other colour in single-player and follows the same "
		+ "compulsory jumps. Casual, Thoughtful and Cunning difficulty choices "
		+ "apply next match."
	)
	var solo := (
		"You play %s; the CPU takes the other side. Red always starts. "
		+ "Give away every checker, or have no legal move on your turn, to win. "
		+ "There is no match clock."
	)
	game.copy = {
		"mode_select_intro": "The familiar board. The opposite ambition.",
		"mode_select_hint": "Choose a side for solo, or share one board with a friend.",
		"single_player_description": "Choose your colour. Red starts; the CPU takes the other.",
		"single_player_roster": "You as %s vs CPU",
		"single_player_selection_summary": "Selected: Single Player - You as %s vs CPU.",
		"multiplayer_description": (
			"Two humans alternate Red and Ivory on one overhead board. "
			+ "Both use the same controls."
		),
		"player_one_control_description": "Red moves first. Use the shared board controls below.",
		"player_two_control_description": "On Ivory's turn, use the same board and controls.",
		"cpu_opponent_description": cpu,
		"solo_confirm_title": "%s vs CPU",
		"solo_confirm_description": "You play %s. Red always moves first.",
		"versus_confirm_title": "Two humans, one board",
		"versus_confirm_description": "Alternate Red and Ivory. The camera stays overhead.",
		"instructions_headline": "Nothing left? You win.",
		"instructions_rules": (
			"English/American checkers on an 8 x 8 board. Each side starts "
			+ "with 12 men on the dark squares; Red moves first.\n"
			+ "Men step one square diagonally forward. Jump an adjacent enemy "
			+ "to an empty square beyond it to capture, also forward only.\n"
			+ "If any capture exists, you must jump. Choose any available "
			+ "capture, then keep jumping with that same piece until it cannot. "
			+ "You do not have to choose the longest chain.\n"
			+ "Reaching the far row crowns a king and ENDS that turn. Kings "
			+ "step or jump in either direction, but never fly across the board.\n"
			+ "Win by having no pieces or no legal moves on your turn. "
			+ "Taking the opponent's last checker makes THEM the winner.\n"
			+ "Three repetitions draw, as do 40 moves each with no capture "
			+ "or man move. Matches are untimed."
		),
		"instructions_demo_prompt": "JUMP. GIVE. WIN.",
		"instructions_solo_summary": solo,
		"instructions_cpu_summary": solo,
		"instructions_versus_summary": (
			"Two humans share the square cursor and camera controls. "
			+ "Red starts, then Ivory. Complete jump chains before passing "
			+ "the turn. Flip Board changes the view, never the players."
		),
		"instructions_player_one_controls": controls,
		"instructions_player_two_controls": controls,
		"instructions_cpu_controls": cpu,
	}
	game.achievements = {
		"anti_checkers_first_match": {
			"title": "The Other Way to Play",
			"description": "Finish an Anti Checkers match.", "badge": "AC",
		},
		"anti_checkers_giveaway": {
			"title": "Light as Air",
			"description": "Win as a human by giving away all twelve checkers.", "badge": "0",
		},
		"anti_checkers_outsmarted": {
			"title": "A Generous Rival",
			"description": "Win an Anti Checkers match against the CPU.", "badge": "CPU",
		},
		"anti_checkers_chain": {
			"title": "One More Jump",
			"description": "Finish a match after completing a human multi-jump turn.",
			"badge": "2x",
		},
	}
	game.credits = [
		{"heading": "Game Design & Code", "lines": ["DeskCanSaw"]},
		{
			"heading": "Rules",
			"lines": ["Traditional English/American checkers, with the giveaway objective"],
		},
		{
			"heading": "Board, Checkers & Art",
			"lines": ["Original walnut, garnet and ivory table, meshes and vector art - DeskCanSaw"],
		},
		{
			"heading": "Sound",
			"lines": ["Original synthesized wooden clicks and chimes - no external samples"],
		},
		{
			"heading": "Accessible Play",
			"lines": [
				"Shared, rebindable controls and mouse/touch selection",
				"Stacked kings, side letters, optional player labels and audio captions",
			],
		},
	]
	var theme := GameTheme.new()
	theme.logo_texture_path = "res://games/anti_checkers/assets/logo.svg"
	theme.logo_color = Color.WHITE
	theme.plaque_color = Color("39232c")
	theme.accent = Color("edbe83")
	theme.light = Color("fff0dc")
	theme.background_top = Color("2a1e29")
	theme.background_bottom = Color("100f19")
	theme.background_material = preload("res://games/anti_checkers/ui/menu_background.tres")
	theme.menu_motion = GameTheme.MenuMotion.FIRM
	theme.style_share_card = true
	game.theme = theme
	return game
