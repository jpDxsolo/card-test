# Pyramid Solitaire — Implementation Plan

A data-driven Pyramid solitaire built in Godot 4.7, designed so that the many published
variants (Relaxed, Tut's Tomb, Apophis, Giza, Triangle, reserve rows, cells, redeals,
Spanish deck) are **configuration, not code**.

---

## 1. Decisions locked in

| Decision | Choice | Consequence |
|---|---|---|
| Language | GDScript primary | C# kept in mind for the solver hot loop — **see the web-export caveat in §10** |
| Card art | Kenney pack (both sheet + individual PNGs on hand), swappable later | All art access goes through a `CardTheme` resource; swapping packs is a one-file change |
| Input | Click-to-select (tap A, tap B) | No drop-target logic; works on touch and mouse identically |
| Target | Web export | Single-atlas texture, small asset budget, threading caveats |
| Screen shape | Responsive — landscape **and** portrait | Layout must be computed, never hand-placed. This is a day-one architectural requirement |
| Variant scope for v1 | Config system + classic Pyramid only | Build the abstraction properly, prove it with 1–2 config-only variants at the end |
| Features | Hint system, sound + music | Hints need legal-move enumeration, which we need anyway for game-over detection |
| Deal fairness | Both random and guaranteed-winnable modes | Requires a solver — the single largest piece of optional work |

### Where the proof of concept lands

The current POC (`card.tscn` + `card.gd`) is two `Area2D` cards with a drag script and
64×64 placeholder textures scaled up ~3×. It validated that Godot input and scene
instancing work, and that's all it needs to have done.

**What carries forward:** the scene-instancing pattern, and `Area2D` as a proven hit target.
**What gets replaced:** the drag logic (§9), the per-card `Sprite2D` texture assignment (§6),
and the hand-placed `position` values in `board.tscn` (§7). Nothing in the POC is load-bearing
— treat it as a spike to be deleted, not a base to extend.

---

## 2. Guiding principle

> **The rules engine must not know that Godot exists.**

Every core file is pure GDScript operating on plain data — no `Node`, no `Vector2`, no
textures, no tweens. This buys three things that are individually worth the discipline and
collectively non-negotiable:

1. **Testability.** Rules can be tested headlessly, with no scene tree and no rendering.
2. **A possible solver.** The solver must simulate hundreds of thousands of states per
   deal. That is only feasible against plain data — never against scene nodes.
3. **Variants as data.** When the rules are a function of a config object rather than a
   web of `if` statements scattered through view code, a new variant is a `.tres` file.

The corollary that's easy to violate later: **the view never mutates state, and the state
never touches the view.** All communication is one-way (state → events → view) plus intents
(input → controller → engine).

---

## 3. Architecture

```
   ┌──────────────────────────────────────────────────────────────┐
   │  PRESENTATION  (Godot nodes — knows nothing about rules)     │
   │                                                              │
   │   BoardView ── CardNode ×52    LayoutResolver                │
   │       │                        AnimationDirector             │
   │       │                        CardTheme / CardAtlas         │
   └───────┼──────────────────────────────────────────────────────┘
           │  events (card_matched, card_dealt, …)   ▲ intents
           ▼                                          │ (slot clicked)
   ┌──────────────────────────────────────────────────────────────┐
   │  GameController — the only place both sides are visible       │
   └───────┬──────────────────────────────────────────────────────┘
           │  Move objects
           ▼
   ┌──────────────────────────────────────────────────────────────┐
   │  CORE  (pure GDScript — no Node, no Vector2, no Texture)      │
   │                                                              │
   │   RulesEngine ── GameState ── SlotGraph                      │
   │        │            │                                        │
   │      Ruleset ◄──────┘         Move   Card   Deck             │
   └───────┬──────────────────────────────────────────────────────┘
           │
           ▼
   ┌──────────────────────────────────────────────────────────────┐
   │  SOLVER  (pure, offline or background)                       │
   │   PyramidSolver ── DealGenerator                             │
   └──────────────────────────────────────────────────────────────┘
```

