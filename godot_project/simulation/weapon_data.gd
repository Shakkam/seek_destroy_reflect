class_name WeaponData
extends Resource

## Data-driven weapon definition (Custom Resource, per architecture decision
## "Data-Driven Roster System"). Never hardcode weapon stats in code —
## always add/edit a .tres instance under data/weapons/.

@export var id: String = ""
@export var display_name: String = ""
@export var damage: int = 2 # fixed damage per hit (GDD anchors: mitraillette ~2, bazooka ~10, super 20-30). For effect_type == "beam", this is reinterpreted as damage PER SECOND for the pulse's duration instead of per-hit.
@export var fire_rate: float = 5.0 # shots per second — for effect_type == "beam" this gates the cooldown between pulses, same as any other weapon
@export var gauge_max: float = 100.0
@export var gauge_cost_per_shot: float = 10.0 # one-time cost per pulse for effect_type == "beam" too, same as any other weapon
@export var is_heavy: bool = false # triggers a vulnerability window on fire (Story 1.8)

## Epic 2 — what firing this weapon actually does. "damage" (default) is a
## normal projectile per Story 1.5. The others opt into the special
## resolution paths added for Stories 2.4-2.6 (+ the "shmup juice pass"),
## still fired through the same WeaponSystemState/gauge/charge machinery —
## only the *effect* differs by type. "beam" (2026-08-09 redesign, Zoneur:
## "le tir normal de zoneur n'est pas bien... un laser qui traverse toute
## la map, mais qui ne dure que 0.5 secondes... cooldown 0.8 seconde")
## fires a discrete, timed beam PULSE through the exact same cooldown/
## charge dispatch as every other weapon — no more continuous hold-to-
## channel — see MatchArenaNode._spawn_timed_beam() and beam_duration/
## charged_beam_duration below.
@export_enum("damage", "turret", "mobility_boost", "stun", "beam") var effect_type: String = "damage"

# effect_type == "mobility_boost" / "stun" only:
@export var effect_duration: float = 0.0 # seconds
@export var effect_speed_multiplier: float = 1.0 # mobility_boost: e.g. 1.5 = +50% speed

@export var homing_strength: float = 0.0 # 0 = straight line; >0 = gently steers toward target (moved here from being hardcoded per-is_heavy, so any weapon can opt in)
@export var beam_range: float = 500.0 # effect_type == "beam" only: max horizontal reach — set comfortably larger than the arena width for a pulse that "traverse toute la map"
@export var beam_duration: float = 0.5 # effect_type == "beam" only: seconds the normal-fire pulse persists, with a quick fade in/out (2026-08-09)
@export var beam_thickness_multiplier: float = 1.0 # effect_type == "beam" only
@export var charged_beam_duration: float = 0.0 # effect_type == "beam" only: seconds the CHARGED pulse persists — 0 falls back to beam_duration
@export var charged_beam_thickness_multiplier: float = 1.0 # effect_type == "beam" only
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

# Per-weapon projectile speed/spin (2026-08-09, Vif's "Tourbillon" — "un
# petit tourbillon qui tourne sur lui meme en avancant et qui va tres
# vite"). Previously every projectile shared one hardcoded 620 px/s speed
# with no spin at all; both are now data-driven so any weapon can opt in.
@export var projectile_speed: float = 620.0 # matches the old hardcoded default — unset means "unchanged"
@export var projectile_spin_speed: float = 0.0 # deg/sec — rotates the whole projectile node; 0 = no visual spin (the Tourbillon doesn't use this — its 3-frame texture cycle already reads as spinning)

# Vif's Tourbillon (2026-08-09, Camil's drawing): traces small forward-
# advancing loops instead of a straight line. See ProjectileNode.is_looping.
@export var is_looping: bool = false
@export var loop_radius: float = 18.0 # px
@export var loop_angular_speed: float = 1080.0 # deg/sec — how fast/tight each loop is

# Charged fire (2026-08-09, Camil's per-character "tir charge" pass —
# "chaque perso devrait avoir une regle bien a lui"). A quick tap still
# fires normally; holding past charge_fire_duration suppresses normal fire
# entirely while the gauge builds (charge_fire_slow_multiplier applies to
# movement meanwhile) — releasing early wastes the attempt (nothing
# fires), releasing at full charge fires the empowered variant instead.
# 0 duration = this weapon has no charged fire at all (most won't).
@export var charge_fire_duration: float = 0.0 # seconds held before charged fire is ready
@export var charge_fire_slow_multiplier: float = 1.0 # movement multiplier while charging (1.0 = no penalty)
@export var charged_projectile_count: int = 1 # how many shots the charged release fires, spread across charged_burst_spread_deg/charged_stagger
@export var charged_burst_spread_deg: float = 0.0
@export var charged_burst_ping_pong: bool = false # 2026-08-09, Spreader: sweep from -spread/2 to +spread/2 and back within the SAME burst (a triangle wave), instead of one-way linear — "balayer de haut en bas puis remonter de bas en haut"
@export var charged_stagger: float = 0.0 # seconds between each shot in the charged burst — 0 = simultaneous
@export var charged_speed_multiplier: float = 1.0 # multiplies projectile_speed for the charged release only

# Mitrailleur's charged fire (2026-08-09) — first tried as a heat-immunity
# buff (Camil: "pas bien"), replaced with: "les 10 missiles suivants seront
# doubles (paralleles, separes de 10px verticalement)." A pure self-buff on
# release, no projectile burst at all (charged_projectile_count is ignored
# when this is set) — it just arms ShipNode._double_fire_shots_remaining,
# consumed one at a time by MatchArenaNode._on_weapon_fired() on each
# subsequent NORMAL shot.
@export var charged_double_fire_shots: int = 0 # how many subsequent normal shots fire doubled. 0 = disabled.
@export var charged_double_fire_offset: float = 10.0 # px vertical separation between the two parallel shots
