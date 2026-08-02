class_name WeaponData
extends Resource

## Data-driven weapon definition (Custom Resource, per architecture decision
## "Data-Driven Roster System"). Never hardcode weapon stats in code —
## always add/edit a .tres instance under data/weapons/.

@export var id: String = ""
@export var display_name: String = ""
@export var damage: int = 2 # fixed damage per hit (GDD anchors: mitraillette ~2, bazooka ~10, super 20-30)
@export var fire_rate: float = 5.0 # shots per second
@export var gauge_max: float = 100.0
@export var gauge_cost_per_shot: float = 10.0
@export var is_heavy: bool = false # triggers a vulnerability window on fire (Story 1.8)

## Epic 2 — what firing this weapon actually does. "damage" (default) is a
## normal projectile per Story 1.5. The others opt into the special
## resolution paths added for Stories 2.4-2.6, still fired through the same
## WeaponSystemState/gauge machinery — only the *effect* differs by type.
@export_enum("damage", "turret", "mobility_boost", "stun") var effect_type: String = "damage"

# effect_type == "mobility_boost" / "stun" only:
@export var effect_duration: float = 0.0 # seconds
@export var effect_speed_multiplier: float = 1.0 # mobility_boost: e.g. 1.5 = +50% speed

@export var homing_strength: float = 0.0 # 0 = straight line; >0 = gently steers toward target (moved here from being hardcoded per-is_heavy, so any weapon can opt in)
