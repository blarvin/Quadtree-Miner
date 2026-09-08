# Quadtree Miner

2D side-scrolling mining sandbox for one question: is the quadtree terrain a
good game system? **`GDD_MinerGame.md` is the specification.** Read the
relevant section before changing anything in `scripts/core/`.

## Engine

- Godot **4.7.2 stable**, GDScript, GL Compatibility renderer, 640×360
  framebuffer integer-scaled, 3 framebuffer px per atom.
- Engine binary: `C:\Users\blarv\Desktop\GODOT\Godot_v4.7.2-stable_win64.exe`
  (use `..._console.exe` for headless — it writes to stdout).

## Code search

**Use the jcodemunch MCP tools instead of Grep/Read/Glob for this repo.** Call
`jcodemunch_guide` first and follow its instructions strictly — it ships the
version-current policy, so do not work from a pasted copy of it. This path is
not indexed yet: `index_folder` it once, then `search_symbols` /
`get_context_bundle` / `search_text` in place of a grep sweep.

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
| `scripts/game/` | Player, ladders, scene glue. |
| `scripts/render/` | Terrain drawing. |
| `data/templates/` | Block templates (GDD §4). JSON keys starting with `_` are notes. |
| `data/maps/` | The dev map (GDD §2): a character grid plus a legend. |
| `tests/` | `test_*.gd` suites + `run_tests.gd`. |

## Invariants — settled in the GDD; do not relitigate them in code

1. **Name nodes by size in atoms, never by depth.** No `B1..B5`, `L0..L4`. (§1)
2. **Quad indices are 0-based row-major**: Q0=TL, Q1=TR, Q2=BL, Q3=BR.
   Bit 0 = right, bit 1 = bottom. +Y is down. `tests/test_quad.gd` locks it. (§1)
3. **Void is the absence of a block.** No air material, no air block. (§1)
4. **Templates are sparse override trees**: a quad-path (`Q1.Q2`) applies to
   that node and below; a size key (`size:2`) applies to any node of that size
   without inheriting. Overrides are partial patches. Resolution:
   `default → size:N → paths shallowest to deepest`, so position beats size.
   An unstruck block is one node. (§4.1)
5. **Rules are template-authoritative**: looked up by path, never copied onto
   a node. (§4.2)
6. **Fractures are derived from the tree.** Never add a `fracture_template`;
   never add a `reveal_depth` — a terminal node is inherently opaque.
   Damage shows as crack extent, never as a tint. (§5.2, §5.3)
7. **One strike = one HP at one atom.** The 8-atom cross-section is covered by
   cycling the impact point across strikes, never by widening the hit. (§6.1)
8. **`Node.size` is a derived cache, never serialized.** Written only on load
   and in `subdivide()`. `damage` and `revealed` are persisted. (§7, §5.1)

## Scope

The experiment is the terrain system. No economy, shop, upgrades, air clock,
darkness, or physics — if a change is not about digging feeling good, say so
rather than building it.

## Style

Comments say *what* and cite a GDD section. The argument lives in the GDD;
do not restate it in code, tests, or JSON notes.
