# Game Design Document — *Quadtree Miner* (working title)

A 2D side-scrolling mining game about descending a finite, hand-authored
world, managing air instead of health, and paying for every metre back up.
The distinctive technology is a **per-block quadtree terrain system** that
makes digging tactile, readable, and authorable.

Sections 3 and 6 are the Phase-0 contract. Section 4 is the terrain spec.
Numbers marked *(untuned)* are starting values, expected to move under
playtest.

---

## 1. Pillars

1. **Exploration is the spine.** Terrain, economy and air all exist to make descending a finite world tense and rewarding. Progression is spatial.
2. **The terrain is the toy.** Digging must feel physical and legible. Blocks *are* their mining behaviour.
3. **Commitment and consequence.** Air is a chasing clock. Ladders cost real inventory. Every descent is a bet on getting back up.



## 2. Core loop

Dig → gather → return to surface → sell → upgrade → descend deeper. One
persistent world, one surface rest point.

**Phase 0 tests only the inner loop: dig, air, return, die.** No shop, no
economy, no upgrades (§6).

## 3. Player-facing design (Phase 0)


| Element       | Definition                                                                                              |
| ------------- | ------------------------------------------------------------------------------------------------------- |
| **World**     | One persistent, finite, hand-authored world, saved across sessions. Dev map 1024 × 1024 atoms (§4.1.0). |
| **Character** | An 8 × 8 atom box. Walks, climbs ladders, mines in the direction pressed.                               |
| **Air**       | The only health. Drains continuously, faster with depth. Refilled only at the surface.                  |
| **Death**     | Air reaches zero. The world resets to the authored map.                                                 |
| **Win**       | Not in Phase 0. (Later: retrieve the Jewel of Heaven.)                                                  |
| **Inventory** | A coal counter and a ladder counter. Nothing else.                                                      |
| **Ladders**   | Consumable placed items. Fixed starting stock. The only way up.                                         |
| **Reveal**    | Colour class everywhere; true material on first strike (§4.6). No darkness in Phase 0.                  |




### 3.1 Movement, digging, and ladders

Casual feel, mobile potential: the control scheme must survive a thumb on
glass. So **movement is mining**. There is no attack button, no aim, no
tool UI. Four directions are the whole vocabulary.

#### The core rule

**If the way is clear, move. If something blocks you, hit it.**

#### Character and collision

- The character is an **8 × 8 atom axis-aligned box** on the atom grid. Its position is integer atoms.
- It moves in **1-atom steps**. Walking advances one atom every `1 / WALK_SPEED` seconds while a direction is held; a tap advances one atom.
- A step in direction *d* is legal iff every atom of the box's **leading edge** (8 atoms) is void after the step (`World.is_solid` false). Partial obstruction counts as blocked.
- **Gravity:** if no ladder is at the character's position and any of the 8 atoms directly under the box is solid, the character stands. Otherwise it falls 1 atom every `1 / FALL_SPEED` seconds. Falling is free: no damage, no input needed.
- The character cannot leave the map. Map edges are solid for movement.



#### Digging

- Holding a direction that is blocked produces **strikes** at the tool's strike rate; a tap produces one strike. The strike is the atomic mining event (§4.3.2).
- Each strike delivers the tool's HP to **one atom**: the nearest solid atom along the facing axis, chosen from the **obstructing atoms** of the leading edge by the **scan** (§4.3.2).
- Once the leading edge is fully clear the next step is a move, not a strike. Sustained pressure therefore digs, then walks, then digs again.
- **Up:** the same rule. Pressing up when on a ladder climbs; pressing up when not on a ladder strikes whatever is above the box, and moves only if a ladder occupies the destination (§3.1.1). Void above with no ladder means nothing happens.
- **Down:** pressing down strikes the floor. Once the floor under the box is clear, gravity takes over.



#### 3.1.1 Ladders

A ladder unit is an **8 × 8 atom entity** on the atom grid: exactly the
character's box. "How many ladders deep am I" and "how many character-
heights from the surface" are the same number.


