class_name RivalEncounterData
extends Resource

## Epic 4, Story 4.1 — a single encounter within a mini-branch: either one
## of the two "mook" warm-up fights, or the mini-branch's "real" rival.

@export var opponent: CharacterData
@export var is_mook: bool = true

## 2026-08-18 (Camil: "un monde par rival... les cases seraient plutot des
## niveaux, ou le joueur devrait effectuer certaines taches... on peut
## inventer plein de mini jeux sympa") — a mook-slot encounter (mook_1/
## mook_2 only — the rival/organizer slot always stays "combat", the real
## fight/story beat never becomes a minigame) can be a different
## challenge instead of a straight 1v1. "combat" (default) = the existing
## MatchArena fight, unchanged. New values route MiniBranchMapNode's
## confirm to a different scene instead — see MiniBranchMapNode._confirm().
@export_enum("combat", "breakout", "space_invaders") var challenge_type: String = "combat"

## Mooks only — a reduced-strength version of the archetype rather than a
## new AI system (Story 4.4): scales the mook's starting HP down and, when
## set, overrides how eagerly its AI_PROFILES-driven behavior pushes the
## frontier. 1.0 = same as a normal ship_state.gd START_HP.
@export var mook_hp_multiplier: float = 0.6

## Real rival only — the twist applied for the duration of this fight
## (Story 4.5/4.6). Left unset (null) for mooks.
@export var twist: TwistData

## Real rival only — reward unlocked on victory: a bonus variant "traced"
## from this rival, not a copy of their actual weapon (Story 4.6). Left
## unset for mooks, which grant currency instead (see reward_currency).
@export var unlock_reward: WeaponData

## Mooks only — Exp/Gold granted on victory (Story 4.4/4.9).
@export var reward_currency: int = 100
