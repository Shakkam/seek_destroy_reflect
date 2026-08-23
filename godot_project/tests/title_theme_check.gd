extends Node2D

## One-off scene-boot verification for the 2026-08-16 title-screen theme
## (Camil, sharing "1.wav": "on y entend distinctement les 2 mots 'Seek
## and Destroy and Return the ball'. Ce serait bien que les mots arrivent
## petit a petit en meme temps [que la voix], en arrivant du haut, facon
## Street Fighter 2" — then, listening to the real track: "Seek => 2.5s,
## and destroy 3.5s, and return the ball 4.5s"). Confirms: (1) the theme
## actually starts playing on load, (2) "SEEK" and "AND DESTROY" together
## read as one centered line (no gap/overlap beyond the deliberate word
## gap) despite being two independent Labels now, (3) all three pieces
## start off-screen above their resting spot, (4) each lands at its OWN
## real timestamp, not early. Run with:
##   Godot --headless --path godot_project res://tests/title_theme_check.tscn --quit-after 8000

func _ready() -> void:
	var scene := load("res://scenes/TitleScreen.tscn") as PackedScene
	var title := scene.instantiate() as TitleScreenNode
	add_child(title)
	await get_tree().process_frame

	var playing_ok: bool = title.theme_music.playing
	print("PASS: the theme starts playing on load" if playing_ok else "FAIL: the theme never started playing")

	# "SEEK" ends exactly TITLE_WORD_GAP before "AND DESTROY" begins, and
	# the pair sits centered on the 1280-wide screen.
	var seek_right: float = title.title_word_seek.position.x + title.title_word_seek.size.x
	var gap_ok: bool = is_equal_approx(title.title_word_and_destroy.position.x - seek_right, TitleScreenNode.TITLE_WORD_GAP)
	print(("PASS: 'SEEK' and 'AND DESTROY' sit exactly one word-gap apart (%.1fpx)" % (title.title_word_and_destroy.position.x - seek_right)) if gap_ok else ("FAIL: the gap between the two words was wrong (%.1fpx, expected %.1f)" % [title.title_word_and_destroy.position.x - seek_right, TitleScreenNode.TITLE_WORD_GAP]))
	var total_width: float = title.title_word_and_destroy.position.x + title.title_word_and_destroy.size.x - title.title_word_seek.position.x
	var centered_ok: bool = is_equal_approx(title.title_word_seek.position.x, (1280.0 - total_width) / 2.0)
	print("PASS: the combined 'SEEK AND DESTROY' line is centered on screen" if centered_ok else "FAIL: the combined line isn't centered")

	var seek_offscreen_ok: bool = title.title_word_seek.position.y < title._title_seek_rest_y
	var and_destroy_offscreen_ok: bool = title.title_word_and_destroy.position.y < title._title_and_destroy_rest_y
	var bottom_offscreen_ok: bool = title.title_bottom.position.y < title._title_bottom_rest_y
	print("PASS: 'SEEK' starts off-screen, above its resting spot" if seek_offscreen_ok else "FAIL: 'SEEK' didn't start off-screen")
	print("PASS: 'AND DESTROY' starts off-screen too" if and_destroy_offscreen_ok else "FAIL: 'AND DESTROY' didn't start off-screen")
	print("PASS: 'AND RETURN THE BALL' starts off-screen too" if bottom_offscreen_ok else "FAIL: the bottom line didn't start off-screen")

	# 2026-08-16 playtest: "on voit les textes tout en haut. Il faut les
	# planquer" — the old relative "260px above ITS OWN rest_y" start left
	# the top row's rendered bottom edge (accounting for the 2x start
	# scale, centered pivot) poking a bit into frame. Compute the actual
	# rendered bottom edge the same way the engine does and confirm it
	# sits at/above y=0 (the screen's own top edge) — not just "somewhere
	# above rest_y".
	var seek_scale_ok: bool = title.title_word_seek.scale == Vector2(TitleScreenNode.TITLE_START_SCALE, TitleScreenNode.TITLE_START_SCALE)
	print("PASS: 'SEEK' starts at the bigger TITLE_START_SCALE (falling from far away)" if seek_scale_ok else ("FAIL: 'SEEK' didn't start at TITLE_START_SCALE (scale=%s)" % title.title_word_seek.scale))
	var seek_size := title.title_word_seek.size
	var seek_rendered_bottom: float = title.title_word_seek.position.y + seek_size.y * 0.5 * (1.0 + title.title_word_seek.scale.y)
	var seek_fully_hidden_ok: bool = seek_rendered_bottom <= 0.0
	print(("PASS: 'SEEK' is FULLY off-screen at start, not just poking above rest_y (rendered bottom edge at %.1f)" % seek_rendered_bottom) if seek_fully_hidden_ok else ("FAIL: 'SEEK' is still partly visible at start (rendered bottom edge at %.1f, screen top is 0)" % seek_rendered_bottom))

	await get_tree().create_timer(TitleScreenNode.TITLE_SEEK_DROP_TIME + TitleScreenNode.TITLE_DROP_DURATION + 0.1).timeout
	# Position is fully settled the instant the drop tween finishes, but
	# scale ISN'T — _impact_squash() immediately kicks off a SEPARATE,
	# longer squash-and-recover on scale right as position lands, so
	# scale is deliberately still mid-recovery here, not back at 1.0 yet.
	var seek_landed_ok: bool = is_equal_approx(title.title_word_seek.position.y, title._title_seek_rest_y)
	print("PASS: 'SEEK' has landed at 2.5s" if seek_landed_ok else ("FAIL: 'SEEK' hasn't landed (y=%.2f, expected %.2f)" % [title.title_word_seek.position.y, title._title_seek_rest_y]))
	var seek_mid_squash_ok: bool = not title.title_word_seek.scale.is_equal_approx(Vector2.ONE)
	print("PASS: the impact squash is genuinely mid-recovery right as it lands (not an instant snap)" if seek_mid_squash_ok else "FAIL: scale was already back to normal the instant it landed — the squash beat isn't happening")

	var and_destroy_still_waiting_ok: bool = title.title_word_and_destroy.position.y < title._title_and_destroy_rest_y
	print("PASS: 'AND DESTROY' is still off-screen at 2.5s (hasn't jumped the gun)" if and_destroy_still_waiting_ok else "FAIL: 'AND DESTROY' already landed too early")

	await get_tree().create_timer(TitleScreenNode.TITLE_AND_DESTROY_DROP_TIME - TitleScreenNode.TITLE_SEEK_DROP_TIME + TitleScreenNode.TITLE_DROP_DURATION + 0.1).timeout
	var and_destroy_landed_ok: bool = is_equal_approx(title.title_word_and_destroy.position.y, title._title_and_destroy_rest_y)
	print("PASS: 'AND DESTROY' has landed at 3.5s" if and_destroy_landed_ok else ("FAIL: 'AND DESTROY' hasn't landed (%.2f, expected %.2f)" % [title.title_word_and_destroy.position.y, title._title_and_destroy_rest_y]))
	var bottom_still_waiting_ok: bool = title.title_bottom.position.y < title._title_bottom_rest_y
	print("PASS: the bottom line is still off-screen at 3.5s (hasn't jumped the gun)" if bottom_still_waiting_ok else "FAIL: the bottom line already landed too early")

	await get_tree().create_timer(TitleScreenNode.TITLE_BOTTOM_DROP_TIME - TitleScreenNode.TITLE_AND_DESTROY_DROP_TIME + TitleScreenNode.TITLE_DROP_DURATION + 0.1).timeout
	var bottom_landed_ok: bool = is_equal_approx(title.title_bottom.position.y, title._title_bottom_rest_y)
	print("PASS: 'AND RETURN THE BALL' has landed at 4.5s" if bottom_landed_ok else ("FAIL: the bottom line hasn't landed (%.2f, expected %.2f)" % [title.title_bottom.position.y, title._title_bottom_rest_y]))

	var all_ok := playing_ok and gap_ok and centered_ok \
		and seek_offscreen_ok and and_destroy_offscreen_ok and bottom_offscreen_ok \
		and seek_scale_ok and seek_fully_hidden_ok \
		and seek_landed_ok and seek_mid_squash_ok and and_destroy_still_waiting_ok \
		and and_destroy_landed_ok and bottom_still_waiting_ok \
		and bottom_landed_ok
	get_tree().quit(0 if all_ok else 1)
