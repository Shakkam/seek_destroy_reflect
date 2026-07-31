# Decision Log — GDD: Seek and Destroy and Reflect the Ball

## 2026-07-31 — Session start

- **Intent**: Create (no prior GDD exists).
- **Source input**: Game Brief at `_bmad-output/planning-artifacts/briefs/brief-seek-and-destroy-and-reflect-the-ball-2026-07-30/brief.md`, itself built on the full brainstorming session (`_bmad-output/brainstorming-session-2026-07-29.md`). Both will be drawn from directly rather than re-derived.
- **Game type matched**: **Fighting** (high complexity — frame data, rollback netcode, input parsing, combo boundaries, training mode all require documentation). Competing signal: **Shooter** (aiming/projectile/weapon-feel conventions), resolved as: Fighting is the structural/primary type (1v1 PvP, roster, matchup-driven), with Shooter-genre conventions (weapon feel, aiming) folded into the Fighting-specific section as an explicit extension rather than switching primary type — this mirrors the brief's own "double vigilance" differentiator (neither pure Pong nor pure fighting game).

## 2026-07-31 — Pillars confirmed, tie-breaker recorded

- The brief's 3 pillars (Spatial Control, Return Precision, Mastered Power Escalation) are confirmed as-is for the GDD — no changes.
- **Tie-breaker precedent for Spatial Control**: when forced to choose between a larger arena (more strategic space to manage) and a smaller/tighter arena (more intense, less room to flee), the user's explicit preference is **intensity over expansive strategic space**. This should steer stage-size decisions in Stage Design and Level Design Framework toward tighter, higher-intensity arenas rather than sprawling ones.

## 2026-07-31 — Core loop numbers

- **Match format**: Best of 3 rounds, total match time budget ≤ 5 minutes → each round targets roughly **90-120 seconds**. Smash Bros-style tension build-up preferred over Street Fighter's immediate-tension pacing.
- **HP pool**: **100 HP** per character, gauge-based (not abstract), to allow fine per-weapon damage tuning.
- **Damage model**: **fixed integer damage per hit**, not percentage-based. Example anchors given by user: machine-gun-type weapon ≈ **2 damage/shot**; bazooka-type weapon ≈ **10 damage/hit**; "super"-tier weapons ≈ **20-30 damage** for a single high-commitment hit.
- **Missed-ball penalty — RESOLVED via party-mode consult (2026-07-31)**: **Option B — fills the opponent's weapon gauge**, in significant quantity (equivalent to a full light-weapon charge, ~5-10 machine-gun shots). Direct flat damage (option A) and the stacked option (C) were both rejected: A would let a missed ball alone deal bazooka-tier damage (10 dmg) for free, undermining the weapon/gauge economy and contradicting the already-locked rule that the ball never deals damage directly; C risked a crushing double-punish (damage + full enemy gauge) for a single mistake, flagged by dev-feasibility concerns as likely to feel unfair in playtesting. B preserves the HP pool from an unearned "one-shot" feeling, keeps a catch-up window (opponent must still land a shot to convert the advantage), and stays consistent with gauges being the game's core resource currency. Required follow-through: strong visual feedback (flash + gold-outline gauge fill-up) on the opponent's ship when this triggers, so the moment still reads as a real "oh no" beat despite not being direct damage.
- **Gauge fill from ball returns**: a standard successful return fills a weapon's gauge to a normal amount — user's anchor example: enough to grant **5-10 machine-gun shots** worth of ammo per fill. A stylish/risky return (lift, trick shot) grants a **bonus fill percentage on top** (e.g. a "+100%" popup) — explicitly desired as a satisfying juice moment, to be shown on-screen.
- **Ball damage**: reconfirmed — the ball **never deals damage directly**; that is not its role. This holds for V1, not just as an earlier brainstorming idea.

## 2026-07-31 — Movement & control feel

