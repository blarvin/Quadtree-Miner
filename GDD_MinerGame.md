# Game Design Document — (working title) *Quadtree Miner*

> A 2D side-scrolling mining & exploration game about descending a finite,
> hand-authored world, managing air instead of health, and shoring up your
> path as you chase a single prize: the Jewel of Heaven.
>
> The distinctive technology is a **per-block quadtree terrain system** that
> makes digging tactile, readable, and authorable. This document specifies
> the full vision *and* a staged build plan so there is something playable
> long before the full system exists.

---

## 1. Pillars

1. **Exploration is the spine.** Everything — terrain, economy, air — exists to make descending a finite world tense and rewarding. Progression is spatial, not numeric.
2. **The terrain is the toy.** Digging must feel physical and legible. The quadtree reveal system is the core innovation; blocks *are* their mining behaviour.
3. **Commitment and consequence.** Air is a chasing clock. Ladders and shoring cost real resources and inventory. Every descent is a bet on getting back up.

## 2. Core loop

Dig → gather → return to surface → sell → upgrade → descend deeper. One persistent world, one shop, one buyer, one surface rest point. The loop tightens as air pressure grows with depth and the return trip lengthens.

**Phase 0 tests only the inner loop** — dig, air, return, die. Selling and upgrading are deliberately excluded (§6); the slice must prove the terrain is fun with a single pickaxe and nothing to spend on.

## 3. Player-facing design

| Element | Definition |
|---|---|
| **World** | One persistent, finite, hand-authored world. Saved across sessions. POC dev map **1024 × 1024 atoms** (§4.1.0). |
| **Character** | 8 atoms tall (½ a standard block). Walks, climbs ladders, mines in a target direction. |
| **Chase factor** | **Air**: continuous drain, faster with depth, refilled only at the surface. (Heat: *Ideas for Later*.) |
| **Failure** | Run out of air = death. Death = full world reset (perma-death). Earnable extra lives → *Ideas for Later*. |
| **Win** | Find and retrieve the **Jewel of Heaven**. That is the entire victory condition. |
| **Economy** | Mine resource units → carry in inventory → sell at surface → buy upgrades, ladders, shoring. **Phase 1+** — excluded from the slice (§6). |
| **Inventory** | **Slot-based.** Phase 0/1: every item fills exactly one slot. Capacity becomes an upgrade axis once the economy exists. |
| **Traversal items** | Ladders and shoring: consumable placed items, cost resources, occupy inventory. They gate vertical progress. **Phase 0: ladders only, granted as fixed stock** (traversal, not economy). |
| **Map reveal** | Player-radius reveal, persistent once seen. |

### 3.1 Movement, mining, and traversal

**Design target: casual feel, mobile potential.** The control scheme must survive a thumb on glass. This works against fine-grained terrain — and the terrain is the point — so the resolution of that tension is that **movement *is* mining**.

#### The core rule

**If the way is clear, move. If something blocks you, hit it.**

- Applies in **all four directions** — up, down, left, right.
- **Hit whatever blocks you; move only when fully clear.** Partial obstruction (a block occupying 3 of the 8 atoms in your path) is the common case, and it counts as blocked. A tunnel must actually be cleared to be walked.
- **Sustained pressure mines continuously.** Holding a direction against an obstruction produces **repeated strikes** at the tool's strike rate, then walks you into the space you made. A brief press-and-release produces a **single strike**. No separate mine button, no auto-repeat to configure — pressure *is* the input.

There is **no separate attack input, no aim, no tool-placement UI.** Direction is the whole vocabulary.

#### Traversal rules (Phase 0/1)

| | |
|---|---|
| **Character** | 8 atoms tall. Walks left/right. |
| **No jump** | Deliberate. Vertical movement is earned, not free. |
| **Up** | **Ladders only** — placed, consumable, cost resources, occupy inventory (§3). Ladders are the *only* way up. |
| **Down** | **Dig or fall.** Descent is cheap; ascent is the expensive, planned half of every trip. |
| **Falling** | Free and instant. Combined with air (§3), this is the core tension: down is a one-way door until you spend on ladders. |
| **All digging** | Impact-point scan (§4.3.2) spans the character's cross-section perpendicular to the dig axis — height when digging sideways, width when digging up or down. Tunnels are always walkable; shafts are always enterable. |

**Why no jump:** the air clock (§3) only bites if the return trip is a real cost. A jump would make shallow ascents free and collapse the risk of descending "just a bit further." Ladders-only makes every metre of depth a resource decision.

---

## 4. THE TERRAIN SYSTEM (core spec)

### 4.0 Vocabulary — NAME THINGS AFTER INVARIANTS

**The atom is real. The root is arbitrary.** The engine's naming must reflect that.

- The **atom** is the fixed, physical, engine-wide bottom: the **grid resolution** and the **collision unit**. It never changes. It is also the **floor** on drop size — but not the drop size itself, which is a template property (§4.7, §5.1).
- A block's **root size** is a per-block convenience that varies. Nothing is special about any particular root.

Therefore **nodes are named by physical size in atoms** — never by depth-from-root:

| Name | Meaning |
|---|---|
| **atom** (`size 1`) | 1×1 — fixed, real, the bottom. Cannot subdivide. |
| `size 2` | 2×2 atoms |
| `size 4` | 4×4 atoms |
| `size 8` | 8×8 atoms |
| `size 16` | 16×16 atoms — the **standard block** footprint |
| `size 32` | boulder root — costs nothing to add |

**"Coal drops at size 4" is a fact about coal, true in every block regardless of root.** A boulder is just a tree whose root is size 32 — no renumbering, no template invalidation.

- **Tree depth is derived** (`log2(block.size)`), not an identity.
- **The atom is the natural terminator**: `size == 1` cannot subdivide. Arithmetic, not a special case.

> **Do not reintroduce depth-numbering** (`B1…B5`, `L0…L4`). Any name counted from the root or the bottom is relative to a movable end, so the same name means different physical sizes in different blocks, and every authored rule silently changes meaning when a new root size appears.

*Informal usage:* "standard block" is fine conversationally for a size-16 footprint — never as a level name in code or templates.