### Core types

**`Card`** — an integer `0..51`. Suit is `id / 13`, rank is `id % 13`. Integers, not
objects, because the solver will copy and hash these by the million. Human-readable
wrappers exist only for debugging.

**`Ruleset`** *(Resource)* — the variant config. Full schema in §5.

**`SlotGraph`** — the tableau's shape, generated from the `Ruleset` at deal time. See §4;
this is the heart of the variant system.

**`GameState`** — the entire mutable game:
```gdscript
class GameState:
    var tableau: PackedInt32Array   # slot index -> card id, or -1 if removed
    var stock: PackedInt32Array     # remaining stock, in order
    var stock_index: int            # how far we've drawn
    var wastes: Array               # 1 or 3 piles (Apophis), each a PackedInt32Array
    var foundation: PackedInt32Array
    var cells: PackedInt32Array
    var redeals_used: int
```
It must be cheap to `duplicate()` and cheap to hash. Packed arrays give us both.

**`Move`** — a plain data object, *not* a function call:
```gdscript
enum MoveType { MATCH_PAIR, DISCARD_SINGLE, DRAW_STOCK, RECYCLE_WASTE, TO_CELL }
class Move:
    var type: MoveType
    var a: int    # source location id (encodes zone + index)
    var b: int    # second location, or -1
```

Representing moves as data rather than behaviour is what makes the solver, the hint
system, and replay/serialisation all fall out of the same mechanism.

> **Note on undo:** you didn't select undo, so we won't build it. But since moves are
> already data, adding undo later is a `_move_history: Array[Move]` plus an `unapply()`
> function — roughly an afternoon. Building the engine *any other way* would make undo a
> rewrite. Flagging this so the choice stays cheap to reverse.

**`RulesEngine`** — stateless functions, the entire public rules API:
```gdscript
static func deal(ruleset, rng_seed) -> GameState
static func get_legal_moves(state, ruleset) -> Array[Move]
static func apply(state, move, ruleset) -> void      # mutates in place
static func is_exposed(state, slot_id) -> bool
static func is_won(state, ruleset) -> bool
static func is_stuck(state, ruleset) -> bool         # == get_legal_moves().is_empty()
static func score(state, ruleset) -> int
```

Note that `is_stuck` is defined in terms of `get_legal_moves`. One source of truth for
"what can the player do" feeds game-over detection, hints, and the solver alike. Any time
you're tempted to write a second, faster, special-cased version of this — don't. That
divergence is where solitaire bugs live.

---

## 4. The key insight: the tableau is a slot graph

This is the design decision the whole variant system rests on, so it's worth stating
plainly.

Don't model the pyramid as a pyramid. Model it as a **directed graph of slots**, where each
slot lists the slots that cover it:

```gdscript
class Slot:
    var id: int
    var covered_by: PackedInt32Array   # slots that must be empty before this is playable
    var grid_pos: Vector2              # abstract layout units, NOT pixels
    var zone: int                      # TABLEAU, RESERVE, GIZA_COLUMN, …
    var face_up: bool
```

A slot is **exposed** when every slot in `covered_by` is empty. That single rule, applied to
different graphs, produces every published variant's tableau:

| Variant | Slot graph |
|---|---|
| Classic Pyramid | 7 rows, slot `(r,c)` covered by `(r+1,c)` and `(r+1,c+1)` |
| Triangle | The same graph inverted — row 1 has 7, row 7 has 1 |
| Giza | Pyramid + 8 columns of 3, each card covered by the one below it |
| Reserve row | Pyramid + 7 slots with empty `covered_by` (always exposed) |
| 6-row pyramid (21 cards) | Same generator, `rows = 6` |

