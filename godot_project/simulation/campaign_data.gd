class_name CampaignData
extends Resource

## Epic 4, Story 4.1 — one character's full solo campaign: up to 7 possible
## mini-branches (Story 4.3 lets the player freely pick which/how many, but
## `required_branch_count` of them must be completed before the final node
## unlocks, Story 4.2/4.8).

@export var character: CharacterData
@export var mini_branches: Array = [] # of MiniBranchData — up to 7, untyped (see project-context.md typed-array pitfall note)
@export var required_branch_count: int = 3 # 3-4 per the brainstorm ("3-4. Cela force la rejouabilité.")

## The organizer's final-boss encounter for this character's campaign.
## `opponent`/`is_mook`/`mook_hp_multiplier`/`unlock_reward`/`reward_currency`
## on RivalEncounterData are not meaningful here — only `twist` is read,
## and it must be an "energy_orb_pickup"-type TwistData (Story 4.8).
@export var organizer_encounter: RivalEncounterData