#### 4.0.1 Axis convention — +Y IS DOWN

**+Y is down. Depth increases with Y.** Godot's 2D convention. The quad order in §4.0.2 follows from this and breaks if it is violated.

#### 4.0.2 Quad-path convention — 0-BASED, ROW-MAJOR (Z-ORDER)

Children are indexed **Q0–Q3**, in **row-major (reading) order**:

```
        +X →
  +Y   Q0 = TL    Q1 = TR
   ↓   Q2 = BL    Q3 = BR
```

Indices are **computed, not typed**:

```
child_index = (x >= mid_x) | ((y >= mid_y) << 1)
```

**Bit 0 = "am I right?" Bit 1 = "am I bottom?"** This is what the convention buys:

- A packed quad-path is the interleaved binary coordinates of the node — a **Z-order curve (Morton code)** — so paths are cheap to compute, compare, and pack.
- **Sibling patterns are bit ops**: `pass_through: lateral` = flip bit 0; `downward` = set bit 1 (§4.4.2).
- **Rotation is a fixed digit remap** (§4.7.1), checkable against standard references.

> **Do not "fix" this to 1-based or to winding order** (TL,TR,BR,BL). Winding is the convention for *polygon vertices*, not quadtrees; it destroys the bit decomposition and forces lookup tables. 1-based forces a ±1 correction at every lookup and blocks path packing.

**UI may display any labelling it likes (Q1–Q4, NW/NE/SW/SE). Storage and code are 0-based row-major.**

### 4.1 World structure

- The world is a **flat spatial index of non-overlapping blocks**. Blocks tile cleanly; two blocks never overlap.
- **Blocks are always square.** A block's `size` (edge length in atoms) is its entire extent — there is no separate footprint. Non-square regions are a *painter* concern: a brush places several square blocks, and the runtime never knows they were one gesture.
- The world grid resolution is **one atom**. Blocks of any size snap to this grid.
- Placement may leave **gaps of any number of atoms.** Blocks need not be contiguous.
- There is **no global quadtree.** Each block owns its own subdivision tree internally. The "grid" is only a placement/snapping resolution.

#### 4.1.0 World dimensions

**Phase-0 dev map: 1024 × 1024 atoms.**

| | |
|---|---|
| **Extent** | 1024 × 1024 atoms |
| **In standard blocks** | 64 × 64 = 4,096 |
| **Atom cells** | 1,048,576 |
| **Depth in character-heights** | 128 |

A shallow dig — fine for development. Ship scale is a content question, deferred until the loop is proven.

**Sparseness applies to nodes, not blocks.** An untouched block is one node (§4.7.1), so live node count scales with how much has actually been dug — not with the million atom cells, most of which are void (§4.1.1) or unstruck. But `BlockInstance` records exist whether touched or not, so **the block count is the number that scales**. At 4,096 the world is a flat array: no chunking, no streaming.

#### 4.1.1 Void semantics (air is not a block)

Empty space is the **absence of a block**, not an air-material block. There is no void object to author, store, or carve.

- "Is this cell empty?" = "does any block cover it?" → for a gap, no. This is the *same* spatial-index query collision and neighbour-reveal already need, so void costs nothing extra.
- Mining an atom **removes** the unit; the cell simply reverts to void. No air block is spawned.
- **Air-the-resource** (what the player breathes) is a purely numeric drain on the player and has **no** relationship to void space. The player never interacts with void as an object.
- Deferred: if blocks later *flow into* or are displaced through void (Phase-3 physics), void cells act as flow space — still with no hand-authored air blocks.

This removes air from the material list: **5 starting materials** (dirt, stone, hard stone, sand, coal).

#### 4.1.2 Mixed-size packing — a terrain axis independent of material

**Block size is an authoring dial that costs no new templates.** The same template painted at size 16 and at size 4 gives different *play*, not different content: a size-4 dirt block is one strike from dust; a size-16 dirt block is five. Same rules, same material, same fracture logic — pebble versus boulder. The player's theory transfers ("I know what dirt does"); the encounter does not ("...but not at this size").

So 20 good templates × 5 sizes is not 100 templates. It is **20 templates and a granularity dial** — which is better, because it multiplies encounters without multiplying things to learn.

**Packing patterns are the level-design vocabulary:**

| Pattern | Play |
|---|---|
| A size-16 hard block **embedded in size-4 rubble** | The wall reads cheap from outside; three metres in, a boulder you cannot afford blocks the tunnel. Air spent, tunnel behind you. **The rubble hid the boulder.** |
| **Alternating size-8s** of two materials | A checkerboard that punishes straight-line digging. |
| A **seam of size-2 blocks** through size-16 stone | A *fault line*: cheap to follow, expensive to cross. **A corridor authored as terrain, discoverable only by a player who reads size as cost.** |

That last is how this game authors **routes without walls** — progression is spatial (§1), and mixed-size packing shapes where players go without ever forbidding a direction. It is navigation-as-skill (§4.5), authored in terrain rather than in mechanics.

**Prerequisite: block borders must be legible on untouched terrain.** Size must be readable *before* the first strike, or the boulder-in-rubble is not a decision but a gotcha. This is a **third visual channel**, distinct from the other two:

| Channel | Tells you |
|---|---|
| Generic skin / colour class (§4.6) | material *family* |
| **Block border** | **size — and therefore rough cost** |
| Fracture (§4.6.2) | internal structure |

These three must not fight each other visually.

### 4.2 The block quadtree

- A **standard block** has a size-16 root and subdivides: 16 → 8 → 4 → 2 → **atom**.
- **The atom is the atomic addressable unit** for damage and collision, and the **floor** on drop size. Anything finer than an atom (sub-pixel cracks) is **purely visual**.
- **Boulders (size-32 roots) are free** — the tree simply starts higher. No renaming, no new rules. Not in scope now, but the model already permits it.

### 4.3 The node model (the heart of it)

Damage is **spatial, per-node**, not per-block. Every hit targets whichever **leaf node** currently sits under the impact point.

A node **stores** only what is true of *this instance*:

