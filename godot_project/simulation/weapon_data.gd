class_name WeaponData
extends Resource

## Data-driven weapon definition (Custom Resource, per architecture decision
## "Data-Driven Roster System"). Never hardcode weapon stats in code —
## always add/edit a .tres instance under data/weapons/.

@export var id: String = ""
@export var display_name: String = ""
@export var damage: int = 2 # fixed damage per hit (GDD anchors: mitraillette ~2, bazooka ~10, super 20-30). For effect_type == "beam", this is reinterpreted as damage PER SECOND instead of per-hit.
@export var fire_rate: float = 5.0 # shots per second — unused for effect_type == "beam" (continuous, no discrete shots)
@export var gauge_max: float = 100.0
@export var gauge_cost_per_shot: float = 10.0 # For effect_type == "beam", reinterpreted as gauge drained PER SECOND while held instead of a one-time cost.
@export var is_heavy: bool = false # triggers a vulnerability window on fire (Story 1.8)

## Epic 2 — what firing this weapon actually does. "damage" (default) is a
## normal projectile per Story 1.5. The others opt into the special
## resolution paths added for Stories 2.4-2.6 (+ the "shmup juice pass"),
## still fired through the same WeaponSystemState/gauge machinery — only the
## *effect* differs by type. "beam" is the odd one out: it bypasses the
## discrete cooldown-gated fired() entirely in favor of continuous
## WeaponSystemState.beam_tick() while the fire button is held.
@export_enum("damage", "turret", "mobility_boost", "stun", "beam") var effect_type: String = "damage"

# effect_type == "mobility_boost" / "stun" only:
@export var effect_duration: float = 0.0 # seconds
@export var effect_speed_multiplier: float = 1.0 # mobility_boost: e.g. 1.5 = +50% speed

@export var homing_strength: float = 0.0 # 0 = straight line; >0 = gently steers toward target (moved here from being hardcoded per-is_heavy, so any weapon can opt in)
@export var beam_range: float = 500.0 # effect_type == "beam" only: max horizontal reach, capped below the full arena width so the shooter must close distance rather than poke from the back wall (2026-08-05 playtest)
@export var turret_hp: float = 22.0 # effect_type == "turret" only: destroyed by opponent fire once its HP runs out (2026-08-05 playtest: "faudrait qu'elle soit destructible (20/25 PV)")
@export var turret_lifetime: float = 25.0 # effect_type == "turret" only: seconds before it expires on its own if not destroyed first (2026-08-05 playtest: was a flat 6s, "devraient durer bien plus longtemps, au moins 20-30 secondes")

# "Shmup juice pass" (2026-08-05 feedback: "réveiller l'esprit shoot'em up") —
# data-driven so tuning any of this is authoring a .tres, never a code change.
@export var spread_deg: float = 2.0 # random angle jitter per shot, non-heavy weapons only (heavy stays true to its aim)
@export var projectile_count: int = 1 # fires this many projectiles per shot, e.g. a missile swarm — each spread across burst_spread_deg and staggered by burst_stagger
@export var burst_spread_deg: float = 0.0 # angular fan across a multi-projectile burst (see projectile_count)
@export var burst_stagger: float = 0.0 # seconds between each projectile's spawn within a burst — 0 = all at once
@export var is_boomerang: bool = false # curves outward then arcs back to the shooter instead of flying straight/homing (can hit once on the way out and once on the way back)
@export var visual_scale_multiplier: float = 1.0 # extra engine-side size multiplier on top of the base projectile scale, per weapon (2026-08-06 playtest: Éventail needed to read bigger)

# Heat gauge (2026-08-08 playtest: "Mitraillette, c'est trop fort. Il
# faudrait un cooldown de 1s tous les... 6 tirs ?"; redesigned 2026-08-09
# after "je tire 4 balles, j'attends 3 secondes, et je ne peux tirer que 2
# balles => frustrant" — a flat shot-count-then-hard-lockout counter never
# decayed on a partial pause). A continuous gauge instead: each shot adds
# heat_per_shot, heat drains at heat_cooldown_rate/sec whenever NOT firing,
# and firing is blocked once heat reaches heat_max — so ANY pause helps a
# little, not just a full stop-and-wait. 0 = disabled (most weapons don't
# need this; their fire_rate/gauge_cost_per_shot already self-limits).
@export var heat_max: float = 0.0 # 0 = no heat limit at all
@export var heat_per_shot: float = 0.0
@export var heat_cooldown_rate: float = 0.0 # heat drained per second while not firing