So `SlotGraph.build(ruleset)` is a small factory with one branch per `tableau_shape`, and
**everything downstream — exposure checks, hit testing, layout, the solver — is
shape-agnostic.** Adding "Triangle" is one generator function and a `.tres` file. No changes
to the engine, the view, or the solver.

`grid_pos` is in card-width units, not pixels. Layout converts to pixels at render time
(§7), which is what makes the same graph work in both orientations.

---

## 5. Ruleset schema

A single `Resource`, saved as `.tres` files under `data/rulesets/`. Every field below exists
to express at least one documented variant.

```gdscript
class_name Ruleset extends Resource

# --- Deck -------------------------------------------------------------
@export var deck_composition: DeckType = DeckType.STANDARD_52  # or SPANISH_48
@export var target_sum: int = 13                               # 12 for Spanish deck
@export var single_discard_value: int = 13                     # Kings go alone

# --- Tableau ----------------------------------------------------------
@export var tableau_shape: Shape = Shape.PYRAMID  # PYRAMID | TRIANGLE | GIZA
@export var tableau_rows: int = 7
@export var reserve_count: int = 0                # 6 or 7 for the reserve variant
@export var extra_columns: int = 0                # Giza: 8
@export var extra_column_depth: int = 0           # Giza: 3

# --- Stock / waste ----------------------------------------------------
@export var stock_face_up: bool = false           # true = MS Solitaire Collection style
@export var draw_count: int = 1                   # 3 for Tut's Tomb
@export var waste_pile_count: int = 1             # 3 for Apophis
@export var redeals_allowed: int = 0              # 2 for Par Pyramid, -1 = unlimited

# --- Matching ---------------------------------------------------------
@export var allow_covering_pair: bool = false     # Ace on Queen removable together
@export var cell_count: int = 0
@export var cell_fill_from: FillSource = FillSource.NONE  # TABLEAU | WASTE | BOTH

# --- Win / score ------------------------------------------------------
@export var win_condition: WinCondition = WinCondition.CLEAR_ALL  # CLEAR_TABLEAU = Relaxed
```

Two fields deserve comment, because they're the ones that will bite:

**`allow_covering_pair`** — the "an exposed Ace may be removed together with the Queen it
covers, provided nothing else covers either" rule. This is the only field that changes the
*shape* of `get_legal_moves` rather than just its parameters: it adds candidate pairs where
one card is not itself exposed. Implement it as an explicitly separate branch in move
generation, and give it its own tests, or it will silently produce illegal moves in the
variants that enable it.

**`win_condition`** — Relaxed vs. Strict Pyramid differ *only* here. It's a satisfying
one-line proof that the config abstraction works, which is why it's the first variant to
add in Milestone 8.

---

## 6. Card art and the sprite sheet

All texture access goes through one resource, so swapping the Kenney pack for your own art
later touches exactly one file:

```gdscript
class_name CardTheme extends Resource

@export var atlas: Texture2D
@export var cell_size: Vector2i        # e.g. 140 x 190
@export var margin: Vector2i           # sheet edge padding
@export var spacing: Vector2i          # gutter between cells
@export var suit_order: Array[String]  # maps suit index -> sheet row
@export var back_cell: Vector2i        # grid coords of the card back
@export var empty_slot_cell: Vector2i  # grid coords of the empty-pile marker
```

### Confirmed sheet layout (Kenney)

The sheet is a **14 × 4 grid, 56 cells** — 52 cards plus four extras in the last column:

| | Columns 0–12 | Column 13 |
|---|---|---|
| Row 0 | A 2 3 4 5 6 7 8 9 10 J Q K — **hearts** | blank white card |
| Row 1 | same ranks — **diamonds** | card back |
| Row 2 | same ranks — **clubs** | red joker |
| Row 3 | same ranks — **spades** | black joker |