| Field | Meaning |
|---|---|
| `damage` | **HP** accumulated on *this* node (§4.3.1) |
| `revealed` | whether this node's material/fractures have been shown (§4.6.1) |
| `children` | four child nodes, or `null` for a leaf — **`null` is the common case** (§4.7.1) |
| `size` | edge length **in atoms** — derived cache, not persisted (§5.2) |

Its **`rule`** is *not stored* — it is **looked up** from the block's template by quad-path (§4.7.1, §4.7.2). The rule carries what is true of the *material*: `resistance` (the HP threshold to break), `on_break`, and `drop`.

**The split:** does a value differ between two instances of the same material? `damage` does — it goes on the node. `resistance` does not — it lives on the template, in one copy.

When a leaf's `damage` reaches its rule's `resistance`, it **breaks** — one of two outcomes:

- **`subdivide`** → replaced by four children of `size/2`.
- **`mine`** → **the node is destroyed.** Whether anything comes out is a *separate* question, answered by `rule.drop` (§5.1): `drop: none` means it simply vanishes; otherwise it yields units at the drop's own authored size.

**`mine` means destroyed; `drop` means what — if anything — comes out.** Vanishing is not a different kind of break; it is a break that yields nothing.

Unstruck siblings keep their own damage pools at **zero** — so digging is a **wandering front**: you carve one quadrant-path and the siblings stay intact until separately hit. (This is the Gem-Miner feel and is deliberate.)

### 4.3.1 Damage is HP

**A tool delivers HP. The block takes that HP and does what its template says to do with it.**

This is the model's core separation of concerns:

- The **tool** knows nothing about terrain — it has an HP value, a **strike rate**, and an impact-point scan (§4.3.2).
- The **template** knows nothing about tools — it has HP thresholds and break behaviour.
- All intelligence lives in the **rule**. **Adding a new tool later is data, not code.**

`resistance` is therefore an **HP threshold on each node**, not a hit count. Discrete-hit tools are just tools with HP=1. Propagation falloff (§4.4) is plain arithmetic on surplus HP, which is only coherent because HP is continuous.

#### Tool power and pass_down interact — tune them together

`pass_down` **only expresses itself when a tool overdelivers.** A 1 HP pickaxe into a resistance-1 node breaks it with **0 surplus** — so there is nothing to pass down, and the block grinds level by level *regardless of the flag*.

This is why the prototype block (§4.5) feels progressive: not because `pass_down = false`, but because **there is no surplus**. Give the same block resistance-1 nodes and a 4 HP tool, and it cascades — **if** `pass_down = true`.

**Consequence:** resistance values must be tuned **against the tool ladder**, never in isolation. This is a desirable property — **upgrades change how terrain *behaves*, not merely how fast it dies** — but it means the 90/10 propagation ratio (§4.4.3) is a statement about *tool-relative* resistance, not absolute numbers.

### 4.3.2 Impact-point scan — DISTRIBUTE OVER TIME, NOT SPACE

**One strike = one HP at one atom. Always.** A tool never hits multiple nodes in a single strike.

A **strike** is the atomic mining event — it is not an input. Sustained pressure against an obstruction produces repeated strikes at the tool's **strike rate**; a brief press produces one (§3.1). The invariant holds either way: the input decides *how many* strikes, never *how much* a strike does.

The problem this solves: a strike lands at one point, but the character must fit through the hole. Without a scan you cut a 1-atom slot and cannot follow it. **Position cannot solve this**, because whichever axis you are digging along, the perpendicular one is pinned:

- Digging **horizontally**, Y is **floor-locked** — you stand on what you stand on.
- Digging **vertically**, X is **shaft-locked** — once the shaft is your own width, there is no room to shuffle. (Free aim is available only *before* the first strike; digging its own hole is what traps you in it.)

The fix is **temporal, not spatial**. Consecutive strikes advance the impact point through a **deterministic cycle** spanning the obstructing atoms:

- **The scan spans the character's cross-section perpendicular to the facing axis.** Facing left/right → scan the 8 atoms of **height**. Facing up/down → scan the 8 atoms of **width**. One rule, four directions, no special cases.
- **It spans exactly the atoms that obstruct** — not a fixed 8. In a 4-atom-wide space, the scan covers 4. The tool always carves precisely the hole needed to pass, and never more.
- **Deterministic order.** POC: **top to bottom** (horizontal digging) / **near side to far side** (vertical digging), one atom per strike, repeating. Not random.
- **Nearest obstruction first.** The scan targets the closest blocking node along the facing axis — you cannot hit through an intact block into one behind it.
- The player expresses **intent** ("through here"); the tool handles **mechanism**.

**Why temporal and not spatial:** a tool whose hit *region* covers 8 atoms delivers 8 hits per strike — a strike is no longer a strike, and a block is no longer a block. A tool that distributes the *same single hit* across successive strikes keeps the model intact. It also keeps damage-spreading authority in the template (§4.4) where it belongs, rather than splitting it between tool and terrain.

**Scan pattern and strike rate are tool properties.** The POC pickaxe scans the character's 8-atom cross-section. Later tools differ: a tighter cycle concentrates (precision digging); a wider one carves roomier tunnels and shafts; a faster strike rate mines quicker without ever making one strike stronger. These are upgrade axes more interesting than a bigger number.

*Deferred to Phase 1 — **optional steering bias**: holding a direction (e.g. forward + up on an 8-way pad) biases the cycle toward that half of the span. Not aiming — emphasis. Invisible unless wanted; casual players ignore it and the scan handles everything.*

### 4.4 Damage propagation: PASS DOWN and PASS THROUGH

Two distinct mechanisms, same anti-grind purpose:

- **PASS DOWN** = leftover damage flows to **child** nodes (down the tree).
- **PASS THROUGH** = damage flows to **sibling** nodes (across the tree).

Neither is required for POC. Both are designed for now.

#### 4.4.1 Pass down

A per-template **`pass_down` flag** (+ falloff) unifies two very different feels from one machine:

- **`pass_down = false`** (progressive/tough block): when a node breaks, leftover damage is discarded. Each level is a fresh wall. This is the **prototype block**.
- **`pass_down = true`** (crumbly block, e.g. sand): leftover damage flows into the newly-exposed child **under the impact point**, cascading potentially size-16 → atom in a single blow.