|               |                                                                                                                                                                                                                           |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Placement** | `place_ladder` puts a unit at the character's current position, if that 8 × 8 is entirely void and holds no ladder already. The unit is spent.                                                                            |
| **Climbing**  | While the character's box coincides with or overlaps a ladder, gravity is off and **up** moves 1 atom per step, as long as the destination box is void. Down moves down likewise.                                         |
| **Reach**     | The character may climb until the bottom of its box is at the top of the highest ladder atom it overlaps: it stands on the ladder's top. From there it can dig the ceiling and place the next unit into the cleared void. |
| **Leaving**   | Walking left or right off a ladder is an ordinary step; gravity resumes when the box no longer overlaps any ladder.                                                                                                       |
| **Digging**   | Ladders do not obstruct strikes and are never damaged. A ladder can sit in void inside a partially mined block.                                                                                                           |
| **Recovery**  | None in Phase 0. A placed ladder is permanent and spent (§7).                                                                                                                                                             |
| **Stock**     | `LADDER_STOCK` at start. No refill in Phase 0.                                                                                                                                                                            |


**Why no jump:** a jump makes shallow ascents free and collapses the risk of
descending "just a bit further". Ladders-only makes every metre of depth a
resource decision.

#### 3.1.2 Air and the surface

- `AIR_MAX` seconds of air at the surface.
- The **surface** is any position whose box bottom is at or above `SURFACE_Y` (the top of the topsoil, row 4 of the dev map, y = 64). While at the surface, air refills at `AIR_REFILL` per second.
- Below the surface, air drains at `1 + depth_factor` per second, where `depth_factor = (box_bottom_y − SURFACE_Y) / DEPTH_SCALE`. Linear; a first guess.
- Air zero = death: world, character, and ladder stock reset to the authored map. The save file is deleted.



#### 3.1.3 Drops

- Breaking a node with a `drop` **adds the yielded count to the coal counter immediately**. No pickups, no entities, no inventory slots.
- Everything with `drop: null` vanishes.
- Physical `MinedUnit` entities are deferred to Phase 3 (§7).



#### 3.1.4 Starting values *(all untuned)*


| Constant           | Value                                                                          |
| ------------------ | ------------------------------------------------------------------------------ |
| `WALK_SPEED`       | 24 atoms/s                                                                     |
| `FALL_SPEED`       | 60 atoms/s                                                                     |
| `CLIMB_SPEED`      | 16 atoms/s                                                                     |
| `STRIKE_RATE`      | 4 strikes/s                                                                    |
| `PICKAXE_HP`       | 1                                                                              |
| `LADDER_STOCK`     | 20                                                                             |
| `AIR_MAX`          | 60 s                                                                           |
| `AIR_REFILL`       | 20 s of air per second                                                         |
| `SURFACE_Y`        | 64 atoms                                                                       |
| `DEPTH_SCALE`      | 256 atoms (air drains at 2×/s at 256 atoms deep, 5×/s at the bottom)           |
| **Start position** | standing on the topsoil at the map's horizontal centre: box top-left (508, 56) |


---



## 4. The terrain system



### 4.0 Vocabulary: name things by size in atoms

The **atom** is the grid resolution, the collision unit, and the floor on
drop size. A block's **root size** is a per-block convenience; no root is
special.

Nodes are named by **edge length in atoms**: `atom` (size 1), `size 2`,
`size 4`, `size 8`, `size 16`, `size 32`. Tree depth is derived, never an
identity. "Coal drops at size 4" is true in every block regardless of root.

Never reintroduce depth numbering (`B1…B5`, `L0…L4`): a name counted from a
movable end changes meaning when a new root size appears.

#### 4.0.1 +Y is down

Godot's 2D convention. Depth increases with Y.

#### 4.0.2 Quad indices are 0-based, row-major

```
        +X →
  +Y   Q0 = TL    Q1 = TR
   ↓   Q2 = BL    Q3 = BR
```

`child_index = (x >= mid_x) | ((y >= mid_y) << 1)`. Bit 0 = right,
bit 1 = bottom. A packed quad-path is a Morton code; sibling selection for
`pass_through` (§4.4.2) is a bit op. Do not change to 1-based or winding
order. UI may label quads however it likes.

### 4.1 World structure

- A **flat spatial index of non-overlapping square blocks** snapped to the atom grid. Gaps of any size are allowed.
- **No global quadtree.** Each block owns its own subdivision tree.
- Blocks are always square. Non-square regions are several square blocks.



#### 4.1.0 World dimensions

Dev map: **1024 × 1024 atoms** = 64 × 64 cells of 16 = 128 character
heights deep. A flat array of blocks; no chunking. Block count scales with
the map; node count scales with digging (§4.7.1).

