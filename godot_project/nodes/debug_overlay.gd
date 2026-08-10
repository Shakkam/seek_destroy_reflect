extends Node

## Global debug-visualization toggle (2026-08-10, Camil: "j'aimerais que tu
## me mettes les hitbox autour de TOUTES les armes, activables en appuyant
## sur la touche TAB. cela me permettra de comprendre pourquoi certaines
## fois je ne touche pas") — purely a rendering concern, no simulation class
## reads this (see project-context.md, Regle absolue n1). Any node that owns
## a hitbox weapons actually check against (ShipNode.half_extents,
## TurretNode.HALF_EXTENTS) draws its own outline in _draw() when this is
## true — see each node's _draw() for the exact rect, which intentionally
## matches the rect ProjectileNode._segment_crosses_rect() checks against,
## not the (larger) ball-catch rect BallNode uses — this is about "pourquoi
## je ne touche pas [avec mes armes]", not the ball paddle.
var show_hitboxes := false

func _input(event: InputEvent) -> void: # _input, not _unhandled_input — must fire even if a Control (menu, etc.) has focus and would otherwise consume Tab first
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		show_hitboxes = not show_hitboxes
