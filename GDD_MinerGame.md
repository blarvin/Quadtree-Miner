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
- **A block boundary is the edge of a wave.** `pass_through` never crosses one
  (§3.2), so the same ground painted at a smaller size is not a subdivision of
  the larger one — it is a different material. `sand` is 2 strikes as one B16
  and 8 as four B8s: four separate collapses, each stopping dead at its seam,
  each revealing only itself. Painting partitions propagation and information,
  not just the ground.
- Which is why a **template made of templates** is not wanted. Everything it
  could compose, placement already composes, and honestly — the border draws.
  The one thing it would add is hiding the seams until the first strike, and
  that is the only part worth refusing. Rules stay looked up by path from one
  template (§4.2). A stamp that places a 2 × 2 of blocks in a click belongs in
  the editor, where it is a placement macro and not a new kind of thing.
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
- `shatter` → the whole subtree is fractured in one act: every descendant
  instantiated and revealed, down to wherever its own rule turns terminal.
  **The blow is absorbed.** A shatter has no surplus to pass anywhere, and
  that is what makes it exactly one strike rather than a tuning problem.

The first two act on a node; `shatter` acts on a subtree. It is the only way
to reach the floor of a block in a single strike without mining anything on
the way, and it is what a material does when it fails as a mass rather than
at a point.

`mine` is terminal: children are never instantiated. A shatter stops at a
terminal child — exposed, but not opened, because it has no inside to show
(§5.2). It reveals everything it does open, so **do not hide a core in a
shattering material**; it is a loud property, not a subtle one.

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
- **`pass_through`** (+ falloff): leftover HP flows outward from the node that
  broke — mined or subdivided, either way. Neighbours are **spatial, not
  sibling indices**: one node-width out from the node's centre, delivered to
  whatever owns that point, at whatever size that turns out to be. A wave
  therefore crosses parents instead of rattling around inside one; sibling
  bit-flips would trap a collapse in a box four nodes wide. It never leaves
  the block (§2).

  | Pattern | Reads as | Goes |
  | --- | --- | --- |
  | `none` | brittle in place | — |
  | `inline` | grain | both ways along the blow's axis |
  | `lateral` | shattering | left and right |
  | `radial` | crumbling outward | all eight; a diagonal is a step further, so falloff twice |
  | `downward` | collapsing | down |

  Each neighbour is sent a **copy** of the surplus, never a share, so a
  pattern's reach does not depend on how many neighbours happen to exist and
  `falloff` is the only damping. At `falloff: 1` a hop costs exactly the
  target's `resistance`, so a collapse reaches `hp / resistance` hops and
  clears a **square** — a diagonal costs no more than a step. Below 1 the
  diagonals pay twice and the hole rounds off. **Reach is the authoring
  dial**: one number decides whether a collapse takes the block or craters
  it. A node takes one delivery per strike and
  breaks at most once, so the block's own node count bounds the wave — it
  needs no iteration cap.

**A wave loads leaves sparsely.** `pass_through` spreads at the size that
broke, while `pass_down` reaches one child. A strike that fractures a block
down to size 2 therefore leaves damage on a handful of its cells, not on all
of them. So a material cannot be loaded to the brink everywhere by one blow
and collapsed by the next: **wholesale collapse has to happen in the strike
that starts it**, or not at all.

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
4. **sand** — the trap, in two beats. The first strike shatters the block to
   its 256 atoms and is spent doing it: every grain stands, the whole
   fracture on show. The second, landed anywhere in it, costs 0.05 and hands
   the rest sideways through a radial `pass_through`, so the block goes at
   once. Sand is not dug, it is triggered.
5. **hard_stone** — twenty strikes with nothing happening, then one clean
   cross, then terminal at size 8.
6. **stone** — grey fill. Painted at size 4 it is rubble; same colour class
   as hard stone, so only the border says the wall is expensive.

### 4.4 The space of templates

Templates are cheap to write and most of them are not worth playing. These
are the axes a template may vary, and the seams where the space divides into
kinds rather than degrees.

#### Axes

| Axis | Authored as | What it is |
| --- | --- | --- |
| **Floor** | the size carrying `on_break: mine` | the grain of the hole — the smallest bite that can be taken |
| **Cost curve** | `resistance` per `size:N` | flat grind, front-loaded look, or back-loaded surprise |
| **Friability** | `resistance` below tool HP, with `pass_down` / `pass_through` | whether a blow stops at the wall, falls through it, or takes the room with it |
| **Contents** | path overrides (`Q1.Q2`) | that this block has an inside |
| **Placement** | the block's size on the map (§2) | the same template as different play, at no cost |