So the lookup is trivial: `row = suit`, `col = rank`, with
`suit_order = [hearts, diamonds, clubs, spades]` and rank A→0 … K→12. This means our
`Card` integer encoding (`suit = id / 13`, `col = id % 13`) maps **directly** onto sheet
coordinates with no translation table.

`back_cell = (13, 1)`. `empty_slot_cell = (13, 0)` — the blank white card is exactly the
footprint marker we need for empty stock/waste/foundation piles. Jokers are unused.

### Measured metrics (verified against the sheet, not assumed)

Sheet is **909 × 259**, which forces a unique integer solution for a 14 × 4 grid:

| Field | Value |
|---|---|
| `cell_size` | `(64, 64)` |
| `spacing` | `(1, 1)` |
| `margin` | `(0, 0)` |
| `card_rect` | `(11, 2, 42, 60)` |

`14·64 + 13·1 = 909` and `4·64 + 3·1 = 259`. Grid pitch is 65 px in both axes.

**Cells are square; cards are not.** All 56 cells contain the artwork at exactly
`(11, 2)` size `42 × 60` — measured identical across every cell, with hard-edged alpha
(no anti-aliased fringe) and fully transparent gutters.

**Therefore `AtlasTexture.region` is trimmed to `card_rect`, never the full cell.** 34% of
each cell is transparent padding. Using the full cell would give every card a click target
52% wider than the visible art, and since §9 hit-tests against layout rects on a tableau
where cards deliberately overlap, those phantom zones would overlap each other and land
clicks on the wrong card. `CardTheme.card_size()` returns `(42, 60)` and is the unit
`LayoutResolver` works in, so the trim propagates correctly into §7.

**Spaced vs. packed is moot for this sheet.** The transparent padding leaves a minimum 5 px
guard between adjacent artwork (23 px horizontally). Linear filtering samples a one-texel
neighbourhood, so bleeding cannot occur regardless of which sheet variant is used.

**Open: source resolution.** 42 × 60 upscales ~2.7× on a 1280 × 720 desktop canvas
(height-constrained to roughly 112 × 160 per card in a 7-row pyramid). Expect visible
softness, with the rank glyphs blurring first; portrait mobile is fine at ~1.3×. Deliberately
deferred to M2, when it can be judged on a real screen rather than predicted. Swapping to a
higher-resolution atlas costs one `.tres` edit.

`CardAtlas` is a small autoload that builds and caches 53 `AtlasTexture` instances (52 faces
+ back) once at startup, keyed by card id. `CardNode` then just does
`sprite.texture = CardAtlas.face(card_id)`.

Why an atlas rather than 52 separate PNGs, given you have both: on web it's **one HTTP
request instead of 53**, and it keeps the whole deck in a single GPU texture so the renderer
can batch every card into one draw call. On a card game where 52 sprites are on screen at
once, that's the difference between a smooth and a stuttery deal animation.

All metrics are now measured and recorded above — the theme resource can be authored with
no unknowns.

**Flip animation with an atlas:** tween `scale.x` to 0, swap the texture in a
`tween_callback`, tween `scale.x` back to 1. Cheap, reads as a real flip, and needs no
3D or shader work.

---

## 7. Responsive layout

Because we're supporting both orientations on the web, **no card position is ever authored
by hand.** The current `board.tscn` hardcodes `position = Vector2(429, 85)`; that pattern
does not survive contact with a resizable browser canvas.

```gdscript
class_name LayoutResolver

static func compute(slot_graph, ruleset, viewport: Vector2) -> Dictionary
    # returns { slot_id: Rect2 } in pixels, plus pile anchors
```

The algorithm:

1. Pick a **profile** from the viewport aspect ratio — `landscape` (stock, waste and
   foundation sit beside the pyramid) or `portrait` (they sit below it). Threshold around
   aspect 1.0, with a little hysteresis so a window dragged near-square doesn't flicker
   between profiles.
2. Lay everything out in **card units** — pyramid rows overlap vertically by ~50%, columns
   by 0, and the profile decides where the non-tableau piles anchor.
