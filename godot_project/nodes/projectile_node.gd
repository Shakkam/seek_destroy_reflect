class_name ProjectileNode
extends Node2D

## Visual + damage-application placeholder for a fired shot — travels in a
## straight line, applies its damage to `target` on contact (a lightweight
## slice of Story 1.9's HP, see ship_state.gd note), and disappears.

var velocity: Vector2 = Vector2.ZERO
var color: Color = Color(1.0, 0.9, 0.3, 1.0)
var radius: float = 4.0 # heavy weapons (bazooka) use a larger radius to read as "fatter" shots
var lifetime: float = 2.0
var damage: int = 0
var target: ShipNode = null
var homing_strength: float = 0.0 # 0 = straight line; >0 = gently steers toward target (bazooka only)

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
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color)