Pass down has an unambiguous target — the child under the blow — so it needs only a flag and a falloff.

#### 4.4.2 Pass through (where material character lives)

Pass through must **choose** siblings, and that choice *is* the material's character. So it is a **named pattern**, not a flag:

| Pattern | Reads as | Sibling selection (§4.0.2) |
|---|---|---|
| `none` | isolated / brittle-in-place | — |
| `inline` | grain, bedding planes — passes along the axis of the blow | flip the bit for the blow's axis |
| `lateral` | shattering — passes to side siblings | flip bit 0 |
| `radial` | crumbling outward from impact | all 3 siblings, falloff by distance |
| `downward` | collapsing under its own weight | set bit 1 |

Each pattern takes a **falloff** (how much damage survives the hop). Expect to add patterns as materials demand them.

*These bit ops are only this clean because of 0-based row-major indexing (§4.0.2) — sibling selection is arithmetic on the quad index, not a lookup table.*

#### 4.4.3 Design principle — the propagation ratio is the game's feel

Propagation is a spectrum in practice, not a binary:

- **pass down = true + low resistance** = **bread-and-butter fill** a decent tool knifes through. Most of the world should be this.
- **pass down = false** = a **deliberate grind**, reserved for walls that must *feel* like walls: hard-stone gates on shortcuts, the shell around the Jewel of Heaven, the boundary of a resource pocket.

The character of the whole game lives in the ratio of pass-true fill to pass-false gates — target roughly **90/10**. A world of pass-false blocks is a grind; a world of pass-true blocks has no tension. Authoring good blocks for each purpose is expected to take experimentation — **that experimentation *is* the level design.**

### 4.5 The prototype block (Phase-0 canonical template)

#### Fracture before commit

**The first strike reveals without subdividing.** `resistance: 2` on the root, not 1: strike one exposes the fracture pattern and the material; strike two breaks it.

This is one number, and it is the difference between an action and a **decision**. The player gets **one look before committing** — see a tight clean cross (hard, slow) versus a spidery mess (about to crumble) and *walk away*. Combined with the air clock (§3), every block becomes a wager: not *"should I dig"* but *"should I dig **this one**"*. The terrain is a slot machine whose reels are partly visible.

It also makes the 90/10 ratio (§4.4.3) **legible rather than merely tuned** — if gates announce themselves after one strike, the player routes *around* obstacles instead of through them, and **navigation becomes the skill**. That is what makes this exploration rather than excavation.

#### The rest of the block

Homogeneous, progressive, `pass_down = false`, `pass_through = none`. **Root `resistance: 2`** (fracture before commit, above); 1 HP at every level below. A `default_rule` plus one root override (§4.7.1). A size-16 root against the starting pickaxe (1 HP/strike):

1. **Strike 1** → size-16 node takes 1 of 2 HP. **Reveals** fracture pattern + material (persisted, §4.6.1). **Does not subdivide.** ← *the look before committing*
2. **Strike 2** → size-16 breaks, `subdivide` into 4 size-8 children.
3. **Strike 3** → the *struck* size-8 breaks, `subdivide` to 4 size-4 children.
4. **Strike 4** → the *struck* size-4 breaks, `subdivide` to 4 size-2 children.
5. **Strike 5** → the *struck* size-2 breaks with **`on_break: mine`**, `drop: {coal, size 1}` — the node is destroyed, its four atoms **never instantiated as nodes**, yielding **4 atom drop units at once**.

**Drop size is authored, not assumed.** The prototype declares `size 1` on its size-2 nodes because that is the character wanted — a fine spray of coal. A material yielding one chunky 2×2 lump instead declares `drop: {coal, size 2}`. Nothing in the engine hardcodes `size/2`.

**The drop unit is a payoff, not a chore.** The parent's break destroys its children and yields them at once. The final blow is chunky rather than a fifth identical strike.

Surgical single-atom mining (picking around a gem) is available where wanted as a per-block `on_break: subdivide` override.

**POC drop handling:** coal yields and is **auto-collected**. Dirt and stone declare `drop: none` — they **vanish** (§4.3). Contact-based collection, particle spawning, etc. come later (§7).

Coherent and fully general: heterogeneity later is just *overrides on the default* (Q0 breaks straight to atoms while Q1 stops at size 4), and crumbly blocks are just `pass_down = true`.

### 4.6 The reveal ladder

Knowledge of the terrain arrives in **four layers**. Each costs more than the last, and the last two cost air.

| Layer | Trigger | What you learn |
|---|---|---|
| **1. Darkness** | — | Nothing. |
| **2. Colour class** | within lamp radius | **Family only.** Brown = dirt *or* mud *or* hard dirt *or* clay. Grey, yellow, blue, red likewise. Block **borders are visible** — so size, and therefore rough cost, is readable (§4.1.2). |
| **3. True nature** | first strike, or TNT / seismic charge | **Material texture + fractures.** Now you know it is clay, not dirt. Written permanently to the map (§4.6.1). |
| **4. Hidden core** | breaking the outer layers — and sometimes not even then | Some templates hide a child that outer-layer removal does not expose. See §4.6.3. |

**Colour class is deliberately lossy.** Four materials sharing a colour may differ wildly in `resistance` and `pass_down`. Approaching a brown wall you do **not** know whether it is five strikes or fifty — you buy that knowledge one strike at a time, and strikes cost air. This is what gives fracture-before-commit (§4.5) its teeth: **the first strike is the price of information.**

It also makes area tools precise in value (§4.6.1): TNT and seismic charges do not "reveal the map" — they **collapse the colour class into the material** across an area. That is a purchase with a legible price.

#### 4.6.1 Reveal is PERSISTED STATE, not decoration

**`damage` and `revealed` are saved world state, exactly like the tree's shape.** Fractures never heal.

This is not a rendering detail — it is the spine of discovery:

- Discovery of materials and regions happens **through** fracture (and colour) reveal. A revealed fracture pattern is a **permanent annotation on the terrain**: *"I know what this is."*
- The player's accumulated fractures across the world are a **map of their own knowledge** — as meaningful as the player-radius map reveal, and separate from it.

