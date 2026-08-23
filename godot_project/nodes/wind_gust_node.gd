class_name WindGustNode
extends Node2D

## Vif's Ultra rework — "Bourrasque" (2026-08-15, Camil, with a reference
## image): alongside the vortex swarm (see MatchArenaNode._ultra_
## bourrasque()), a continuous gust shoves the opponent toward THEIR OWN
## outer wall for the whole attack — a positioning debuff distinct from
## the vortices' own damage, not tied to any radius/location (the target
## is affected everywhere on their side, not just near a hazard point),
## so unlike BlackHoleNode/the old WindVortexNode this has no visual
## ring and no position of its own that matters.
##
## 2026-08-16 playtest correction: "bourrasque ne pousse pas au contact, ca
## pousse tout le temps de l'ultra" — this push was never meant to be an
## on-hit knockback (that was a misread of the "plus les tourbillons vont
## vite, plus la poussee est forte" request); it's this EVERY-FRAME shove,
## already running for the whole attack, that must ramp up. push_speed now
## grows linearly from push_speed_start to push_speed_end over `duration`,
## mirroring the vortices' own acceleration (see MatchArenaNode.
## _ultra_bourrasque(), which derives both ends straight from
## BOURRASQUE_VORTEX_START_SPEED/ACCELERATION) — "a la fin normalement le
## joueur adverse ne peut meme plus avancer, il doit meme un poil reculer".

var duration := 3.0
var push_speed_start := 90.0
var push_speed_end := 90.0
var target: ShipNode

var _total_duration := 0.0

func _ready() -> void:
	_total_duration = duration

func _physics_process(delta: float) -> void:
	duration -= delta
	if duration <= 0.0:
		queue_free()
		return
	if not is_instance_valid(target):
		return
	var elapsed_fraction := 1.0 - clampf(duration / _total_duration, 0.0, 1.0)
	var push_speed := lerpf(push_speed_start, push_speed_end, elapsed_fraction)
	var direction := -1.0 if target.side == 0 else 1.0 # away from the frontier, toward the target's own outer wall
	target.apply_knockback(Vector2(direction * push_speed * delta, 0.0))
