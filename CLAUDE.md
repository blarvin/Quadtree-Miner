# Quadtree Miner

2D side-scrolling mining game. **`GDD_MinerGame.md` is the specification.**
Read the relevant section before changing anything in `scripts/core/`.

## Engine

- Godot **4.7.2 stable**, GDScript, GL Compatibility renderer, 640×360
  framebuffer integer-scaled, 3 framebuffer px per atom.
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

**Run `--import` after adding any file with a new `class_name`**, or
`--script` fails with *"Could not find type X"*. If `--import` hangs, kill
stray `Godot_*.exe` processes first.

Tests are plain GDScript, no addon. `tests/test_*.gd` files are
auto-discovered; every `test_*` method runs. Use `runner.check(cond, msg)`
and `runner.check_eq(actual, expected, msg)`. **The runner does not catch
runtime errors**: read the output for `SCRIPT ERROR`, not just the tally.

`scenes/debug_map.tscn` is a throwaway map viewer (colour class + borders,
no fractures, no player). Delete it when the real renderer lands.

## Layout

| Path | Holds |
|---|---|
| `scripts/core/` | Engine-pure logic — quadtree, templates, damage, world, save. **No `Node` dependency**, so it stays headless-testable. |
| `scripts/game/` | Player, air, ladders, scene glue. |
| `scripts/render/` | Terrain drawing. |
| `data/templates/` | Block templates (GDD §4.7). JSON keys starting with `_` are notes. |
| `data/maps/` | The dev map (GDD §4.1.0): a character grid plus a legend. |
| `tests/` | `test_*.gd` suites + `run_tests.gd`. |

## Invariants — argued in the GDD; do not relitigate them in code

1. **Name nodes by size in atoms, never by depth.** No `B1..B5`, `L0..L4`. (§4.0)
2. **+Y is down.** (§4.0.1)
3. **Quad indices are 0-based row-major**: Q0=TL, Q1=TR, Q2=BL, Q3=BR.
   Bit 0 = right, bit 1 = bottom. `tests/test_quad.gd` locks it. (§4.0.2)
4. **Void is the absence of a block.** No air material, no air block. (§4.1.1)
5. **Templates are sparse override trees** with two key kinds: a quad-path
   (`Q1.Q2`) applies to that node and below; a size key (`size:2`) applies to
   any node of that size without inheriting. Overrides are partial patches.
   Resolution: `default → size:N → paths shallowest to deepest`, so position
   beats size. An unstruck block is one node. (§4.7.1)
6. **Rules are template-authoritative**: looked up by path, never copied
   onto a node. (§4.7.2)
7. **`damage` and `revealed` are persisted world state.** Fractures never
   heal. (§4.6.1)
8. **Fractures are derived from the tree.** Never add a `fracture_template`. (§4.6.2)
9. **Never add a `reveal_depth`.** A terminal node is inherently opaque. (§4.6.3)
10. **One strike = one HP at one atom.** The 8-atom cross-section is covered
    by cycling the impact point across strikes, never by widening the hit. (§4.3.2)
11. **`Node.size` is a derived cache, never serialized.** Written only on
    load and in `subdivide()`. (§5.2)
12. **`on_break: mine` is terminal**; children are never instantiated.
    `drop: null` means it vanishes. Drop count is `(node.size / drop.size)²`. (§4.3)
13. **Enum for names, integer for quantities.** (§5.3)
14. **The character is an 8×8 atom box that moves in 1-atom steps.**
    Blocked means strike; clear means move. (§3.1)

## Scope discipline

**Phase 0 is the vertical slice: dig, air, return, die.** No shop, economy,
upgrades, painter, darkness, or physics; those are GDD §6 Phase 1+ and §7.
If a change is not in Phase 0, say so rather than building it.

## Style

Comments say *what* and cite a GDD section. The argument lives in the GDD;
do not restate it in code, tests, or JSON notes.