**Consequence — area tools are information weapons.** TNT and seismic charges damage and reveal *significant areas*. A seismic charge that reveals a wide region at size-8 **without mining anything** is a **survey instrument**: it costs money and inventory, and it buys knowledge of where the coal seam runs. This falls straight out of the system and is a primary reason the terrain tech pays for itself in gameplay rather than merely looking good.

*(Phase 0: this just means showing the basic quad fractures, persisted.)*

#### 4.6.2 Fractures are DERIVED FROM STRUCTURE — do not add a fracture template

**Cracks are the override tree, rendered.** A fracture is drawn along the quad borders the node *would actually* subdivide into, growing outward from the impact point.

> **Do not add a `fracture_template` field.** It would be a second authored copy of the internal structure — and when the two disagree, the picture lies about the rules. The player learns to read cracks, the cracks turn out to be decorative, trust dies. Deriving them from the tree makes the tell **incapable of being wrong**: it is not a depiction of the structure, it *is* the structure. Same single-writer discipline as §5.2, applied to art. A new template gets its fracture look for free.

**This is the diagnostic mechanic.** Structure *is* character, so distinct materials get distinct silhouettes at zero art cost:

| Material | What the cracks do | Read in one frame |
|---|---|---|
| Hard stone (subdivides one level) | a single clean cross | "solid, 4-way, this will take work" |
| A block with a deep core in Q0 | dense nested lines in one corner, sparse elsewhere | "something is in there" |
| Sand (`pass_down: true`, low resistance) | fine lines everywhere at once | "this is about to collapse" |

**Partial spread.** Fracture growth radiates from the impact point and **need not reach the node's edges**. Cracks stopping mid-block is its own tell, and keeps the reveal proportional to the work done.

**Impact-point legibility is intended, not incidental.** Cracks radiating from where the strike *actually landed* show the player which quadrant they are working — real feedback, given the scan cycles the impact point (§4.3.2).

#### 4.6.3 The opacity rule — FRACTURES CAN ONLY SHOW THE SHAPE OF CHILD NODES

**A fracture draws boundaries *between children that exist*. A node that has not subdivided has no children, therefore no boundaries, therefore nothing inside it can be shown.**

Opacity is not a setting. It is a **consequence of the tree's shape** — which is why there is no `reveal_depth` field and must never be one. An authored "how much to hide" number could contradict the rules; this cannot.

**The hidden core is automatic.** A terminal override (§4.7.1):

```
"Q1.Q2": { resistance: 40, on_break: mine, drop: {gem, size 4} }
```

never subdivides, so it never has children, so **no fracture can ever depict its interior**. It reads as one solid size-4 region with a texture. The player can see *that something is there* — a distinct area that refuses to crack — but not what. They learn only by breaking it, at 40 HP they may not have.

*The converse case does not exist:* a node that **has** subdivided has real child boundaries, and hiding them would be the fracture lying about structure — forbidden above. So the rule is complete.

#### 4.6.4 Reveal follows the damage

**Striking reveals the material of the node struck, and of any siblings sharing its rule.** A terminal core with a different rule stays unrevealed until struck itself — which is what makes §4.6.3's hidden core hold even inside a block whose outer material is known.

**Therefore propagation is a reveal mechanic, not only a breaking one.** Damage that passes down or through (§4.4) carries reveal with it, so a material's propagation pattern determines **how much of itself it gives away per strike**:

- `pass_through: inline` → reveals a band along the blow's axis. Shale gives up its bedding.
- `pass_through: radial` → lights up everywhere at once. Sand cannot keep a secret.
- `pass_through: none` → tells you only what you hit. Hard stone is close-lipped.

How much a strike reveals is thus a function of **tool HP × template propagation** — the same product that governs breaking (§4.3.1). One mechanism, two payoffs.

### 4.7 Templates & authoring

- A **block template** is a recipe for *one block's* internal composition and per-node rules. Templates are used as **brushes** in a terrain painter. A block is a block.
- **Drops:** two independent facts, both authored per material (§5.1):
  - **at what node size** the material becomes minable (`on_break: mine` on size-4 nodes → coal is won by breaking size-4 chunks);
  - **at what size the yielded units come out** (`drop: {coal, size 2}` → four 2×2 units; `{coal, size 4}` → one 4×4 lump; `drop: none` → nothing, it vanishes).
  
  Both are facts about the material, true in any block (§4.0). Unit **count is derived, never authored**: `(node.size / drop.size)²`.
- **Starting materials (5):** dirt, stone, hard stone, sand, + one resource (coal). (Void is not a material — see §4.1.1.)

#### 4.7.1 Templates are SPARSE OVERRIDE TREES, never flat 256-cell arrays

A template is **not** a bottom-up array of all 256 atoms. It is a **sparse tree of overrides, definable at any size and nested only as needed**:

- Every template has a **`default_rule`** (resistance, on_break, drop, pass-down/through behaviour).
- It optionally carries rules keyed by **quad-path** (`Q0`, `Q0.Q3`, `Q1.Q3.Q2`). Each override applies to **that node and everything beneath it**, until a deeper override says otherwise.
- Any node whose path has no override **inherits from its nearest ancestor** that has one.

**Inheritance describes what descendants *would* inherit — it does not force them to exist.** A node's `on_break` alone decides that:

| Override's `on_break` | Effect |
|---|---|
| **`subdivide`** | Children are created and **inherit this rule** (until a deeper override supersedes). This is what makes "this whole quadrant is coal, all the way down" a *single* override. |
| **`mine`** | **Terminal.** The node is destroyed and yields its drop. Children are **never instantiated**, so the rules beneath it are never consulted — inert, not overridden. |

**Worked example — a hidden chunk.** To bury an intact gem inside a block that otherwise breaks down to atoms (`gem` is illustrative — beyond the five Phase-0 materials, but the pattern is what fossils and gems will use):

```
default_rule:                          # ordinary stone, breaks to atoms
  resistance: 1, on_break: subdivide, drop: none

overrides:
  "Q1.Q2":                             # size 4 under a size-16 root
    resistance: 40                     # needs a better tool (§4.3.1)
    on_break: mine
    drop: {gem, size 4}                # one 4x4 lump, not a spray
```

