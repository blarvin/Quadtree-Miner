# Quadtree Miner — spec

A 2D side-scrolling mining sandbox. The subject of the experiment is the
**per-block quadtree terrain system**: whether digging a tree of blocks is a
good game system on its own. Everything here exists to serve that question.
There is no economy, shop, upgrade, air clock, or win state.

Values marked *(untuned)* are starting guesses.

---

## 1. Conventions

- **Atom** — the grid unit: collision, addressing, and the floor on drop size.
- Nodes are named by **edge length in atoms**: `atom` (1), `size 2`, `size 4`,
  `size 8`, `size 16`, `size 32`. Never by tree depth.
- **+Y is down.**
- **Quad indices are 0-based, row-major.**
  `child_index = (x >= mid_x) | ((y >= mid_y) << 1)`; bit 0 = right,
  bit 1 = bottom.

  ```
          +X →
    +Y   Q0 = TL    Q1 = TR
     ↓   Q2 = BL    Q3 = BR
  ```

- **Void is the absence of a block.** No air material, no void object.
  "Is this atom empty?" = "does no block cover it, or is the covering block
  mined out here?"
- Enum for names (`on_break`, `pass_through`, materials); integer for
  quantities (`size`, in atoms).

## 2. World

- A flat spatial index of non-overlapping **square** blocks snapped to the
  atom grid. Gaps of any size are allowed. No global quadtree — each block
  owns its own subdivision tree.
- Dev map: **1024 × 1024 atoms**. A flat array of blocks; no chunking.
- **Block size is an authoring dial that costs no new templates.** The same
  template at size 16 and size 4 is different play. Size must read before the
  first strike, so block borders are drawn on untouched terrain.
- Three visual channels that must not fight: **colour class** (material
  family), **block border** (size), **fracture** (internal structure).
- Scale: 640 × 360 framebuffer, integer-scaled, **3 framebuffer px per atom**.
  A size-16 block is 48 px; every subdivision is a whole pixel count
  (24, 12, 6, 3) and a 1 px border reads at every size.

## 3. Blocks and nodes

A size-16 block subdivides 16 → 8 → 4 → 2 → atom. The atom cannot subdivide.
Size-32 roots are free; the tree just starts higher.

A node stores only instance state:

| Field | Meaning |
| --- | --- |
| `damage` | HP accumulated on this node |
| `revealed` | whether its material and fractures have been shown (§5.1) |
| `children` | four children, or none (the common case) |
| `size` | edge length in atoms; derived cache, not persisted (§7) |

Its **rule** is not stored; it is looked up from the template by quad-path
(§4.2). When `damage` reaches the rule's `resistance` the node breaks:

- `subdivide` → four children of `size / 2`.
- `mine` → the node is destroyed. `drop: null` means it vanishes; otherwise
  it yields `(node.size / drop.size)²` units, added to the counter
  immediately. No pickup entities.

`mine` is terminal: children are never instantiated.

Unstruck siblings keep their own damage at zero, so digging is a wandering
front through the tree. An unstruck block is **one node in memory**.

### 3.1 Damage is HP

A tool delivers HP; the template says what to do with it. `resistance` is a
continuous HP threshold, so propagation falloff is arithmetic. Discrete-hit
tools are tools with HP 1.

### 3.2 Propagation

- **`pass_down`** (bool + `pass_down_falloff` 0..1): leftover HP flows to the
  child under the impact point, potentially cascading size 16 → atom in one
  strike. False discards the surplus and each level is a fresh wall. Only
  expresses itself when a tool overdelivers.
- **`pass_through`** (+ falloff): leftover HP flows to siblings. In the data
  model; not routed yet.

  | Pattern | Reads as | Siblings |
  | --- | --- | --- |
  | `none` | brittle in place | — |
  | `inline` | grain | flip the bit for the blow's axis |
  | `lateral` | shattering | flip bit 0 |
  | `radial` | crumbling outward | all three, falloff by distance |
  | `downward` | collapsing | set bit 1 |

Most of the world should be pass-down fill a decent tool knifes through; a
few walls should be pass-down-false grinds. Target roughly 90/10. *(untuned)*

## 4. Templates

A **block template** is a recipe for one block's per-node rules. Two
independent authored facts: at what node size the material becomes minable
(`on_break: mine` at `size:N`), and at what size the units come out
(`drop.size`).