3. Compute the bounding box in card units, derive `scale = min(vw / bw, vh / bh)` with a
   margin factor, and centre.
4. Convert every `grid_pos` to a pixel `Rect2`.

Hook `get_tree().root.size_changed`, recompute, and tween cards to their new rects over
~0.2s. Resizes then look intentional rather than jarring.

Keep `window/stretch/mode="canvas_items"` (already set) and set the aspect to `expand` so we
get real viewport resizes rather than letterboxing.

---

## 8. Animation

An `AnimationDirector` owns a queue of animation jobs so that sequences can't interleave
into visual garbage. The rule that keeps this simple:

> **State commits immediately; the view catches up asynchronously.**

The engine never waits for a tween. Input is soft-locked only during the deal and the
win sequence. This avoids the classic solitaire bug class where a player double-clicks
during an animation and the board desyncs from the state.

To make that safe, `BoardView` must expose:
```gdscript
func sync_to_state(state: GameState, animate: bool) -> void
```
which can rebuild the entire visual board from state alone. Non-animated sync is the escape
hatch for resume, for "skip animation", and for recovering from any desync — and having it
from the start means you can always assert that the view is a pure function of the state.

Animations to build (all with `create_tween()`):

| Animation | Feel |
|---|---|
| **Deal** | Cards fly from the stock anchor to their slots, staggered ~40 ms, flipping face-up on arrival. Ease out, ~0.3 s each |
| **Select** | Card lifts ~8 px with a subtle glow/outline |
| **Match** | Both cards pulse, then arc to the foundation, scaling down slightly. ~0.4 s |
| **Invalid** | Short horizontal shake, ~0.15 s |
| **Draw / recycle** | Stock → waste slide with a flip; recycle sweeps the waste back |
| **Win** | Foundation cascade |

Put every duration and easing curve in one `TuningConfig` resource. Game feel is found by
iteration, and iteration is only pleasant when the numbers live in one place.

---

## 9. Input

Click-to-select, with hit testing done directly against the `Rect2` map from
`LayoutResolver` — walking slots in reverse z-order (topmost first) and taking the first hit.

This replaces the POC's `Area2D` + `_input_event` approach deliberately. With a pyramid the
cards overlap heavily, so `Area2D` picking requires careful z-index management *and* every
`CollisionShape2D` would need rescaling on every viewport resize. Since `LayoutResolver`
already produces exact rects, testing against them is less code, fully deterministic, and
free of resize bookkeeping.

Interaction rules:
- Click an exposed card → select it. Click it again → deselect.
- A King (or any card equal to `single_discard_value`) → resolves immediately on one click.
- Click a second card → if the pair is a legal move, match it; if not, play the invalid
  shake and make the *new* card the selection (this is friendlier than clearing it).
- Click the stock → draw.
- Non-exposed cards are visually dimmed and ignore input entirely.

---

## 10. Solver and winnable deals

You chose to offer both random and guaranteed-winnable modes, which means writing a
Pyramid solver. This is the most technically interesting part of the project and also the
most likely to eat time, so it's isolated in Milestone 7 and the game is fully playable
without it.

**Approach:** depth-first search with memoisation on a canonical state hash. Because the
shuffle fixes the stock order, a state compresses to roughly:

- 28-bit mask — which tableau slots are still occupied
- 24-bit mask — which stock/waste cards have been removed
- small int — the stock pointer

Search order matters more than raw speed: try forced/obvious moves first (Kings, then pairs
that expose the most new cards), and memoise every state you prove unwinnable. Most deals
resolve in well under a second with a node-count cap as a backstop.

**`DealGenerator.winnable(seed)`** then loops: generate seed → deal → solve → if unsolvable,
advance the seed. Deals are always identified by seed, so a game is reproducible and a
"replay this deal" feature costs nothing.

