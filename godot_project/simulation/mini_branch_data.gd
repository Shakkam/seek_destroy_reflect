class_name MiniBranchData
extends Resource

## Epic 4, Story 4.1 — one of a character's up to 7 mini-branches: a 3-fight
## arc (2 mooks -> 1 "real" rival) targeting a specific roster archetype.
## Order between mini-branches is free (Story 4.3); order WITHIN one is
## fixed: mook_1 -> mook_2 -> rival.

@export var id: String = ""
@export var display_name: String = "" # the target archetype's name, e.g. "Contre Lourd"

@export var mook_1: RivalEncounterData
@export var mook_2: RivalEncounterData
@export var rival: RivalEncounterData

## Preview art for the campaign map node (Story 4.2) — optional, falls back
## to a placeholder in the node UI when unset, same "no art yet" approach
## used throughout Epic 2's weapon VFX.
@export var preview_texture: Texture2D