Materials: dirt, stone, hard stone, sand, coal.

### 4.1 Sparse override trees

A template is a `default_rule` plus overrides under two key kinds:

| Key | Addresses | Applies to | Inherits downward? |
| --- | --- | --- | --- |
| `Q1.Q2` | position | that node and below, until a deeper path says otherwise | yes |
| `size:2` | physical size | any node of that edge length | no |

Overrides are **partial patches**: an absent field means inherit, never reset.
Resolution, later wins, field by field:

```
default_rule  →  size:N for this node's size  →  path overrides, shallowest to deepest
```

Paths resolve last, so **position beats size**.

Quad-paths are root-relative, so `Q0.Q3` is a different physical size under a
size-32 root than a size-16 one; express thresholds by size. A size key above
a block's root is inert, not an error. A path deeper than the atom is an
error, caught when the template is bound to a block size.

### 4.2 Rules are template-authoritative

Children's rules are read from the template by path, never copied onto the
node. Retuning a material applies immediately to a saved world.

### 4.3 The authored templates

The same input must produce different experiences:

1. **honest_dirt** — the baseline. Root `resistance: 2` so the first strike
   is a look and the second breaks; 1 HP per level below; terminal at size 2,
   drops nothing.
2. **liar_dirt** — identical untouched; `Q2` resists 8 all the way down.
   Strike each quadrant once: three crumble, one does not.
3. **gift_stone** — stone with a coal core at `Q1.Q2` that changes only the
   drop, so fracturing shows the coal before it can be reached.
4. **sand** — `pass_down: true`, resistance 0.25: one strike bores a shaft
   through the whole block and you fall.
5. **hard_stone** — twenty strikes with nothing happening, then one clean
   cross, then terminal at size 8.
6. **stone** — grey fill. Painted at size 4 it is rubble; same colour class
   as hard stone, so only the border says the wall is expensive.

## 5. Reveal and fractures

| Layer | Trigger | You learn |
| --- | --- | --- |
| **Colour class** | always visible | family only: brown is dirt *or* sand; grey is stone, hard stone *or* coal. Borders visible, so size. |
| **True nature** | first strike | material + fractures. Persisted. |
| **Hidden core** | breaking the outer layers, sometimes never | a terminal child that fractures cannot show (§5.2). |

Colour class is deliberately lossy: the first strike is the price of
information.

### 5.1 Reveal is persisted state

`damage` and `revealed` are saved with the tree. Fractures never heal.

Striking reveals the node struck **and any sibling sharing its rule**. A
sibling with a different rule (a terminal core) stays unrevealed until struck
itself. Damage that passes down carries reveal with it.

### 5.2 Fractures are derived from structure

Cracks are the override tree, rendered: drawn along the borders of the
children a node *would* subdivide into, and nowhere else. **Never add a**
`fracture_template` **field** — a second copy of the structure can disagree
with it.

A terminal node (`on_break: mine`) has no children, so nothing inside it can
be shown. Opacity is structural; **never add a** `reveal_depth` **field**.

A cross has four states:

| State | Condition | Drawn |
| --- | --- | --- |
| **Nothing yet** | unrevealed leaf | colour class only |
| **Never** | terminal node, or an atom | no cross at any damage |
| **Promise** | revealed leaf that would subdivide | the cross at `extent` (§5.3) |
| **Fact** | node has subdivided | the full cross, permanently |

### 5.3 Extent is damage, drawn

```
extent = tell × (damage / resistance)        clamped 0..1
```

`extent` is the fraction of each arm, from its origin, that is inked. Nothing
is stored: `damage` is persisted and `resistance` is looked up, so a reloaded
world shows the same half-grown cracks.

`tell` is the material's talkativeness and a design lever: `hard_stone` 0
(nothing happening, then one clean cross), `honest_dirt` ~0.6 (you can see it
giving), `sand` 1 (failing before you finish the swing).

**Damage has no channel of its own** — no tint. It shows as crack, or it does
not show.

The renderer tweens between the extent it drew last frame and the extent the
tree implies now, over `growth` seconds. Arms grow from the centre outward; a
struck-edge or impact-quad origin is open, and any impact hint it needs stays
transient.

### 5.4 The style block