The surrounding stone subdivides normally. `Q1.Q2` never subdivides at all — it sits there as a size-4 node absorbing damage until it breaks whole and yields one gem. **One override, and the chunk is unbreakable-by-structure rather than by special-casing.**

*Count the path when authoring:* each step halves. Under a size-16 root, `Q1` → size 8, `Q1.Q2` → size 4, `Q1.Q2.Q0` → size 2.

*Note this also gives you tool-gating for free:* resistance is tool-relative (§4.3.1), so "unbreakable" means "unbreakable until you buy the drill." A progression gate at zero extra cost.

So the homogeneous prototype block is **one line** — a default, no overrides. "Dirt shell with a coal core" is a default plus ~two overrides. Only a deliberately chaotic hand-authored block approaches 256 entries, and nothing forces you there.

This is structural, not a compression trick:

- **Nodes don't exist until needed.** An unstruck block is **one node in memory**, not 256. Children are instantiated **on break**, reading their rule from the template by path. The world is mostly untouched, so the saved tree is only ever as deep as the player has dug — which is what makes the persistence in §4.6.1 cheap.
- **It matches the brush gesture.** Painting "this quadrant is coal" at size 8 and letting it inherit downward is the natural authoring action.
- **Heterogeneity stays sane.** "Q0 breaks to atoms immediately, Q1 stops at size 4" is two overrides on a default.

**Note — quad-paths are root-relative; sizes are not.** An override key like `Q0.Q3` describes a *position* in a tree, so it means a different physical size under a size-32 root than under a size-16 one. This is fine and intended (paths address position; `size` addresses physical fact), but it is why rules should express thresholds in terms of **size**, not depth.

**Caveat — templates are tied to a specific subdivision geometry.** Overrides are keyed by path, so *rotating* a template (90° etc.) requires transforming the paths (a path rotation is a digit remap — easy, but it must be a **deliberate feature**, not a surprise discovered at authoring time).

#### 4.7.2 Rules are TEMPLATE-AUTHORITATIVE

When a node breaks and instantiates children, children's rules are **read from the template by path** — the template is always authoritative. Rules are **not** copied/frozen into the node at creation.

- **Why:** smaller saves, and retuning a material applies **immediately** without invalidating existing saves. Essential while the whole point of the exercise is experimenting toward good blocks.
- **Trade-off (accepted):** editing a template **changes the saved world's behaviour**.
- **Option at ship:** switch to copy-on-create ("freeze") so each block's behaviour is fixed at authoring time. Flagged now because it is annoying to change late.

### 4.8 Physics (deferred, but not precluded)

No physics in early phases. But **mined units are discrete position-persistent entities from day one**, so falling / shifting / scattering / recombining (mud→dirt) is *additive later*, not a rewrite. See *Ideas for Later*.

---

## 5. Data model

**Persisted form ≠ runtime form.** The save stores the minimum truth; the runtime caches values derived from it. They are allowed to differ.

Conventions (§4.0): all sizes are in **atoms**; quad indices are **0-based row-major** (Q0=TL, Q1=TR, Q2=BL, Q3=BR); **+Y is down**.

### 5.1 Persisted schema (save / authored data)

`Node.size` is **not stored** — it is implicit in nesting depth (`BlockInstance.size >> depth`). An unstorable value cannot be an invalid one.

```
World
  blocks: SpatialIndex<BlockInstance>   # non-overlapping, snapped to atom grid
                                        # returns NOTHING for void (§4.1.1)

BlockInstance
  origin: GridPos                       # in atoms
  size: int                             # edge length in atoms. Blocks are
                                        #   always square, so this alone gives
                                        #   extent: size x size.
                                        #   16 = standard block; 32 = boulder.
                                        #   Same unit and meaning as Node.size.
  template_id                           # rules read from here, always (§4.7.2)
  root: Node

Node                                    # damage & revealed are saved world
  damage: HP                            #   state (§4.6.1, §4.3.1)
  revealed: bool                        # permanent; fractures never heal.
                                        # PER NODE: set on the node struck and
                                        #   on siblings sharing its rule, and
                                        #   carried by pass_down/through
                                        #   (§4.6.4). A terminal core with a
                                        #   different rule stays unrevealed
                                        #   until struck itself.
  children: [Node x4] | null            # indexed Q0..Q3; null = leaf.
                                        # Created ON BREAK only, and ONLY for
                                        #   on_break:subdivide. on_break:mine
                                        #   never instantiates children — it
                                        #   yields them as drops.
                                        # An unstruck block is ONE node.

BlockTemplate                           # SPARSE OVERRIDE TREE (§4.7.1)
  material_id
  display_skin                          # generic pre-reveal look
  colour_class                          # LOSSY family shown at lamp radius
                                        #   (§4.6): brown = dirt|mud|clay|...
                                        #   Deliberately does not identify the
                                        #   material or its cost.
                                        # NB: no fracture_set / fracture
                                        #   template, and no reveal_depth.
                                        #   Cracks are DERIVED from the
                                        #   override tree (§4.6.2–4.6.3).
  default_rule: Rule                    # homogeneous template = this alone
  overrides: map<quad_path, Rule>       # "Q0", "Q0.Q3", "Q1.Q3.Q2"
                                        # applies to that node AND BELOW,
                                        #   until a deeper override supersedes
                                        # paths are root-relative (§4.7.1)

Rule
  resistance: HP                        # HP threshold to break this node
  on_break: {subdivide | mine}          # subdivide -> 4 children of size/2,
                                        #   which INHERIT this rule unless a
                                        #   deeper override supersedes
                                        # mine -> THIS NODE IS DESTROYED.
                                        #   TERMINAL: children are never
                                        #   instantiated, so any override
                                        #   beneath this path is never read.
                                        #   What comes out is `drop`, below.
  drop: none | {material, size}         # none  -> vanish, yields nothing
                                        # else  -> yields units of `size`
                                        #   count = (node.size / drop.size)^2
                                        #   CONSTRAINTS:
                                        #     1 <= drop.size <= node.size
                                        #     drop.size is a power of two
                                        # Count is DERIVED, never authored.
                                        # e.g. size-4 node, drop.size 2 -> 4
                                        #      size-4 node, drop.size 1 -> 16
                                        #      size-4 node, drop.size 4 -> 1
  pass_down: bool                       # §4.4.1 — leftover -> child at impact
  pass_down_falloff: float
  pass_through: {none|inline|lateral|radial|downward}   # §4.4.2 — to siblings
  pass_through_falloff: float
                                        # NB: NO reveal_depth field. Opacity
                                        #   is structural: a fracture can only
                                        #   show boundaries between children
                                        #   that EXIST, so a terminal node
                                        #   (on_break: mine) is inherently
                                        #   opaque. See §4.6.3.

MinedUnit                               # discrete entity, position-persistent
  material_id
  size: int                             # in atoms, from Rule.drop.size
  pos
  (later: velocity, state)
```

