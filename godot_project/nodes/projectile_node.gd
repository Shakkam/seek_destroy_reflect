class_name ProjectileNode
extends Node2D

## Visual + damage-application placeholder for a fired shot — travels in a
## straight line (or gently homes, bazooka only), applies its damage to
## `target` on contact (a lightweight slice of Story 1.9's HP, see
## ship_state.gd note), and disappears. Rendered via placeholder R-Type
## sprites (2026-08-02) instead of a plain circle — see match_arena_node.gd
## for which textures are assigned per weapon/shooter.

var velocity: Vector2 = Vector2.ZERO
var lifetime: float = 2.0
var damage: int = 0
var target: ShipNode = null
var homing_strength: float = 0.0 # 0 = straight line; >0 = gently steers toward target (bazooka only)

var textures: Array = [] # of Texture2D — 1 = static sprite; 2+ = simple flicker/pulse animation
var flip_h := false # sprites face right by default; flipped for shots travelling left
var visual_scale := 1.0 # engine-side size bump, independent of the source art (2026-08-02 feedback)

var _sprite: Sprite2D
var _anim_timer := 0.0
var _anim_index := 0
const ANIM_FRAME_DURATION := 0.1

func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # keep pixel art crisp
	_sprite.flip_h = flip_h
	_sprite.scale = Vector2(visual_scale, visual_scale)
	add_child(_sprite)
	_update_sprite_texture()

func _physics_process(delta: float) -> void:
	if target and homing_strength > 0.0:
		# Only steer vertically — horizontal (left/right) speed stays constant.
		var desired_vy := clampf((target.position.y - position.y) * 2.0, -260.0, 260.0)
		velocity.y = lerpf(velocity.y, desired_vy, clampf(homing_strength * delta, 0.0, 1.0))

	position += velocity * delta
	lifetime -= delta

	if target:
		var target_rect := Rect2(target.position - target.half_extents, target.half_extents * 2.0)
		if target_rect.has_point(position):
			target.apply_damage(damage)
			queue_free()
			return

	if lifetime <= 0.0:
		queue_free()

	if textures.size() > 1:
		_anim_timer += delta
		if _anim_timer >= ANIM_FRAME_DURATION:
			_anim_timer = 0.0
			_anim_index = (_anim_index + 1) % textures.size()
			_update_sprite_texture()

func _update_sprite_texture() -> void:
	if textures.size() > 0 and _sprite:
		_sprite.texture = textures[_anim_index]