#### 4.1.1 Void is the absence of a block

There is no air material, no air block, no void object. "Is this atom
empty?" = "does no block cover it, or is the covering block mined out
here?" Air-the-resource is a number on the player and has no relation to
void space.

#### 4.1.2 Mixed-size packing

**Block size is an authoring dial that costs no new templates.** The same
template at size 16 and size 4 is different play, not different content. A
size-16 hard block embedded in size-4 rubble; a seam of size-2 blocks
through size-16 stone; alternating size-8s. These author routes without
walls.

**Prerequisite: block borders must be legible on untouched terrain**, so
size reads as cost before the first strike. Three visual channels that must
not fight:


| Channel             | Tells you                  |
| ------------------- | -------------------------- |
| Colour class (§4.6) | material family            |
| **Block border**    | size, therefore rough cost |
| Fracture (§4.6.2)   | internal structure         |


**Legibility finding (done):** at 3 framebuffer px per atom in a 640 × 360
target, integer-scaled 3× to 1080p, a size-16 block is 48 framebuffer px,
every subdivision is a whole pixel count (24, 12, 6, 3), and a 1 px border
reads on both size-16 and size-4 blocks. Depth 3–4 fractures are dense but
distinguishable from depth 1–2. This is the game's scale.

### 4.2 The block quadtree

A size-16 block subdivides 16 → 8 → 4 → 2 → atom. The atom cannot
subdivide. Size-32 roots are free; the tree just starts higher.

### 4.3 The node model

Damage is per **leaf node**. A node stores only instance state:


| Field      | Meaning                                                     |
| ---------- | ----------------------------------------------------------- |
| `damage`   | HP accumulated on this node                                 |
| `revealed` | whether its material and fractures have been shown (§4.6.1) |
| `children` | four children, or none (the common case)                    |
| `size`     | edge length in atoms; derived cache, not persisted (§5.2)   |


The node's **rule** is not stored; it is looked up from the template by
quad-path (§4.7.1). When `damage` reaches the rule's `resista`

- `subdivide` → four children of `size / 2`.
- `mine` → the node is destroyed. `drop` decides what comes out: `nnce` the node
breaks:`ull` means it vanishes; otherwise it yields `(node.size / drop.size)²` units.

Unstruck siblings keep their own damage at zero, so digging is a wandering
front through the tree.

#### 4.3.1 Damage is HP

A tool delivers HP; the template says what to do with it. `resistance` is
an HP threshold, continuous so that propagation falloff is arithmetic.
Discrete-hit tools are tools with HP 1.

`pass_down` only expresses itself when a tool **overdelivers**. A 1 HP
pickaxe into a resistance-1 node leaves zero surplus and grinds level by
level regardless of the flag. Resistance values must be tuned against the
tool ladder, never in isolation.

#### 4.3.2 The impact-point scan

**One strike = one HP at one atom, always.** The character must fit through
the hole it digs, and the perpendicular axis is pinned (floor-locked
digging sideways, shaft-locked digging vertically), so the fix is
**temporal**: successive strikes cycle the impact point across the
obstructing atoms of the leading edge.

- The scan spans the leading edge perpendicular to the facing axis: 8 atoms of height facing left/right, 8 of width facing up/down.
- It covers **only the atoms that obstruct**: void atoms are skipped.
- Order: top to bottom (sideways), left to right (vertical). Deterministic. *(untuned)*
- The strike lands on the **nearest solid atom** along the facing axis at that scan position. It cannot hit through an intact block.
- The obstructing set is recomputed every strike, so a cascade that clears several atoms shortens the cycle.

Scan pattern and strike rate are tool properties; later tools vary them.
A steering bias is a Phase-1 idea.

### 4.4 Damage propagation

- **Pass down** (§4.4.1): leftover HP flows to the child under the impact point. Built.
- **Pass through** (§4.4.2): leftover HP flows to siblings. In the data model, not routed until Phase 2.



#### 4.4.1 Pass down

`pass_down: bool` + `pass_down_falloff` (0..1). False: surplus is discarded
and each level is a fresh wall. True: surplus × falloff continues into the
child under the blow, potentially cascading size 16 → atom in one strike.

#### 4.4.2 Pass through

A named pattern, because choosing siblings is the material's character:


