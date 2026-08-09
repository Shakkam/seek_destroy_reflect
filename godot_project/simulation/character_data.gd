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

## 2026-08-09 (Camil: "chaque perso devrait avoir une regle bien a lui. un +
## et un -") — an opt-in per-character movement/lift rule that replaces the
## shared hold-to-charge lift, read by ShipNode. "none" = the original
## shared mechanic, untouched. "dash_lift" (Vif's rewrite) is the first:
## the MINUS is he can never charge a lift at all (always 0% outside a
## dash); the PLUS is the Lift button instead triggers a short directional
## dash, and a ball return connecting during that dash carries a fixed
## "leger lift" (ShipNode.DASH_LIFT_CHARGE) instead of nothing. Add new
## values here (and a matching branch in ShipNode) as more characters get
## their own rule — never hardcode a rule to a character id in ShipNode.
## "heavy_push" (Lourd): a fully-charged (100%) lift return knocks the
## opponent back on contact — see BallNode._resolve_ships()/
## ShipNode.apply_knockback() (2026-08-09, Camil: "il faudrait donc que ca
## 'pousse' la balle et que cette derniere pousse le joueur adverse").
@export_enum("none", "dash_lift", "heavy_push") var special_rule: String = "none"

## 2026-08-09 (Camil: "seul mitrailleur tire plusieurs fois d'affilee quand
## on laisse appuye... pour les autres, il faut appuyer plusieurs fois pour
## tirer plusieurs fois") — orthogonal to special_rule (a base firing-input
## distinction, not a lift/movement rule). false (default, everyone except
## Mitrailleur) = semi-auto, one shot per discrete press/release, even
## during a charge-capable weapon's pre-charge grace window. true = full
## auto, fires repeatedly for as long as Tir is held (gated only by the
## weapon's own cooldown/gauge, as every weapon originally worked).
@export var full_auto: bool = false