Style is a property of the **material**; a template may name a different one
but does not spell one out inline.

```
FractureStyle
  tell          0..1   crack spread before the break (§5.3)
  growth        s      tween time for a change in extent
  jitter        atoms  lateral wander around the true border
  jitter_seed   int    hashed from the node path; stable across frames and saves
  weight        px     framebuffer pixels
  colour
```

Jitter **roughens the line, never moves it** (§5.2).

## 6. Character

An **8 × 8 atom axis-aligned box** on the atom grid, integer position, moving
in 1-atom steps. Movement is mining: four directions, no attack button, no
aim, no tool UI.

**If the way is clear, move. If something blocks you, hit it.**

- A step is legal iff every atom of the box's **leading edge** (8 atoms) is
  void after the step. Partial obstruction counts as blocked.
- A blocked direction held produces **strikes** at the tool's strike rate;
  a tap produces one.
- **Gravity:** with no ladder at the box and no solid atom under it, the box
  falls 1 atom every `1 / FALL_SPEED` seconds. Falling is free.
- **Up:** climbs on a ladder; otherwise strikes the ceiling, and moves only
  if a ladder occupies the destination.
- **Down** strikes the floor; once clear, gravity takes over.
- The character cannot leave the map. Edges are solid.

### 6.1 The impact-point scan

**One strike = one HP at one atom, always.** The character must fit through
the hole it digs, so the 8-atom cross-section is covered **temporally**:
successive strikes cycle the impact point across the obstructing atoms of the
leading edge.

- The scan spans the leading edge perpendicular to the facing axis.
- It covers **only the atoms that obstruct**; void atoms are skipped.
- Order: top to bottom (sideways), left to right (vertical). Deterministic.
- The strike lands on the **nearest solid atom** along the facing axis at that
  scan position. It cannot hit through an intact block.
- The obstructing set is recomputed every strike.

### 6.2 Ladders

A ladder unit is an **8 × 8 atom entity**: exactly the character's box.

- **Placement:** at the character's current position, if that 8 × 8 is
  entirely void and holds no ladder. The unit is spent.
- **Climbing:** while the box overlaps a ladder, gravity is off and up/down
  move 1 atom per step into void.
- **Reach:** the character may climb until its box bottom is at the top of the
  highest ladder atom it overlaps, so it can dig the ceiling and place the
  next unit into the cleared void.
- **Leaving:** walking sideways off a ladder is an ordinary step.
- Ladders do not obstruct strikes and are never damaged.
- No jump: ladders are the only way up.

### 6.3 Values *(all untuned)*

| Constant | Value |
| --- | --- |
| `WALK_SPEED` | 24 atoms/s |
| `FALL_SPEED` | 60 atoms/s |
| `CLIMB_SPEED` | 16 atoms/s |
| `STRIKE_RATE` | 4 strikes/s |
| `PICKAXE_HP` | 1 |
| Start position | box top-left (508, 56) |

## 7. Data model

Persisted form ≠ runtime form. All sizes in atoms.

```
World
  blocks: SpatialIndex<BlockInstance>   # non-overlapping; nothing for void

BlockInstance
  origin: Vector2i                      # atoms
  size: int                             # edge length
  template_id
  root: Node

Node
  damage: float
  revealed: bool                        # only ever set
  children: [Node | null x4] | none     # null slot = mined quadrant;
                                        # none = never subdivided

BlockTemplate
  material_id
  display_skin
  colour_class                          # defaults to the material's
  default_rule: Rule
  overrides: map<key, RulePatch>        # "Q0.Q3" | "size:4"; partial patches
  fracture_style                        # optional; defaults to the material's

Rule
  resistance: float
  on_break: subdivide | mine
  drop: null | {material, size}         # 1 <= drop.size <= node.size, power of two
  pass_down: bool
  pass_down_falloff: float              # 0..1
  pass_through: none|inline|lateral|radial|downward
  pass_through_falloff: float           # 0..1

Ladder
  origin: Vector2i                      # 8x8, atom grid

Player
  origin: Vector2i                      # box top-left, atoms
  coal: int
  ladders: int
```

Save = world blocks (an untouched node is `{}`) + ladders + player.

`Node.size` is **not serialized**. It is written in exactly two places: load
(`BlockInstance.size >> depth`) and subdivide (`parent.size >> 1`).