Rule lookup: walk the quad-path from the root, keep the deepest matching override, else inherit the nearest ancestor's, else `default_rule`.

### 5.2 Runtime structure (derived cache)

Hit resolution, sibling hops (`pass_through`), rendering, and drop yield all hold a `Node` **without** a root-relative context, so they cannot recover size by descent. The runtime therefore caches it:

```
Node (runtime)
  size: int                             # DERIVED CACHE — edge length in atoms
                                        #   16, 8, 4, 2, 1. Never serialized.
  damage, revealed, children            # as persisted
```

**Derived-cache discipline:**

- **Single writer.** `size` is written in exactly two places — load (`BlockInstance.size >> depth`) and subdivide (`child.size = parent.size >> 1`). Nothing else ever writes it.
- **Assert** `size` is a power of two ≥ 1.
- `size` is **never authored**. Templates key on quad-path, so no author can express an invalid size — there is no field to write it in.
- **`BlockInstance.size` and `Node.size` mean exactly the same thing** — edge length in atoms — and are numerically identical at the root. `size >> 1` therefore reads uniformly from the block all the way down to the atom, with no special case at the top and no seam to introduce bugs.

### 5.3 Typing note

**Enum for names; integer for quantities.** `on_break` and `pass_through` are symbolic — no arithmetic, no ordering, new members append freely — so they are enums. `size` is a physical quantity in atoms: `size >> 1`, `log2`, and drop comparisons ("coal at size 4") are arithmetic on it. An enum would sever `size` from `atoms_across`, requiring a conversion table, and adding a size-32 root would renumber every member. Constrained quantities want asserts, not enums.

---

## 6. Build plan (staged)

The full template + quadtree system must be **designed and specified up front** (this document), but built against a deliberately crippled slice first.

### Phase 0 — Vertical slice ("Does it feel good to dig? Can this system make fun and interesting terrains?")
- Quadtree node engine, **sparse override template structure in place from day one** (§4.7.1) — exercised with **three hand-written templates** (below). Not a full authoring tool; three literals.
- **Size-in-atoms vocabulary from day one** (§4.0) — no level numbering anywhere in code or data.
- **0-based row-major quad indices and +Y-down from day one** (§4.0.1–4.0.2) — conventions are free now and expensive to retrofit.
- `pass_down` / `pass_through` **supported in the data model**; `pass_down` used by *the trap* below, `pass_through` unused (`none`).
- **Atom-atomic**, **three** materials (dirt, stone, coal) over void.
- **Damage + reveal persisted and saved** (§4.6.1) — not deferred; discovery depends on it.
- Fractures **derived from the override tree** (§4.6.2), growing from the impact point, deterministic.
- **The reveal ladder** (§4.6): darkness → colour class at lamp radius → true nature on first strike. At least two materials must **share a colour class**, or the lossiness — and therefore the price of information — is untested.
- Character: walk, climb ladders, mine in facing direction (§3.1). **No jump; up via ladders only.**
- **Impact-point scan** (§4.3.2) — all four directions, spanning the character's 8-atom cross-section. One strike, one hit. Hold-to-mine at the tool's strike rate (§3.1).
- **Air drain + surface refill.** Death = reset.
- The **1024 × 1024 atom dev map** (§4.1.0), hand-authored — no painter yet, hardcoded or JSON. Small enough that the world is a **flat array of blocks** — no chunking, no streaming.

#### The three templates (Phase 0 must be heterogeneous)

**Uniform subdivision is the least interesting thing the system does.** A slice built from one homogeneous template is four identical strikes producing four similar subdivisions — a progress bar with extra steps. It would answer *"does the engine work?"* while leaving *"is this fun?"* untested. Three literals fix that; the same input must produce three different experiences:

1. **The honest block** — the prototype (§4.5). Uniform, 1 HP per level. The baseline.
2. **The liar** — identical when untouched; `Q2` has `resistance: 8`, the rest 1. Strike once: three quadrants crumble, one does not. **The player's "huh?" is the game.**
3. **The gift** — a coal core two levels down that fracturing exposes *before* it can be reached. You can see the coal and must work for it. Contrast a **terminal** core (§4.6.3), which fractures cannot show at all.

Plus one **trap** worth having early: sand with `pass_down: true` and low resistance — one strike collapses a whole size-16, dropping you somewhere you did not choose. Not punishment; **consequence**. Most digging games have no way to dig *wrong*.

#### And one packing test — the boulder in the rubble

Templates are not the only axis. **Mixed-size packing (§4.1.2) is a different question and needs its own test:** bore a tunnel through size-4 rubble with a size-16 hard block embedded three metres in. It reads cheap from outside. It is not.

This tests whether **block borders are legible on untouched terrain** — whether the player can read size as cost *before* committing. If they cannot, the packing axis is invisible and half the terrain vocabulary (§4.1.2) is unreachable. Cheap to build, and it fails loudly.

#### Deliberately excluded from Phase 0 — selling and upgrading

Coal drops and is collected, and that is all. **No shop, no economy, no upgrades.** A shop is a reward schedule bolted onto a core loop; the slice tests the loop, not the schedule. If the terrain is not fun to dig with a single pickaxe and nothing to spend on, no economy will save it. Dig, air, return, die.

