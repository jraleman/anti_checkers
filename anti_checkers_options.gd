extends RefCounted

## Preload-safe settings and shared board controls; the host owns their persistence.

const GAME_ID := "anti_checkers"
const CPU_DIFFICULTY_KEY := "game/anti_checkers_cpu_difficulty"
const PLAYER_SIDE_KEY := "game/anti_checkers_player_side"
const SHOW_HINTS_KEY := "game/anti_checkers_show_hints"
const PIECE_LABELS_KEY := "game/anti_checkers_piece_labels"
const CPU_CASUAL := 0
const CPU_THOUGHTFUL := 1
const CPU_CUNNING := 2
const PLAYER_RED := 0
const PLAYER_IVORY := 1
const DEFAULT_CPU_DIFFICULTY := CPU_THOUGHTFUL
const DEFAULT_PLAYER_SIDE := PLAYER_RED

const CURSOR_UP_ACTION := &"anti_checkers_up"
const CURSOR_DOWN_ACTION := &"anti_checkers_down"
const CURSOR_LEFT_ACTION := &"anti_checkers_left"
const CURSOR_RIGHT_ACTION := &"anti_checkers_right"
const SELECT_ACTION := &"anti_checkers_select"
const CANCEL_ACTION := &"anti_checkers_cancel"
const FLIP_ACTION := &"anti_checkers_flip"
const CAMERA_UP_ACTION := &"anti_checkers_camera_up"
const CAMERA_DOWN_ACTION := &"anti_checkers_camera_down"
const CAMERA_LEFT_ACTION := &"anti_checkers_camera_left"
const CAMERA_RIGHT_ACTION := &"anti_checkers_camera_right"
const CAMERA_RESET_ACTION := &"anti_checkers_camera_reset"

const TUNABLES: Array[Dictionary] = [
	{
		"key": CPU_DIFFICULTY_KEY,
		"type": GameManifest.OPTION_CHOICE,
		"default": DEFAULT_CPU_DIFFICULTY,
		"title": "CPU difficulty",
		"description": "How far the CPU plans its giveaways. Applies next match.",
		"heading": "Anti Checkers - next match",
		"choices": [
			{"value": CPU_CASUAL, "title": "Casual"},
			{"value": CPU_THOUGHTFUL, "title": "Thoughtful"},
			{"value": CPU_CUNNING, "title": "Cunning"},
		],
	},
	{
		"key": PLAYER_SIDE_KEY,
		"type": GameManifest.OPTION_CHOICE,
		"default": DEFAULT_PLAYER_SIDE,
		"title": "Play as",
		"description": "Solo only. Red starts; the CPU takes the other side. Next match.",
		"heading": "Anti Checkers - next match",
		"choices": [
			{
				"value": PLAYER_RED,
				"title": "Red (you move first)",
				"summary_title": "Red",
			},
			{
				"value": PLAYER_IVORY,
				"title": "Ivory (CPU moves first)",
				"summary_title": "Ivory",
			},
		],
	},
	{
		"key": SHOW_HINTS_KEY,
		"type": GameManifest.OPTION_TOGGLE,
		"default": true,
		"title": "Legal-move hints",
		"description": (
			"Show destination dots and jump outlines. Compulsory captures and "
			+ "continuations remain enforced and announced with hints off."
		),
		"heading": "Anti Checkers - live",
	},
	{
		"key": PIECE_LABELS_KEY,
		"type": GameManifest.OPTION_TOGGLE,
		"default": true,
		"title": "Piece labels",
		"description": "Add R / I side letters and K for kings. Kings also have two discs.",
		"heading": "Anti Checkers - live",
	},
]

const CONTROL_BINDINGS: Array[Dictionary] = [
	{
		"key": "controls/anti_checkers_up", "action": CURSOR_UP_ACTION,
		"default": KEY_W, "title": "Cursor up",
		"description": "Browse squares toward the top of the view.",
		"player": -1, "movement": true, "heading": "Board squares",
	},
	{
		"key": "controls/anti_checkers_down", "action": CURSOR_DOWN_ACTION,
		"default": KEY_S, "title": "Cursor down",
		"description": "Browse squares toward the bottom of the view.",
		"player": -1, "movement": true, "heading": "Board squares",
	},
	{
		"key": "controls/anti_checkers_left", "action": CURSOR_LEFT_ACTION,
		"default": KEY_A, "title": "Cursor left",
		"description": "Browse squares toward the left of the view.",
		"player": -1, "movement": true, "heading": "Board squares",
	},
	{
		"key": "controls/anti_checkers_right", "action": CURSOR_RIGHT_ACTION,
		"default": KEY_D, "title": "Cursor right",
		"description": "Browse squares toward the right of the view.",
		"player": -1, "movement": true, "heading": "Board squares",
	},
	{
		"key": "controls/anti_checkers_select", "action": SELECT_ACTION,
		"default": KEY_ENTER, "title": "Select piece / destination",
		"description": "Choose a checker, then confirm its next step or jump.",
		"player": -1, "heading": "Board squares",
	},
	{
		"key": "controls/anti_checkers_cancel", "action": CANCEL_ACTION,
		"default": KEY_BACKSPACE, "title": "Cancel selection",
		"description": "Clear a choice. A started jump chain must still be completed.",
		"player": -1, "heading": "Board squares",
	},
	{
		"key": "controls/anti_checkers_flip", "action": FLIP_ACTION,
		"default": KEY_F, "title": "Flip board",
		"description": "Look from the other side without changing whose turn it is.",
		"player": -1, "heading": "Board squares",
	},
	{
		"key": "controls/anti_checkers_camera_up", "action": CAMERA_UP_ACTION,
		"default": KEY_UP, "title": "Camera up",
		"description": "Orbit upward in solo, or pan upward in local play.",
		"player": -1, "heading": "Camera",
	},
	{
		"key": "controls/anti_checkers_camera_down", "action": CAMERA_DOWN_ACTION,
		"default": KEY_DOWN, "title": "Camera down",
		"description": "Orbit downward in solo, or pan downward in local play.",
		"player": -1, "heading": "Camera",
	},
	{
		"key": "controls/anti_checkers_camera_left", "action": CAMERA_LEFT_ACTION,
		"default": KEY_LEFT, "title": "Camera left",
		"description": "Orbit left in solo, or pan left in local play.",
		"player": -1, "heading": "Camera",
	},
	{
		"key": "controls/anti_checkers_camera_right", "action": CAMERA_RIGHT_ACTION,
		"default": KEY_RIGHT, "title": "Camera right",
		"description": "Orbit right in solo, or pan right in local play.",
		"player": -1, "heading": "Camera",
	},
	{
		"key": "controls/anti_checkers_camera_reset", "action": CAMERA_RESET_ACTION,
		"default": KEY_HOME, "title": "Reset camera",
		"description": "Restore the full board and your match's starting perspective.",
		"player": -1, "heading": "Camera",
	},
]
