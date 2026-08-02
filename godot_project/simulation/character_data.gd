class_name CharacterData
extends Resource

## Data-driven character definition (Custom Resource), per architecture
## decision "Data-Driven Roster System" (Epic 2, Story 2.1). Adding or
## tuning a character is authoring/editing a .tres — never a code change.

@export var id: String = ""
@export var display_name: String = ""
@export var archetype: String = "" # e.g. "Lourd", "Contrôleur", "Mitrailleur"...
@export var kit: Array = [] # of WeaponData — ordered weapon kit, index 0 = default selected weapon (see project-context.md re: avoiding typed-array assignment pitfalls)
@export var complexity: String = "intermediate" # "beginner" | "intermediate" | "advanced" — Zangief-style spread (GDD)