**Floor is the tunnelling lever.** A floor of 2 lets a corridor be cut to the
body; a floor of 8 means every bite is 64 atoms, so the material cannot be
threaded at all, only cleared. Whether terrain is negotiated or erased is
decided here, not by resistance.

#### Two seams

**Terminal at the root is not a shallow tree — it is a tile.** A block that
never subdivides is outside the system being tested. That is its use: it makes
the first subdividing block a discovery, so the upper world can be tiles and
the quadtree can be what you find by going down.

**Size keys are physics; path keys are contents.** A `size:N` override says how
the substance behaves at scale: it is a curve, it does not inherit, and it is
what makes a material a material. A quad-path override says what is inside
*this* block: it is positional, it inherits downward, it is an object. A
template is one material plus its contents, and the two are authored
differently.

#### The 4× law

Each level of depth roughly quadruples the cost of clearing, because there are
four times as many nodes to break. Strikes with a 1 HP tool to empty one
size-16 block, against strikes to cut an 8-atom corridor through it. This is
the full inventory; §4.3 describes only the six the spec started with:

| Template | Floor | Clear | Tunnel |
| --- | --- | --- | --- |
| `easy_dirt` | root | 3 | 3 |
| `sand` | 1 | 2 | 2 |
| `mid_dirt` | 8 | 5 | 3 |
| `firm_sand` | 1 | 7 | 4 |
| `gravel` | 2 | 14 | 10 top, 8 bottom |
| `honest_dirt` | 2 | 86 | 44 |
| `hard_stone` | 8 | 100 | 60 |
| `stone` | 2 | 171 | 87 |
| `liar_dirt` | 2 | 233 | 44 top, 191 bottom |

`sand` is the row that is not really a cost: two strikes take a block from
whole to gone, wherever they land, and neither of them is a dig. It is the
only material whose price does not scale with what you want from it — and
the only one that cannot be tunnelled *because* it is cheap, since the second
strike takes the room with it whether or not that is what you wanted.

`firm_sand` is `sand` with one number changed — a grain resists 0.15 instead
of 0.05 — and it is a different material to be in: the block still shatters
whole, but the collapse stops six hops out and leaves an eleven-atom room
with the rind standing. The difference is a **silhouette, not a clock**,
which is the only kind of difference that earns a second template.

`gravel` is the seam made concrete. Its `size:2` key is physics — shatter to
64 lumps, collapse at 0.3 a cell — and four quad-paths are contents: three
stubborn cells and one size-4 lump that ride out a collapse and stand in the
crater afterwards. Nothing announces them; they are terminal, so they have no
fracture to show. **The leftovers are the tell**, which is the honest way for
a material to be heterogeneous — you learn gravel by seeing what it leaves,
not by being told. It is also why gravel's tunnel cost differs top from
bottom: the lumps are not evenly spread, so where you cut matters.

Two readings. First, the range is two orders of magnitude, and it is bought
almost entirely with depth: `stone` and `honest_dirt` differ by 2× in
resistance and 2× in cost, while `mid_dirt` and `honest_dirt` differ by one
level of floor and 17× in cost. Second, `liar_dirt` is the only row where the
tunnel number depends on *where* you cut. That column is the system's whole
claim: hardness that is a property of place, not of a number.

The tool's strike rate is the exchange rate between depth and player time, and
with no upgrades in scope (§Scope) it is a constant. So deep terrain is not
cleared, it is threaded — and the floor of the deep materials is what decides
whether threading is possible.

#### Materials are vocabulary; templates are grammar

A material is a colour and a name; the colour class above it is deliberately
lossy (§5). A new material buys a word, a new template buys a sentence.
**Five materials are enough.** The scarce resource is not colours but lessons
the player can hold: three or four behaviours per depth band, so that "brown,
this deep, means X" is a proposition that can be learned — and then violated.

**Two templates that differ only in speed are one template.** If the player
cannot name the difference without counting strikes, the difference is not
there. Separation must come from floor, contents, or friability.

#### What a block may confess

Before the first strike: colour class and border size. Nothing else. Reveal is
only ever by strike (§5.1), and behaviour is disclosed only through the
fracture channel — never by tint, never by a colour per template. Fractures
are the third read that no tile game has, and an editor must not let an author
route information around them.

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

**A Fact says nothing about what is under it.** A node fractured into four
terminal children draws the same cross as one fractured into four that will
keep dividing, so `mid_dirt` and `honest_dirt` are indistinguishable until
the next strike answers it. That is the channel's real gap, and the answer is
already in hand: whether a child is terminal is `on_break` read from the
template, derived per frame and stored nowhere, so a **last division** can be
drawn differently from a continuing one without a field and without breaking
this section. The next work on fractures starts here.

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