| Pattern    | Reads as          | Siblings                         |
| ---------- | ----------------- | -------------------------------- |
| `none`     | brittle in place  | —                                |
| `inline`   | grain             | flip the bit for the blow's axis |
| `lateral`  | shattering        | flip bit 0                       |
| `radial`   | crumbling outward | all three, falloff by distance   |
| `downward` | collapsing        | set bit 1                        |


Each takes a falloff.

#### 4.4.3 The propagation ratio is the feel

Most of the world should be pass-down fill a decent tool knifes through;
a few walls should be pass-down-false grinds. Target roughly 90/10.
Finding good blocks for each is the level design.

### 4.5 The prototype block

**The first strike reveals without subdividing.** Root `resistance: 2`,
not 1: strike one shows the fracture pattern and material, strike two
breaks. One look before committing; with the air clock, every block is a
wager.

```
default_rule:  { resistance: 1, on_break: subdivide, drop: null }
overrides:
  "size:16":   { resistance: 2 }                 # the look before committing
  "size:2":    { on_break: mine, drop: null }    # the chunky payoff
```

Both are size rules, not a `""` path override, because a path override
applies to its node *and below* and would push resistance 2 onto every
level. Against a 1 HP pickaxe: strike 1 reveals, 2 breaks the root, 3 the
size-8, 4 the size-4, 5 mines the size-2 (its atoms are never instantiated).

A coal-bearing variant differs only in the terminal drop:
`"size:2": { on_break: mine, drop: {coal, size 1} }` yields four atoms of
coal per size-2. Drop size is authored, never assumed.

### 4.6 The reveal ladder


| Layer            | Trigger                                          | You learn                                                                                                                 |
| ---------------- | ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------- |
| **Colour class** | always visible (Phase 0); lamp radius (Phase 1+) | family only: brown is dirt *or* sand; grey is stone, hard stone *or* coal. Block borders visible, so size and rough cost. |
| **True nature**  | first strike                                     | material texture + fractures. Persisted.                                                                                  |
| **Hidden core**  | breaking the outer layers, sometimes never       | a terminal child that fractures cannot show (§4.6.3).                                                                     |


Colour class is deliberately lossy. Approaching a grey wall you do not know
whether it is three strikes or twenty; the first strike is the price of
information, and strikes cost air.

#### 4.6.1 Reveal is persisted state

`damage` and `revealed` are saved with the tree. Fractures never heal. The
player's fractures are a map of their own knowledge. (Later: area tools
that reveal without mining are survey instruments.)

#### 4.6.2 Fractures are derived from structure

Cracks are the override tree, rendered: drawn along the quad borders the
node *would* subdivide into, growing from the impact point. **Never add a**
`fracture_template` **field**; a second copy of the structure can disagree
with it, and then the picture lies. Distinct materials get distinct
silhouettes for free: hard stone one clean cross, a deep core dense in one
corner, sand fine lines everywhere.

Partial spread is intended: cracks stopping mid-block is its own tell.

#### 4.6.3 Opacity is structural

A fracture draws boundaries between children that exist. A terminal node
(`on_break: mine`) never has children, so nothing inside it can be shown.
**Never add a** `reveal_depth` **field.** The hidden core is automatic:

```
"Q1.Q2": { resistance: 40, on_break: mine, drop: {gem, size 4} }
```

reads as one solid size-4 region that refuses to crack. You learn what it
is only by breaking it.

#### 4.6.4 Reveal follows the damage

Striking reveals the node struck **and any sibling sharing its rule**. A
sibling with a different rule (a terminal core) stays unrevealed until
struck itself. Damage that passes down carries reveal with it, so
propagation is also a reveal mechanic: sand cannot keep a secret; hard
stone is close-lipped.

### 4.7 Templates

A **block template** is a recipe for one block's per-node rules. Two
independent authored facts about a material: at what node size it becomes
minable (`on_break: mine` at `size:N`), and at what size the units come out
(`drop.size`). Count is derived: `(node.size / drop.size)²`.

**Materials (5):** dirt, stone, hard stone, sand, coal.

#### 4.7.1 Templates are sparse override trees

Never a flat 256-cell array. A template is a `default_rule` plus overrides
under two kinds of key:


| Key      | Addresses     | Applies to                                              | Inherits downward? |
| -------- | ------------- | ------------------------------------------------------- | ------------------ |
| `Q1.Q2`  | position      | that node and below, until a deeper path says otherwise | yes                |
| `size:2` | physical size | any node of that edge length                            | no                 |


