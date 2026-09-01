class_name UltraMeterNode
extends Node2D

## Story (2026-08-13, "systeme des 5 balles" backlog, see project memory
## super-meter-backlog-idea) — draws a row of pip indicators for a ship's
## ultra meter (fills on the OPPONENT missing the ball, see
## ball_node.gd's _resolve_out_of_bounds(); triggered by ShipNode once
## full). Pure presentation: MatchArenaNode sets `pips` every frame from
## ship.weapon_state.ultra_pips, this just draws it. Same "_draw() shapes,
## no imported textures" convention as CampaignMapNode/CharacterSelect.
## Named "ultra" not "super" — collides with the GDD's existing "arme
## 'super'/lourde" weapon-tier naming otherwise (separate party-mode
## brainstorm, Epic 4 memlog; file was originally super_meter_node.gd).

@export var max_pips: int = 5
@export var pip_color: Color = Color(1, 0.84, 0.29, 1) # same gold as MatchLabel's "Victoire !"/the GO! flash — reads as "big moment" across the HUD
@export var pip_size: float = 16.0
@export var spacing: float = 6.0

var pips: int = 0:
	set(value):
		if pips != value:
			pips = value
			queue_redraw()

# Bug report (Ben's playtest via Camil, 2026-08-31: "si les blocs jaunes
# sont bien des ults je n'arrive pas a les lancer quand je veux") — pressing
# the ultra key while the meter isn't full does nothing at all, silently.
# That's correct (an ultra genuinely can't fire early), but the silence
# itself reads as "broken/unresponsive". flash_denied() gives the meter a
# brief red shake so an early press is visibly acknowledged instead of
# looking ignored — called by MatchArenaNode on ShipNode.ultra_denied.
const DENY_SHAKE_DURATION := 0.25
const DENY_COLOR := Color(0.92, 0.28, 0.24, 1)
var _deny_shake_timer := 0.0

func flash_denied() -> void:
	_deny_shake_timer = DENY_SHAKE_DURATION

func _process(delta: float) -> void:
	if _deny_shake_timer <= 0.0:
		return
	_deny_shake_timer = maxf(_deny_shake_timer - delta, 0.0)
	queue_redraw()

func _draw() -> void:
	var shaking := _deny_shake_timer > 0.0
	# Decaying sine jitter, not a fixed offset — a shake that just held one
	# spot for 0.25s would read as a static nudge, not "shaking".
	var shake_x := sin(_deny_shake_timer * 90.0) * (_deny_shake_timer / DENY_SHAKE_DURATION) * 4.0 if shaking else 0.0
	for i in max_pips:
		var pos := Vector2(i * (pip_size + spacing) + shake_x, 0.0)
		var rect := Rect2(pos, Vector2(pip_size, pip_size))
		var outline_color := DENY_COLOR if shaking else pip_color
		if i < pips:
			draw_rect(rect, outline_color if shaking else pip_color, true)
		else:
			draw_rect(rect, Color(outline_color.r, outline_color.g, outline_color.b, 0.18), true)
		draw_rect(rect, outline_color, false, 2.0)