### ⚠️ Two web-export caveats to settle before Milestone 7

**Threading.** Running the solver on Godot's main thread will hitch the browser. Godot 4 web
exports support threads only when the page is served with COOP/COEP headers
(`SharedArrayBuffer`), which not every host allows — itch.io does, via a project setting.

The robust alternative, and my recommendation: **precompute a pool of winnable seeds
offline** (a headless editor run, or a script executed once) and ship them as
`data/winnable_seeds.json`. Winnable mode then picks a seed from the pool — zero runtime
cost, zero threading risk, and it works identically on every host. Generating a few thousand
seeds takes minutes once and never again.

**C#.** You mentioned C# as a possible fit for hot loops, and the solver is genuinely the
one place it would pay off. But Godot's .NET builds have historically **not supported web
export**, and the project file already carries a `[dotnet]` section with
`assembly_name="CardTest"` — likely from project creation rather than intent. Before
committing to any C#, verify web export support in 4.7 specifically. If it's still
unsupported, C# and your web target are mutually exclusive, and the offline seed-pool
approach removes the performance pressure that motivated C# in the first place. Worth
resolving early; it's a decision that's painful to reverse late.

---

## 11. Hints

`get_legal_moves()` already exists for game-over detection, so a basic hint is just
"highlight the first legal move". Two levels worth building:

- **Basic** — rank legal moves by how many tableau cards they expose, show the best.
- **Smart** *(needs the solver)* — show only moves that preserve winnability, so a hint
  never walks the player into a dead end.

Ship basic hints in Milestone 6; smart hints become available for free once Milestone 7
lands.

---

## 12. Audio

An `AudioManager` autoload with a small bus layout (Master → Music, SFX) and volume
persisted to `user://`. Sounds: card flip, card place, match chime, invalid buzz, deal
whoosh, win fanfare, plus a music loop.

Web-specific: browsers block audio until the first user gesture. Start the music on the
first click rather than on load, or it silently won't play.

---

## 13. File structure

```
res://
├── game/
│   ├── core/                  # pure GDScript — no Node, no Vector2, no Texture
│   │   ├── card.gd
│   │   ├── ruleset.gd
│   │   ├── slot_graph.gd
│   │   ├── game_state.gd
│   │   ├── move.gd
│   │   ├── rules_engine.gd
│   │   └── deck.gd
│   ├── solver/
│   │   ├── pyramid_solver.gd
│   │   └── deal_generator.gd
│   ├── view/
│   │   ├── card_node.gd / .tscn
│   │   ├── board_view.gd / .tscn
│   │   ├── layout_resolver.gd
│   │   ├── animation_director.gd
│   │   ├── card_theme.gd
│   │   └── card_atlas.gd      # autoload
│   ├── ui/
│   │   ├── hud.gd / .tscn
│   │   ├── main_menu.gd / .tscn
│   │   └── game_over.gd / .tscn
│   ├── audio/audio_manager.gd # autoload
│   └── game_controller.gd
├── data/
│   ├── rulesets/classic_pyramid.tres
│   ├── themes/kenney_default.tres
│   ├── tuning.tres
│   └── winnable_seeds.json
├── assets/
│   ├── cards/atlas.png
│   └── audio/
└── tests/
    └── test_rules_engine.gd
```

The POC files (`card.gd`, `card.tscn`, `board.tscn`, the two 64×64 PNGs) are deleted in
Milestone 0.

---

## 14. Milestones

Ordered so that each one ends at a **verifiable checkpoint** — something you can run and
inspect. The engine is built before the visuals, because a rules bug found through an
animation is ten times harder to diagnose than one found through a test.

