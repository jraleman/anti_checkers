# Anti Checkers

**Jump. Give. Win.** An untimed, 3D giveaway-checkers companion to Anti-Chess,
with its own rules, original turned checkers, walnut table, garnet/ivory
identity and sound cues. It inherits `GameShell` and uses the host project's
Compatibility renderer; no plugin, external asset or new autoload is needed.

From `godot-base`:

```powershell
godot --path . -- --game=anti_checkers
```

From this folder:

```powershell
godot --path ..\.. -- --game=anti_checkers
```

The existing catalog discovers `game.gd`. A standalone launch follows the
studio sting, skippable game opening, themed title screen, mode selection and
instructions. `--game=all` includes it in the collection picker. Its original
poster and written walkthrough work without a tutorial video.

## Rules and modes

- **English/American, 8 x 8:** twelve men per side on dark squares. **Red
  always starts.** Men step or jump diagonally forward only.
- **Captures are compulsory across the whole side.** Choose any available
  jump; the longest chain is not required. Once a jump starts, continue with
  the **same checker** until no further jump is available.
- **Crowning ends the turn.** A man reaching the far row becomes a stacked
  king, but cannot immediately jump backward. Kings step one square or jump
  one adjacent enemy in either diagonal direction; there are no flying kings.
- **Win by having no pieces, or no legal move on your turn.** Taking the
  opponent's final checker makes the opponent win. A blocked player wins
  regardless of the remaining piece counts.
- Three occurrences of the same completed-turn position automatically draw,
  as do 80 consecutive quiet king turns (40 moves each with no capture or man
  move). Wins take precedence over draws.

**Solo** offers Red or Ivory against a seeded CPU, with Casual, Thoughtful
and Cunning settings. The latter two plan replies incrementally rather than
blocking the frame. **Local multiplayer** is two humans taking turns on one
device with shared controls and an overhead camera. Mobile keeps the same
solo side choice.

The manifest opts out of the shell's arcade Timer/Lives rules without changing
the saved preference. Resigning requires confirmation and gives the opponent
the win. Leaving through pause abandons the match without recording a result.

## Controls and accessibility

Click or tap a checker, then a destination. **WASD** browses squares,
**Enter** selects or moves, and **Backspace** clears a selection. Cancelling
does not undo a jump or let you abandon a compulsory chain.

**Right drag or held arrow keys** orbit in solo and pan without tilting in
local play. The **wheel or +/- buttons** zoom, **Home / Reset View** restores
the entire table, **F / Flip** changes perspective, and **Esc** opens the
shared pause menu. All twelve board/camera keys are rebindable. Cursor
directions follow the visible board after orbiting or flipping.

Legal steps use dots, jumps use outlines and an `x`, and the turn panel
explicitly announces compulsory captures and same-checker continuations.
Optional R/I labels, double-height crowned kings, Red/Ivory names and the
host's P1/P2 identity labels supplement colour. Captured checkers move into
their owner's visible **given away** tray. The ledger keeps a whole chain on
one line, for example `c3xe5xg7`; `=K` marks crowning.

Reduced motion settles jumps and flips immediately, while preserving direct
camera control. Captures, crowns and outcomes have audio captions; all sounds
use the shared volume/mute controls. There are no essential sound-only cues,
ambient camera motion or gameplay flashes. The board stays above a scrollable
briefing in portrait, with touch-sized camera and resignation controls.

Side and CPU difficulty apply **next match**, including replay. Hints and
piece labels update live. CPU work and the final-jump hold pause with the
scene and are cancelled on replay or exit.

## Results and identity

The live HUD shows **pieces left**; results show **pieces given away**.
Winner copy always comes from the model, not a comparison of the scores.
A multi-jump chain counts as **one turn**, while every captured checker is
counted separately.

P1 is always the human in solo, including when playing Ivory. Results, stats,
achievement attribution and score values follow that seat order; the
game-owned scorecard art explicitly labels its Red/Ivory counts. The QR links
to the real studio website, not an invented stats service.

## Source and development

| Path | Responsibility |
| --- | --- |
| `game.gd`, `anti_checkers_options.gd` | Manifest, rules copy, identity and constants-only settings |
| `board/checkers_state.gd`, `board/cpu_player.gd` | Node-free rules and bounded, seeded giveaway search |
| `board/checkers_mesh.gd`, `board/board_view.gd` | Original batched geometry, read-only world, animation and camera |
| `board/checkers_audio.gd` | Four original short PCM cues, generated once per scene |
| `ui/board_input.gd`, `ui/match_panel.gd`, `ui/match_dialog.gd` | Projected picking, accessible briefing and explicit resignation |
| `gameplay.gd`, `gameplay.tscn` | Inherited shell integration and match lifecycle |
| `assets/`, `ui/share_art.*`, `ui/menu_background.*`, `intro.tscn` | Original artwork, standalone presentation and opening |

There are no dependencies on another game's folder. The 64 tiles and four
side/type checker groups are `MultiMesh` batches; the graphical regression
keeps the 3D world within **40 draw calls including shadows**.

Run from this folder, sequentially:

```powershell
godot --headless --path ..\.. --import
godot --headless --path ..\.. --script res://games/anti_checkers/tests/checkers_state_test.gd -- --game=all
godot --headless --path ..\.. --script res://games/anti_checkers/tests/cpu_player_test.gd -- --game=all
godot --headless --path ..\.. --script res://games/anti_checkers/tests/anti_checkers_scene_test.gd -- --game=all
godot --audio-driver Dummy --path ..\.. --script res://games/anti_checkers/tests/board_view_test.gd -- --game=all
```

The last command requires a graphics window. Add
`--anti-checkers-capture-dir=<absolute directory>` after `--` to save actual
landscape, portrait, both solo sides, jump-chain, crowning, resignation,
results, scorecard and standalone-title images. Headless output alone is not
visual coverage.

The scene fixture suppresses achievement/progression writes and restores
settings. Shared coverage is already catalog-driven: `game_shell_test.gd`,
`game_options_test.gd`, `game_select_test.gd` and `single_game_test.gd` include
the new manifest automatically. The standalone regression also runs with
`--game=anti_checkers`. Use an isolated user profile for shared tests that
exercise persistence or complete real rounds.
