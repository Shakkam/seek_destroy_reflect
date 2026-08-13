class_name SuperMeterNode
extends Node2D

## Story (2026-08-13, "systeme des 5 balles" backlog, see project memory
## super-meter-backlog-idea) — draws a row of pip indicators for a ship's
## super meter (fills on the OPPONENT missing the ball, see
## ball_node.gd's _resolve_out_of_bounds(); triggered by ShipNode once
## full). Pure presentation: MatchArenaNode sets `pips` every frame from
## ship.weapon_state.super_pips, this just draws it. Same "_draw() shapes,
## no imported textures" convention as CampaignMapNode/CharacterSelect.

@export var max_pips: int = 5
@export var pip_color: Color = Color(1, 0.84, 0.29, 1) # same gold as MatchLabel's "Victoire !"/the GO! flash — reads as "big moment" across the HUD
@export var pip_size: float = 16.0
@export var spacing: float = 6.0

var pips: int = 0:
	set(value):
		if pips != value:
			pips = value
			queue_redraw()

func _draw() -> void:
	for i in max_pips:
		var pos := Vector2(i * (pip_size + spacing), 0.0)
		var rect := Rect2(pos, Vector2(pip_size, pip_size))
		if i < pips:
			draw_rect(rect, pip_color, true)
		else:
			draw_rect(rect, Color(pip_color.r, pip_color.g, pip_color.b, 0.18), true)
		draw_rect(rect, pip_color, false, 2.0)
