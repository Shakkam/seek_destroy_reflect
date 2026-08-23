class_name PassiveHealFxNode
extends Node2D

## Spreader's passive reward (2026-08-16, Camil: "un eventail apparait et
## tourne autour du joueur pendant 1 sec et lui redonne 15% de PV") —
## purely cosmetic, the actual heal is applied directly by MatchArenaNode/
## ShipNode.apply_heal() the moment this spawns, not tied to this node's
## lifetime. Parented to the ship itself so it follows for free without
## needing to track a moving target; two full orbits over `duration` reads
## as a lively little flourish rather than a single slow drift.

const TEXTURE := preload("res://assets/art/vfx/bonbon.png") # Éventail/Spreader's own established shot sprite (see BONBON_TEXTURES)

var duration := 1.0
var radius := 26.0

var _elapsed := 0.0
var _sprite: Sprite2D

func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = TEXTURE
	_sprite.scale = Vector2.ONE * 0.8
	add_child(_sprite)

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= duration:
		queue_free()
		return
	var t := _elapsed / duration
	var angle := t * TAU * 2.0 # two full orbits over the whole duration
	_sprite.position = Vector2(cos(angle), sin(angle)) * radius
	_sprite.modulate.a = 1.0 - t # fades out as it completes its spin
