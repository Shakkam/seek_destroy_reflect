class_name TwistData
extends Resource

## Epic 4, Story 4.5 — data-driven "match twist" definition. A rival/boss
## encounter references one of these by resource, and MatchArenaNode applies
## its configuration for the duration of that match. Reuses existing
## systems wherever possible (see project-context.md, Regle absolue n1 —
## no simulation logic lives here, this is pure data) instead of a
## per-encounter bespoke system, per the brainstorm's explicit solo-dev
## scope discipline (2026-08-07).

@export var id: String = ""
@export var display_name: String = ""

## What kind of twist this is — drives which MatchArenaNode/ship systems
## read the fields below. Mirrors WeaponData's effect_type pattern.
@export_enum("none", "multi_ball", "gauge_floor", "shrinking_arena", "invisible_opponent", "hazard_zones", "drifting_neutral_zone", "visual_decoy", "energy_orb_pickup") var twist_type: String = "none"

# twist_type == "multi_ball" only:
@export var ball_count: int = 2 # 2 = double balle, 3 = triple (Camil: "même triple si on veut pousser le bouchon")

# twist_type == "gauge_floor" only — Story 4.5: self-fill on successful
# return (Story 1.7) is locked, but MISS_GAUGE_FILL (Story 1.6) is never
# touched — "sinon on perd le core game" (Camil).
@export var passive_trickle_rate: float = 2.5 # % of gauge_max per second, guarantees no softlock

# twist_type == "shrinking_arena" only:
@export var shrink_interval: float = 15.0 # seconds between each shrink step
@export var shrink_fraction: float = 0.1 # fraction of depth removed per side, per step
@export var shrink_animation_duration: float = 1.5 # seconds — never instant, ships get pushed smoothly to the new bounds

# twist_type == "hazard_zones" only:
@export var hazard_count: int = 2
@export var hazard_radius: float = 24.0
@export var hazard_spawn_interval: float = 8.0
@export var hazard_lifetime: float = 6.0
@export var hazard_stuns_ships: bool = true
@export var hazard_deflects_ball: bool = true

# twist_type == "drifting_neutral_zone" only: continuous back-and-forth
# motion at drift_speed (no separate "animation duration" needed — a
# constant-velocity drift is inherently never instant, satisfying the same
# "never push a ship out of bounds" guard as shrinking_arena for free,
# since ShipState's per-tick clamp already follows frontier_x smoothly).
@export var drift_speed: float = 40.0 # px/sec
@export var drift_range: float = 120.0 # max distance from the arena's true center before reversing direction

# twist_type == "visual_decoy" only ("Double moi" — zero damage, zero HP, pure confusion):
@export var decoy_wander_speed: float = 180.0

# twist_type == "energy_orb_pickup" only — Story 4.8, the organizer's OWN
# signature mechanic, deliberately NOT part of the shared 7-entry pool above
# (Cloud/Indie: reserved for the boss because it needs its own spawn/pickup
# state machine, not worth the cost for every rival fight).
@export var orb_gauge_bonus_percent: float = 20.0 # reuses WeaponSystemState.with_gauge_added(), no new gauge system
@export var orb_spawn_interval: float = 10.0
