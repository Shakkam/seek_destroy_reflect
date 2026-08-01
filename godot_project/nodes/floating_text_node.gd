class_name FloatingTextNode
extends Node2D

## Purely visual feedback: a number that rises and fades out. Used for
## gauge-fill popups so gains are readable during testing — echoes the
## GDD's "+100%" trick-shot popup idea, ahead of the real diegetic HUD (1.10).

var text: String = ""
var color: Color = Color(1.0, 0.84, 0.29, 1.0)
var velocity: Vector2 = Vector2(0.0, -42.0)
var lifetime: float = 0.9
var _age: float = 0.0

func _physics_process(delta: float) -> void:
	position += velocity * delta
	_age += delta
	if _age >= lifetime:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var alpha := clampf(1.0 - _age / lifetime, 0.0, 1.0)
	var draw_color := color
	draw_color.a = alpha
	var font := ThemeDB.fallback_font
	var font_size := 18
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(font, Vector2(-text_size.x / 2.0, 0.0), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, draw_color)