| # | Milestone | Done when |
|---|---|---|
| **M0** ✅ | Restructure. Directory layout, delete POC, import Kenney atlas, build `CardTheme` + `CardAtlas` | A test scene renders all 52 faces and the back from the atlas |
| **M1** | Core engine, headless. `Card`, `Ruleset`, `SlotGraph`, `GameState`, `Move`, `RulesEngine` | Tests pass: deal produces 28 tableau + 24 stock; exposure is correct; legal moves are correct for hand-built positions |
| **M2** | Static rendering. `LayoutResolver`, `BoardView.sync_to_state(animate=false)` | A dealt pyramid renders correctly, and stays correct when you resize the window and flip orientation |
| **M3** | Input and matching. `GameController`, click-to-select, foundation | Playable, ugly, no animation. You can clear a pyramid |
| **M4** | Stock, waste, game over | Full classic rules playable start to finish; win and stuck states both detected |
| **M5** | Animation. `AnimationDirector`, deal / match / flip / invalid | Feels like a card game |
| **M6** | Polish. Hints, sound, scoring, menu, win/lose screens | Shippable single-variant game |
| **M7** | Solver + winnable deals (incl. the seed-pool decision from §10) | Winnable mode reliably produces solvable deals |
| **M8** | **Variant proof.** Add Relaxed and Triangle | Both added as `.tres` files only. *If either requires an engine change, the abstraction is wrong and we fix it here* |
| **M9** | Web export, load-time budget, mobile-browser touch testing | Playable on itch.io in portrait and landscape |

M8 is the real test of this entire plan. It's placed late deliberately — by then the engine
has been under pressure long enough for any bad abstraction to have shown itself, and the
cost of fixing it is still bounded.

### Current status

**M0 is complete.** `scenes/atlas_check.tscn` renders the full 14 × 4 sheet through the real
`CardAtlas.face()` lookup path; theme metrics in §6 are measured rather than guessed.

Two loose ends carried into M1:

- The POC files (`card.gd`, `card.tscn`, `board.tscn`, `card_clubs_A.png`,
  `card_hearts_Q.png`) are still in the repo root and should be deleted.
- `CardAtlas.back()` and `empty_slot()` are written but not yet exercised by anything.
  `CardNode` picks them up in M2.

**Next: M1** — the pure rules engine, headless and test-first. Nothing in M1 touches a Node.

---

## 15. Testing

Because `game/core/` is pure, tests need no scene tree. A simple headless test runner is
enough to start (GUT is available if we want a real framework later). Minimum coverage
before M5, when animation starts hiding bugs:

- Deal: correct card counts per zone, no duplicates, all 52 accounted for
- Exposure: pyramid corners, mid-row cards, the last row, and after partial clears
- Legal moves: Kings alone, pairs summing to `target_sum`, waste↔tableau, `allow_covering_pair` on and off
- Terminal states: won, stuck, and stuck-but-stock-remaining
- Determinism: the same seed produces the same deal, every time

That last one is quietly the most important — it's what makes every other bug reproducible.

---

## 16. Open questions

1. ~~The Kenney sheet's cell metrics~~ — **resolved**, measured and recorded in §6.
2. **Card source resolution** — 42 × 60 upscales ~2.7× on desktop. Judge at M2 on a real
   screen; swapping atlases is a one-file change. (§6)
3. **Godot 4.7 .NET web export support** — determines whether C# is available at all. (§10)
3. **Portrait pyramid width** — 7 cards across a phone screen is tight. We may need a
   larger row overlap in portrait, or to accept smaller cards. Worth testing on a real
   device at M2 rather than guessing now.
4. **Hosting** — itch.io vs. self-hosted changes whether COOP/COEP headers are available,
   which feeds the §10 threading decision.

---

## 17. Deliberately not in v1

Recorded so these stay conscious choices rather than accidental omissions: undo/redo (§3),
stats and save/resume, daily challenges, animated card backs and themes beyond the swap
mechanism, achievements, and the remaining variants (Apophis, Giza, cells, reserve rows,
Par Pyramid redeals, Spanish deck) — all of which the §5 schema already accommodates when
we want them.
