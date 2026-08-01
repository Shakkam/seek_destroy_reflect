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