**Overrides are partial patches**: an absent field means inherit, never
reset. **Resolution, later wins, field by field:**

```
default_rule  →  size:N for this node's size  →  path overrides, shallowest to deepest
```

Paths resolve last, so **position beats size**.

**Inheritance describes what descendants would inherit;** `on_break` **decides
whether they exist.** `subdivide` creates children that inherit the rule.
`mine` is terminal: children are never instantiated and overrides beneath
that path are never read.

An unstruck block is **one node in memory**. Children are created on break,
reading their rule from the template, so the saved tree is only as deep as
the player has dug.

Quad-paths are root-relative, so `Q0.Q3` is a different physical size under
a size-32 root than a size-16 one. Express thresholds by size. A size key
above a block's root is inert, not an error: that is the granularity dial.
A path deeper than the atom is an error, caught when the template is bound
to a block size.

Rotating a template is a path digit remap; deliberate feature, not a
surprise (§7).

#### 4.7.2 Rules are template-authoritative

Children's rules are read from the template by path, never copied onto the
node. Retuning a material applies immediately to a saved world. Accepted
trade-off: editing a template changes saved behaviour. At ship, switching to
copy-on-create is an option.

### 4.8 Physics

None in Phase 0–2. Void is already the flow space it would need.

### 4.9 Fracture rendering

§4.6.2 fixes *where* a crack may be: along the borders of the children a
node would subdivide into, and nowhere else. This section fixes how much of
that line is drawn and how it is drawn — the only parts a material may
author.

The split is the whole discipline:


| Layer                                                          | Authored?                     | Why                                                                |
| -------------------------------------------------------------- | ----------------------------- | ------------------------------------------------------------------ |
| **Structure** — which lines can exist                          | never                         | derived from the tree; a second copy can disagree with it (§4.6.2) |
| **Extent** — how far along each line the crack has spread      | never; a function of `damage` | damage is already persisted node state (§4.6.1)                    |
| **Style** — weight, jitter, colour, growth rate, talkativeness | per material                  | distinct silhouettes are the art risk §6 exists to catch           |




#### 4.9.1 A cross has four states


| State           | Condition                                    | Drawn                                                      |
| --------------- | -------------------------------------------- | ---------------------------------------------------------- |
| **Nothing yet** | unrevealed leaf                              | colour class only                                          |
| **Never**       | terminal node (`on_break: mine`), or an atom | no cross at any damage — opacity is structural (§4.6.3)    |
| **Promise**     | revealed leaf that would subdivide           | the cross at `extent` (§4.9.2)                             |
| **Fact**        | node has subdivided                          | the full cross, permanently (fractures never heal, §4.6.1) |


Only the **promise** state is new. It is the state the whole reveal ladder
turns on: it says *this will open*, without saying into what.

#### 4.9.2 Extent is damage, drawn

```
extent = tell × (damage / resistance)        clamped 0..1
```

`extent` is the fraction of each arm, from its origin, that is inked. At 0
the node looks untouched; at 1 the cross is complete and the node is about
to break. Nothing is stored: `damage` is persisted (§4.6.1) and
`resistance` is looked up from the template (§4.7.2), so a reloaded world
shows the same half-grown cracks it showed at quit.

`tell` (§4.9.5) is the material's talkativeness and is a **design lever, not
a graphics setting**:


| Template      | `tell` | Reads as                                                         |
| ------------- | ------ | ---------------------------------------------------------------- |
| `hard_stone`  | 0      | twenty strikes with nothing happening, then one clean cross (§6) |
| `honest_dirt` | ~0.6   | you can see it giving                                            |
| `sand`        | 1      | it is failing before you finish the swing                        |


**This replaces the damage tint.** A brightness overlay scaled by damage is
a fourth visual channel competing with colour class, block border and
fracture (§4.1.2), and it costs `hard_stone` its entire design: "nothing
happening" is a lie if every strike lights the block up. Damage shows as
crack, or it does not show.

Extent cannot leak ahead of the reveal ladder: any damage reveals the node
struck (§4.6.4), so `damage > 0` implies `revealed`.

#### 4.9.3 Partial spread is mostly one level down