- **Movement speed**: "relatively fast, but not extreme" — the ship must feel like an extension of the player ("**un troisième bras**" — a third arm), not a burden to wrangle. This exact phrase is the target feel descriptor, worth preserving verbatim in the GDD.
- **Inertia**: user is not a fan of acceleration/braking inertia by default — leans toward direct/responsive control. Explicitly deferred to prototype testing rather than locked now ("on verra avec le proto si ça a du sens") — flagged as a prototype-validated item, not a final decision.
- **Ball speed**: increases slightly with each rally exchange, to intensify the tail end of a rally (classic Pong-style escalation), consistent with match pacing goals.
- **Dedicated dodge mechanic**: explicitly CUT from V1 (not deferred vaguely — a deliberate scope decision). Reasoning: the player already juggles ball-tracking, dodging enemy fire via positioning, managing own weapons, and spatial control — adding a dedicated dodge action (dash/roll/i-frames) was judged as too much simultaneous cognitive load for V1. Evasion in V1 is achieved purely through normal movement/positioning. This is an Out of Scope item for the GDD, with an explicit reopen option post-prototype.

## 2026-07-31 — Roster archetypes & balance philosophy

- **Confirmed archetypes for the 8-character roster** (at least these 4 should be represented): **Heavy hitter** (big single hits, slow), **Controller** (turret/zone-control style, per the earlier free-placement turret decision), **Machine-gunner** (rapid spray weapon), **"Vif"/Agile** (fast, presumably lower per-hit damage, higher mobility/utility). Exact 8th roster composition not yet fully specified — to detail later in Character Roster section.
- **Balance philosophy**: aiming for a **fully-viable roster** (no character intentionally weak/filler), closer to modern SF6-style balance ambition than an accepted-tier-list philosophy. **Intended methodology**: AI-driven testing/simulation as a balancing tool (agent-vs-agent playtesting to surface imbalances), not just human playtesting — flagged as a testing/production-phase concern (relevant to `gds-test-design`/`gds-test-automate` later), not a game-design decision itself.
- **Complexity spread desired**: explicitly wants variation in learning-curve/skill-ceiling across the roster, citing **Zangief (Street Fighter)** as the reference model — hard to learn, high skill ceiling, very rewarding when mastered. Not all 8 characters should have uniform complexity.

## 2026-07-31 — Weapon activation & control scheme revision

- **Control scheme revision**: the earlier Constraint Box hypothesis (long-press + direction to select a weapon) is **overridden** — user now prefers a **dedicated second button for weapon selection**, separate from movement, specifically because tying selection to a long-press would freeze/block ship movement, which conflicts with the "third arm" responsive-control goal. Revised flow: select weapon (dedicated input) → press fire button → weapon fires. Movement is never blocked by weapon selection.
- **Machine-gun fire rate**: **4-6 shots/second** while firing.
- **Heavy-weapon vulnerability window**: CONFIRMED as a desired design direction — firing a heavy weapon (e.g. bazooka) should create a recovery-style vulnerability window (reduced mobility/exposure during the firing animation), similar in spirit to special-move recovery frames in traditional fighting games. Exact frame/timing values not yet set — to be defined precisely per-weapon in Move Lists and Frame Data.

## 2026-07-31 — Reference material: Air Zonk weapon list

User supplied the reference weapon roster from **Air Zonk** (PC Engine) as direct inspiration for weapon variety/design, to be captured in the GDD as reference material for Move Lists and Frame Data / weapon design (not yet mapped to the 8-character roster or archetypes):

- **Boxing Glove** — launches gloves that fly straight or bounce
- **Boomerangs** — return to the player or exit-screen before re-throwable
- **Alligator Teeth** — a jaw that bites through anything in its path
- **Throwing Cards** — scattered/spread forward projectiles
- **Laser** — powerful but limited range
- **Homing Missiles** — self-guided projectiles that track targets
- **Mini-Zonk** — drastically shrinks the character (and hitbox/vulnerability zone) while keeping full firepower and enabling 4-directional fire

Early pattern-matching (not locked): Laser → fits a "precision" archetype; Homing Missiles → fits the Controller archetype; Mini-Zonk → an interesting risk/reward mechanic (smaller hitbox + full power) worth considering as a character-specific gimmick rather than a universal weapon.

