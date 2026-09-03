# Quadtree Miner

2D side-scrolling mining game. **`GDD_MinerGame.md` is the specification** —
read the relevant section before changing anything in `scripts/core/`.
Section references below point into it.

## Engine

- Godot **4.7.2 stable**, GDScript, GL Compatibility renderer.
- Engine binary: `C:\Users\blarv\Desktop\GODOT\Godot_v4.7.2-stable_win64.exe`
  (use `..._console.exe` for headless — it writes to stdout).

## Commands

```bash
GODOT="/c/Users/blarv/Desktop/GODOT/Godot_v4.7.2-stable_win64_console.exe"

"$GODOT" --headless --path . --script res://tests/run_tests.gd   # tests (exit 1 on fail)
"$GODOT" --headless --path . --import                            # reimport assets
"$GODOT" --path . scenes/main.tscn                               # run the game
"$GODOT" --path . scenes/debug_map.tscn                          # look at the dev map
```

`scenes/debug_map.tscn` is a **throwaway** (`scripts/render/debug_map_view.gd`):
colour class + block borders at true scale, no fractures, no player. It exists
to answer GDD §4.1.2's prerequisite — *are block borders legible on untouched
terrain?* — which no test can answer. WASD/arrows pan, TAB overview, 1-4 jump
to the set pieces. Delete it when the real renderer lands.

**Run `--import` after adding any file with a new `class_name`.** The
script-class cache is written by the editor, so a class created outside it is
invisible to `--script` and every use fails with *"Could not find type X"*.

Tests are plain GDScript, no addon. A file in `tests/` named `test_*.gd`
is auto-discovered; every method named `test_*` runs. Use
`runner.check(cond, msg)` / `runner.check_eq(actual, expected, msg)`.

**The runner does not catch runtime errors.** A test that hits one (a failed
cast, a null deref) aborts mid-method, and the run still prints `0 failed` and
exits 0. Read the output for `SCRIPT ERROR`, not just the tally.

## Layout

| Path | Holds |
|---|---|
| `scripts/core/` | Engine-pure logic — quadtree, templates, damage, world. **No `Node` dependency**, so it stays headless-testable. |
| `scripts/game/` | Player, tools, air, scene glue. |
| `scripts/render/` | Fracture/terrain drawing. |
| `data/templates/` | Block templates (GDD §4.7). |
| `data/maps/` | Hand-authored world data (GDD §4.1.0). |
| `tests/` | `test_*.gd` suites + `run_tests.gd`. |
| `art/legibility/` | The GDD §6 legibility test — do this before building the renderer. |

## Invariants — the GDD argues these at length; do not relitigate them in code

1. **Name nodes by size in atoms, never by depth.** `size 16`, `size 4`,
   `atom`. Never `B1..B5`, `L0..L4`, "level 3". Depth is derived
   (`Atoms.depth_of`), not an identity. (§4.0)
2. **+Y is down.** (§4.0.1)
3. **Quad indices are 0-based row-major**: Q0=TL, Q1=TR, Q2=BL, Q3=BR.
   Bit 0 = "am I right?", bit 1 = "am I bottom?". Do not switch to 1-based
   or to winding order — sibling patterns (§4.4.2) are bit ops *because*
   of this, and `tests/test_quad.gd` locks it. (§4.0.2)
4. **Void is the absence of a block.** There is no air material, no air
   block, no void object. (§4.1.1)
5. **Templates are sparse override trees**, never flat 256-cell arrays.
   `default_rule` + overrides under **two kinds of key**: a **quad-path**
   (`Q1.Q2`) addresses *position* and applies to that node *and below*; a
   **size key** (`size:2`) addresses *physical size* and applies to any node of
   that edge length without inheriting downward. Overrides are **partial
   patches** — an absent field means inherit, never reset. Resolution, later
   wins: `default → size:N → paths shallowest to deepest`, so **position beats
   size**. An unstruck block is **one node in memory**. (§4.7.1)
6. **Rules are template-authoritative** — looked up by path at break time,
   never copied/frozen onto the node. (§4.7.2)
7. **`damage` and `revealed` are persisted world state**, not decoration.
   Fractures never heal. (§4.6.1)
8. **Fractures are derived from the override tree, rendered.** Never add a
   `fracture_template` field — a second authored copy of the structure can
   disagree with it, and then the picture lies about the rules. (§4.6.2)
9. **Never add a `reveal_depth` field.** Opacity is structural: a fracture
   can only draw boundaries between children that *exist*, so a terminal
   node (`on_break: mine`) is inherently opaque. (§4.6.3)
10. **One strike = one HP at one atom, always.** A tool never hits multiple
    nodes per strike. The 8-atom cross-section is covered *temporally* by
    cycling the impact point across successive strikes, not by widening the
    hit region. (§4.3.2)
11. **`Node.size` is a derived cache, never serialized.** Single writer:
    load (`BlockInstance.size >> depth`) and subdivide
    (`child.size = parent.size >> 1`). Assert power-of-two ≥ 1. (§5.2)
12. **`on_break: mine` is terminal** — the node is destroyed and children are
    never instantiated, so overrides beneath that path are never read.
    `drop` separately decides whether anything comes out; `drop: none` means
    it vanishes. Drop *count* is derived: `(node.size / drop.size)²`. (§4.3, §5.1)
13. **Enum for names, integer for quantities.** `on_break` and
    `pass_through` are enums; `size` is an int in atoms. (§5.3)

## Scope discipline

The GDD stages the build (§6). **Phase 0 is the vertical slice: does digging
feel good?** No shop, no economy, no upgrades, no painter, no physics — those
are §6 Phase 1+ and §7. If a change is not in Phase 0, say so rather than
building it.