*(Ladders still exist — they are traversal, not economy. Grant a fixed stock.)*

- **Goal:** answer both halves of the question above. If the answer is no, this is the cheapest possible place to find out.

#### The risk this phase exists to catch

**The quadtree might be invisible.** If the player only ever sees "block breaks into smaller blocks," the system is an elaborate machine producing the feel of an ordinary mining game. Everything rests on fractures being **readable at a glance** — a 4-way must be instantly distinguishable from a 16-way, in one frame, at speed. **That is an art problem, not an engineering one**, and it is the one Phase 0 is least equipped to notice going wrong. Watch for it deliberately.

**Prerequisite — the legibility test (do this before writing code).** Draw one block at actual pixel size, subdivided 1, 2, 3, and 4 levels deep, plus the three channels of §4.1.2 (colour class, border, fracture) overlaid. Find where it stops reading.

This is twenty minutes of graphics work and it **bounds the entire design space**. A size-16 block at 64 screen pixels has 4px between cracks at 2 levels deep, 1px at 4. If depth 3+ is grey noise, then the usable structural range is 1–2 levels — which is fine (it matches the original instinct that hard materials should only ever crack one level), but it means deep structure is a *special-occasion* effect, not a general vocabulary. **Whatever that number is, it caps how many templates are actually distinguishable** — and therefore how much of §4.1.2's packing vocabulary is real. Better to know before authoring anything.

### Phase 1 — The authoring tools
- **The economy arrives** (deferred out of Phase 0): sell coal at the surface, buy ladders and upgrades. Only bolt the reward schedule on once the loop underneath it is known to be fun.
- **Block template editor**: default_rule + quad-path overrides, pass down/through, drops, colour class. **Layout authoring** (geodes, rings, hollow cores) is an *editing gesture* over these same overrides — painting a hole writes `drop: none`, not a new field (§7).
- **Terrain painter**: templates as brushes onto the atom grid.
- Expand to the full 5 materials. **Heterogeneous templates** (overrides in anger) — where fracture silhouettes start genuinely differing per material (§4.6.2).
- Multiple tools (different HP values and **scan patterns** — tighter cycles concentrate, taller ones carve taller tunnels).
- **Optional steering bias** on the scan (§4.3.2).
- Enable **pass down** — first real tuning of the 90/10 propagation ratio (§4.4.3).

### Phase 2 — Depth & tension
- Depth-scaled air, shoring as a real mechanic, richer economy & upgrades.
- **Pass through** patterns (§4.4.2) — material grain and shattering.
- **Area/information tools**: TNT, seismic charges as survey instruments (§4.6.1).
- Neighbour-block reveal by depth. Deep/hard material variants.
- Place the Jewel of Heaven; wire the win state.

### Phase 3 — Physics & life
- Mined units fall / shift / scatter. Void as flow space. Recombination (mud→dirt). Extra lives. Heat as a second chase factor.

---

## 7. Ideas for Later (parking lot)
- Real drop handling: contact-based collection, particle spawning, non-coal units persisting as physical objects (POC: auto-collect coal, vanish everything else — §4.5).
- **Larger drop sizes as an entity-count lever.** A size-4 coal declaring `drop: {coal, size 4}` spawns **1** pickup instead of 16. Once Phase-3 physics has units falling, this is the difference between a rubble pile and a particle simulation. Expect to tune drop size for performance as much as for feel.
- **Do not let `drop.size` yield more mass than the node held.** `drop.size < 1` or counts exceeding `(node.size / drop.size)²` would mean mining fine yields more material — an exploit, not a mechanic. If a satisfying spray of debris is wanted, that is a **particle effect**: cosmetic, uncountable, never inventory.
- Surgical single-atom mining via `on_break: subdivide` overrides (e.g. picking around a gem — §4.5).
- **Layout patterns (geodes, rings, hollow cores) — already expressible; do NOT add a `layout_template` field.** Which sub-units *exist* is emergent from rules the model already has: a `resistance: 0, on_break: mine, drop: none` override breaks on materialisation and yields nothing — i.e. a hole. A geode is a hard shell + hollow interior + gem core, written as three overrides on one template (§4.7.1). This is strictly more expressive than a separate layout system (per-node, not per-pattern) and costs no new structure. What *is* worth building later: a **layout authoring tool** — the value is in the editing gesture, not in new runtime data.
- Waste-on-overmine (mining past a resource's drop size destroys it).
- Extra/earnable lives softening perma-death.
- Heat as a second chasing factor.
- Air pipes / pockets tied into the shoring system.
- Block recombination over time (mud → dirt).
- Client-side fracture *variation* from a seed — jitter on crack rendering only. **Must not alter which boundaries are drawn**: cracks are the structure (§4.6.2), so variation is roughening the line, never moving it.
- **World scale beyond a flat array** — chunking / streaming. Not needed at POC size; required before the world grows past a few thousand blocks.
- Inventory beyond one-slot-per-item: stacking, weight, or size classes.
- **Boulders** — size-32 (or larger) roots. Already permitted by the model at zero cost (§4.0, §4.2).
- Template rotation (quad-path digit remap — §4.7.1 caveat; row-major makes this a standard, checkable operation).
- Packing quad-paths into a base-4 integer / bitfield (Morton code) for save size — enabled by §4.0.2.
- Freeze-at-ship: switch from template-authoritative to copy-on-create (§4.7.2).
- Additional pass-through patterns as materials demand them.
- **Cross-block pass-through** — spreading damage to spatial neighbours, not just tree siblings. Needed for area tools/TNT (§4.6.1) regardless; would also let material character shape horizontal tunneling.

## 8. Open

Nothing blocking Phase 0. Values expected to move under playtest, not architecture:

- **Scan cycle order** (§4.3.2) — top-to-bottom is a starting point, not a finding.
- **Resistance / HP values** — meaningless until tuned against the tool ladder (§4.3.1).
- **Air drain rate and depth curve.**
- **The 90/10 propagation ratio** (§4.4.3) — the fill/gate balance *is* the game's feel.
- **Ladder cost** — the price of ascent, and therefore of every decision to descend.
