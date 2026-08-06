class_name TitleScreenNode
extends Node2D

## Front door of the game (2026-08-06 — prepping a build to show on a
## friend's portal, the game previously booted straight into character
## select with no title/branding at all). Purely presentational: no
## gameplay state, just waits for a confirm press then hands off to
## CharacterSelect — same input scheme as the pre-match "ready?" gate in
## MatchArenaNode, for consistency.

func _process(_delta: float) -> void:
	var pressed := Input.is_physical_key_pressed(KEY_SPACE) \
		or Input.is_physical_key_pressed(KEY_ENTER) \
		or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.4 \
		or Input.get_joy_axis(1, JOY_AXIS_TRIGGER_RIGHT) > 0.4
	if pressed:
		get_tree().change_scene_to_file("res://scenes/CharacterSelect.tscn")