"Cracks stopping mid-block is its own tell" (§4.6.2) is only partly the
half-drawn cross of §4.9.2. The larger effect is the *children's* crosses
being absent: a subdivided node draws its own cross as fact, but each child
draws a promise only once revealed, and a terminal child never draws one at
all (§4.6.3). Striking one quadrant of `gift_stone` therefore gives a
dense cross at the top, promises in the quadrants that share the struck
rule, and one quadrant that stays blank and solid — the core, refusing to
crack.

Extent and reveal are independent modulations of the same picture, and both
have to survive whatever the renderer does. A design that makes a
half-extent promise indistinguishable from an unrevealed sibling has thrown
away a layer of the ladder.

#### 4.9.4 Growth is interpolation — geometry open

Because extent is derived from persisted damage, animation adds no state:
the renderer tweens between the extent it drew last frame and the extent
the tree implies now, over `growth` seconds. A cascade (§4.4.1) arrives as
`Strike.Result.broke` in order, so the levels can be staggered rather than
snapping together.

What is **not** settled is where an arm grows *from*:


| Origin               | Reads as                                 | Cost                                          |
| -------------------- | ---------------------------------------- | --------------------------------------------- |
| centre → outward     | the node splitting itself                | none; symmetric, fully derived                |
| struck edge → inward | the blow entering the block              | none; the facing axis is known at strike time |
| impact quad → across | the blow travelling through the material | a 2-bit last-impact hint per node             |


Only the third wants anything new, and it may be a **transient** hint —
session-only, so cracks re-grow symmetrically after a load — rather than a
persisted field. Kept transient it is a cache, not a schema change, and
nothing in §4.6.2 is touched: that invariant forbids a second copy of the
*structure*, and says nothing about where a derived line starts.

Do not settle this on paper. Build the symmetric version first, because it
is free, and only add the hint if the block visibly fails to read as
*struck from a direction*.

#### 4.9.5 The style block

A style is a property of the **material**, so "sand cracks like sand" holds
across every template made of sand and §4.6.2's free distinct silhouettes
stay free. A template may name a different one; it does not spell one out
inline.

```
FractureStyle
  tell          0..1   how far a crack spreads before the break (§4.9.2)
  growth        s      tween time for a change in extent
  jitter        atoms  lateral wander around the true border
  jitter_seed   int    per-node seed, so a line is stable across frames and saves
  weight        px     framebuffer pixels; 1 px reads at every size (§4.1.2)
  colour
```

Jitter **roughens the line, never moves it** (§4.6.2): it displaces the ink
around a border whose position stays derived, and a node's seed is a hash
of its path so the same crack is the same crack after a reload.

---



## 5. Data model

Persisted form ≠ runtime form. All sizes in atoms; quad indices 0-based
row-major; +Y down.

### 5.1 Persisted schema

`Node.size` is not stored; it is `BlockInstance.size >> depth`.

```
World
  blocks: SpatialIndex<BlockInstance>   # non-overlapping; nothing for void

BlockInstance
  origin: Vector2i                      # atoms
  size: int                             # edge length; same meaning as Node.size
  template_id
  root: Node

Node
  damage: float                         # HP
  revealed: bool                        # only ever set
  children: [Node | null x4] | none     # null slot = mined quadrant;
                                        # none = never subdivided

BlockTemplate
  material_id
  display_skin
  colour_class                          # lossy family; defaults to the material's
  default_rule: Rule
  overrides: map<key, RulePatch>        # "Q0.Q3" | "size:4"; partial patches
  fracture_style                        # optional; defaults to the material's (§4.9.5)

Rule
  resistance: float
  on_break: subdivide | mine
  drop: null | {material, size}         # 1 <= drop.size <= node.size, power of two
  pass_down: bool
  pass_down_falloff: float              # 0..1
  pass_through: none|inline|lateral|radial|downward
  pass_through_falloff: float           # 0..1

FractureStyle                           # presentation only, never structure (§4.9)
  tell: float                           # 0..1; crack spread before the break (§4.9.2)
  growth: float                         # seconds to tween a change in extent
  jitter: float                         # atoms of lateral wander; never moves the border
  jitter_seed: int                      # hashed from the node path; stable across saves
  weight: float                         # line width, framebuffer px
  colour

Ladder                                  # Phase-0 entity, not a block
  origin: Vector2i                      # 8x8, atom grid

Player
  origin: Vector2i                      # box top-left, atoms
  air: float
  coal: int
  ladders: int
```

Save = world blocks (an untouched node is `{}`) + ladders + player.