## 2026-07-31 — Combo system, defensive utility, competitive online scope

- **Combo system**: CONFIRMED as desired, in a limited/indirect form (not traditional input-chain combos). Example given by user: a character could have a "paralyzing flash" weapon/effect that stuns the opponent for ~1 second, opening a window to land a heavy hit. This implies at least one character-specific stun/setup tool exists in the roster, enabling weapon-to-weapon synergy for that character — to be detailed per-character in Move Lists and Frame Data rather than as a universal system.
- **Defensive mechanics — refined**: no dedicated block/dodge action confirmed (unchanged), BUT user opened the door to **weapon-granted temporary mobility boosts** (example: a "tornado"-type weapon granting a brief speed boost) as an indirect defensive/repositioning tool. This is consistent with the earlier "no dedicated dodge" decision — evasion utility comes through the weapon/character kit rather than a universal player action.
- **Competitive online scope**: **no ranked/MMR for initial online launch** — a simple quick-match 1v1 is sufficient to start. Ranked matchmaking is explicitly flagged as a **post-launch consideration, conditional on the game finding an audience** ("si le jeu est bien, il faudra l'envisager") — not a V1/full-MVP commitment, to be noted in Out of Scope / Success Metrics rather than Competitive Features as a locked feature.
- **Netcode model (rollback vs. delay-based)**: still OPEN — not resolved in this session. Flagged as a technical decision to hand off to `gds-game-architecture` rather than decide at GDD level, though the GDD will note the genre expectation (competitive real-time 1v1 strongly favors rollback) as context for that downstream decision.

## 2026-07-31 — Campaign scope, audio direction, technical target

- **Campaign scope clarified**: "10 fights per character with branching paths" is an **aspirational target, not an acted/committed V1 campaign scope** — user explicitly confirmed this is a direction to aim for, not a locked production commitment. GDD will document it as a target/vision for the campaign content breadth, with the full-MVP tier's "small campaign" wording from the brief remaining the actual near-term commitment, and the branching/10-fight structure noted as the long-term ambition to scale toward.
- **Audio direction**: confirmed — **metal with an electronic touch**. Notably, the user is a musician themselves, so music composition is an **internal team skill/asset**, not a role requiring external hiring or budget — a meaningfully different production consideration than typical solo-dev audio sourcing.
- **Technical performance target**: **30 FPS, locked/stable** (not just "30-60, whatever") — user explicitly chose a locked 30 over an unlocked/variable higher framerate, aligning with the earlier note that frame-timing stability matters more than raw FPS count for a game where vulnerability windows and reaction timing are gameplay-relevant.

## 2026-07-31 — Finalize

- **gdd.md and epics.md drafted** in full, incorporating every decision logged above plus the prior game brief and brainstorming session as source material.
- **Discipline self-check**: added a **Training Mode** open item to Competitive Features — a standard fighting-game genre convention (per `assets/game-types/fighting.md`) that was not discussed in this session. Flagged as `[NOTE FOR DESIGNER]` rather than silently included or omitted, given the roster's intentional high-complexity characters (Zangief-style) make a training mode more valuable than average.
- **No doc_standards configured** for this module (empty array) — no polish-pass subagents required at Finalize. **No reviewers/required_reviewer configured** — no validation gate to clear beyond this session's own discipline self-check.
- **No `<narrative-workflow-critical/recommended>` flag** present in the matched Fighting genre guide — `needs_narrative` NOT set. `gds-create-narrative` not offered automatically at Finalize; the campaign's "light narrative per character" remains a GDD-level note only, revisitable manually if desired.
- **Next recommended step**: `gds-game-architecture` (engine choice, netcode model decision, technical system design) — the GDD explicitly defers all engine-implementation and netcode-model decisions to that phase.
- User requested (mid-session, outside this workflow's normal Finalize flow): (1) an HTML rendering of the GDD with non-stylized/non-animated wireframe "screenshots", and (2) pushing all resulting artifacts to GitHub. Both handled as ad-hoc requests layered on top of this Finalize, not as part of the skill's own external_handoffs (which remain empty/unconfigured for this module).