### 5.2 Runtime cache

`Node.size` is written in exactly two places: load
(`BlockInstance.size >> depth`) and subdivide (`parent.size >> 1`). Assert
power of two ≥ 1.

### 5.3 Typing

Enum for names (`on_break`, `pass_through`, materials); integer for
quantities (`size`, in atoms).

---



## 6. Build plan



### Phase 0 — vertical slice: does it feel good to dig?

Built so far:

- Quadtree node engine with sparse override templates, size-in-atoms vocabulary, 0-based row-major quads, +Y down.
- Damage, pass down, reveal-with-siblings, drops with derived counts. Pass through parsed, not routed.
- Five materials over void; six authored templates (below); the 1024 × 1024 dev map as a character grid.
- Damage and reveal persisted; save/load round-trips.
- Legibility test (§4.1.2 finding). Throwaway map viewer for borders and colour class.

Remaining:

- **Renderer:** colour class, block borders, fractures derived from the tree growing from the impact point, revealed material texture.
- **Character** (§3.1): atom-stepped 8 × 8 box, gravity, walk, strike-when-blocked, the scan, ladders, place_ladder.
- **Air** (§3.1.2): drain, surface refill, death and reset.
- **Coal counter** (§3.1.3).
- **HUD:** air, coal, ladders, depth.
- **Save** on quit and on surface; **load** on start.



#### The authored templates

The same input must produce different experiences:

1. **honest_dirt** — the prototype (§4.5). The baseline.
2. **liar_dirt** — identical when untouched; `Q2` resists 8 all the way down. Strike each quadrant once: three crumble, one does not. The player's "huh?" is the game.
3. **gift_stone** — stone with a coal core at `Q1.Q2` that changes only the drop, so fracturing shows the coal before it can be reached.
4. **sand** — the trap. `pass_down: true`, resistance 0.25: one strike bores a shaft through the whole block and you fall. Consequence, not punishment.
5. **hard_stone** — the boulder. Twenty strikes with nothing happening, then one clean cross, then terminal at size 8.
6. **stone** — grey fill, dearer than dirt. Painted at size 4 it is the rubble the boulder hides in: same colour class, so only the border says the wall is expensive (§4.1.2).



#### The risk this phase exists to catch

**The quadtree might be invisible.** If the player only sees "block breaks
into smaller blocks", this is an elaborate machine producing an ordinary
mining game. Fractures must be readable at a glance: a 4-way distinguishable
from a 16-way in one frame. That is an art problem. Watch for it.

### Phase 1 — authoring and economy

Sell coal, buy ladders and upgrades. Template editor, terrain painter.
Darkness and lamp radius; player-radius map reveal. Multiple tools with
different HP, strike rates and scan patterns. Tune the 90/10 ratio.

#### The template editor

A template is a tree of rules addressed by quad-path and size (§4.7.1). The
one diagram isomorphic to that address space is a nested square
subdivision — which the terrain renderer already draws, and which a click
already resolves to a path. **The editor is the game's own renderer with an
inspector attached**, in the same spirit as the map painter: one live
block, edited in place.

```
┌─ SIZE LADDER ────────┬─ CANVAS  root: [4][8]•16•[32] ──┬─ INSPECTOR ─────────┐
│ default              │  ┌──────────┬──────────┐        │ node Q2.Q0  size 4  │
│   res 1  subdiv  —   │  │          │    ╬     │        │                     │
│ ─────────────────    │  │    ╬     ├────┬─────┤        │ resistance   8      │
│ size:16  res 2       │  │          │    │ ▓▓  │        │        ← from Q2    │
│ size:8   ·           │  ├──────────┼────┴─────┤        │ on_break  subdivide │
│ size:4   ·           │  │▒▒▒▒▒▒▒▒▒▒│          │        │        ← default    │
│ size:2   mine  —     │  │▒▒ Q2 ▒▒▒▒│    ╬     │        │ drop      null      │
│ size:1   ·           │  │▒▒▒▒▒▒▒▒▒▒│          │        │        ← default    │
│                      │  └──────────┴──────────┘        │ pass_down false     │
│ PATHS                │                                  │        ← default    │
│ ▒ Q2   res 8         │  [author] [strike]  reset        │                     │
└──────────────────────┴──────────────────────────────────┴─────────────────────┘
```

Four requirements, in order of how much of the value they carry:

1. **The size ladder is the primary surface, not the canvas.** Six of the
  eight authored templates (§6) have no path overrides at all: a material
   is normally a resistance per level plus the size at which it goes
   terminal. That is a five-row table. The canvas exists for the two
   templates with a secret.
2. **Every field names the key that won it.** `default → size:N → paths
  shallowest to deepest`(§4.7.1) is the one thing invisible in the JSON,  and it is where authoring mistakes live. Each inspector field carries  its provenance and jumps to that key when clicked; the canvas tints each  subtree by its governing override, so`liar_dirt` *looks* like one
   quadrant painted differently.
3. **The canvas is playable.** A mode toggle strikes real HP at the clicked
  atom through the live damage path, with a tool HP dial and a reset.
   There is no preview mode, because the preview is the game — and "how
   does this material feel" is not answerable from a rule table.
4. **Signature strips.** The deterministic clear-the-whole-block trace,
  rendered as thumbnails at strikes 1, 2, 3, 5, 8, shown for root sizes 4,
   8 and 16 at once. This is how one template is compared to another, and
   it is the only place §4.1.2's claim that block size is an authoring dial
   becomes visible rather than asserted.



##### Composition is a gesture, not a field

"Make Q1 hard stone" is the common authoring wish and the wrong data model.
A template reference at a path collides with size keys — whose ladder
applies? — and with `material` and `colour_class` being per-template. So
the editor **stamps** instead: drop a template onto a quad and it flattens
that template's rules into path overrides under the quad. The JSON stays
flat, `TemplateLoader` learns nothing new, and §7's "build an editing
gesture, not a `layout_template` field" holds.

Stamping must ask one question, because both answers are useful:


|              | Means                                       | Good for                              |
| ------------ | ------------------------------------------- | ------------------------------------- |
| **absolute** | size keys keep their atom sizes             | a seam of real hard stone inside dirt |
| **rescaled** | the source's root maps onto the target node | the same shape of material, smaller   |


Stamping `hard_stone` (terminal at size 8) absolutely into a size-8 quad
makes that quad terminal on arrival — occasionally the point, usually not.
Offer both and show the signature strip for each.

The cost is the one §4.7.2 already accepts, pointing the other way: a
stamped copy does not track later edits to its source. If that becomes
painful, a real template reference is the answer, and it is a Phase-2
design, not a patch on this one.

##### The editor writes only what the game reads

Parse → edit → serialize must round-trip losslessly, `_` notes included,
and must never emit a key the loader ignores — a template that means
something only to the editor is a fracture template by another route.
Validation runs against each offered root size and appears as a standing
problem list, not a modal.

### Phase 2 — depth and tension

Depth-scaled air curve, shoring, pass-through patterns, area tools (TNT,
seismic charges as survey instruments), the Jewel of Heaven and the win
state.

### Phase 3 — physics and life

Mined units as entities that fall and scatter; void as flow space;
recombination; extra lives; heat.

---



## 7. Ideas for later

- Physical drops: pickups, particles, `MinedUnit` entities. Larger `drop.size` as an entity-count lever. Never let `drop.size` yield more mass than the node held.
- Layout patterns (geodes, rings, hollow cores) are already expressible as overrides (`resistance: 0, on_break: mine, drop: null` is a hole). Build an editing gesture, not a `layout_template` field.
- Ladder recovery, at a cost.
- Waste-on-overmine. Extra lives. Heat. Air pockets tied to shoring.
- Chunking past a few thousand blocks. Inventory stacking. Boulders (size-32 roots). Template rotation. Morton-packed paths. Freeze-at-ship rules.
- Cross-block pass-through, needed for area tools.
- Steering bias on the scan.
- Template references at a path, if stamped copies (§6) become painful to retune. A real composition feature, not a patch on stamping.



## 8. Open

Every value in §3.1.4, the scan order, the air curve, the template
resistances, and the 90/10 ratio. None block Phase 0.

Added by §4.9 and the editor spec, none blocking Phase 0:

- `tell` per material, and whether extent grows linearly with damage or late
and suddenly (a curve on §4.9.2).
- Where a crack arm grows from (§4.9.4), and whether the impact hint that
the third option needs is transient or persisted.
- Whether fracture style is keyed by material with a template override, or
by template outright (§4.9.5).
- Whether a stamp defaults to absolute or rescaled sizes (§6).

