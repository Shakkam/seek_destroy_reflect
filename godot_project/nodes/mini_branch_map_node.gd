class_name MiniBranchMapNode
extends Node2D

## Epic 4 — visible per-branch progress map (2026-08-08 UX request, Camil:
## "il est temps de faire une mini map ... petit carré match, flèche, petit
## carré match, flèche, petit carré match contre le vrai 'joueur' avec le
## twist"). Shown before the branch's first fight and again between each
## fight, instead of silently reloading straight into the next one.
##
## 2026-08-11 visual pass ("la carte illustree / branches"): the original
## version was mechanically correct but rendered its state as bracketed text
## ("[X]" / ">>...<<" / "[ ]") — replaced with an actual drawn path, three
## node markers connected by a line, state conveyed by color/shape instead.
## No external art assets exist yet — same "engine-side shapes, no art
## needed" convention used throughout the weapon VFX (turrets, projectiles)
## — nodes are drawn circles/rings via _draw(), not imported textures.
## MiniBranchData.preview_texture (unused everywhere today) is where real
## per-branch art would plug in later without touching this layout.
##
## No backtracking: CampaignContext.branch_step only ever increases
## (advance_branch_step()), so there's nothing to navigate here — the
## player just confirms to fight whichever step is next.

@onready var title_label: Label = $TitleLabel
@onready var node1_name_label: Label = $Node1Name
@onready var node2_name_label: Label = $Node2Name
@onready var node3_name_label: Label = $Node3Name
@onready var hint_label: Label = $HintLabel

const NODE_RADIUS := 42.0
const NODE_POSITIONS := [Vector2(260, 360), Vector2(640, 360), Vector2(1020, 360)]
const COLOR_DONE := Color(0.35, 0.9, 0.55)
const COLOR_CURRENT := Color(1.0, 0.84, 0.29)
const COLOR_UPCOMING := Color(0.4, 0.42, 0.52)
const COLOR_RIVAL_ACCENT := Color(1.0, 0.55, 0.7) # matches Node3's old font_color — the "real" fight of the branch reads as distinct even before reached
const COLOR_CHECKMARK := Color(0.05, 0.15, 0.1)

var _confirm_prev := true # seeded true — same carryover guard as CampaignMapNode (2026-08-08 bug)
var _pulse_time := 0.0

func _ready() -> void:
	if not CampaignContext.branch:
		# Reached without a branch chosen first (e.g. editor testing) —
		# bounce back rather than crash. Deferred: see CampaignMapNode's
		# note on why a synchronous change_scene_to_file() from _ready()
		# errors ("Parent node is busy adding/removing children").
		get_tree().change_scene_to_file.call_deferred("res://scenes/CampaignMap.tscn")
		return
	title_label.text = CampaignContext.branch.display_name
	_refresh()

func _process(delta: float) -> void:
	_pulse_time += delta
	queue_redraw() # the current node's ring pulses — cheap to redraw every frame for 3 static circles + a line

	var confirm := Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_ENTER) \
		or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.4
	if confirm and not _confirm_prev:
		get_tree().change_scene_to_file("res://scenes/MatchArena.tscn")
	_confirm_prev = confirm

func _refresh() -> void:
	node1_name_label.text = "Sous-adversaire 1"
	node2_name_label.text = "Sous-adversaire 2"
	var rival_text := "Rival"
	if CampaignContext.branch.rival.twist:
		rival_text += "\n(%s)" % CampaignContext.branch.rival.twist.display_name
	node3_name_label.text = rival_text
	hint_label.text = "Espace/Entree : combattre" if CampaignContext.branch_step < 3 else ""
	queue_redraw()

## Exposed for headless testing (campaign_setup_check.gd) — the old
## approach parsed rendered label text ("[X]" / ">>" / "[ ]"); now that
## state is conveyed visually (node color/ring/checkmark), tests read this
## directly instead of scraping drawn output they can't screenshot headless.
func node_status(index: int) -> String:
	var step := CampaignContext.branch_step
	if index < step:
		return "done"
	elif index == step:
		return "current"
	else:
		return "upcoming"

func _draw() -> void:
	# Connecting path first, so the node circles draw on top of the line ends.
	for i in 2:
		var lit := node_status(i) == "done"
		draw_line(NODE_POSITIONS[i], NODE_POSITIONS[i + 1], COLOR_DONE if lit else COLOR_UPCOMING, 4.0)
	for i in 3:
		_draw_node(i)

func _draw_node(i: int) -> void:
	var center: Vector2 = NODE_POSITIONS[i]
	var status := node_status(i)
	var is_rival := i == 2
	var ring_color: Color
	match status:
		"done":
			ring_color = COLOR_DONE
		"current":
			ring_color = COLOR_CURRENT
		_:
			ring_color = COLOR_RIVAL_ACCENT if is_rival else COLOR_UPCOMING

	if status == "done":
		draw_circle(center, NODE_RADIUS, ring_color)
		# A simple drawn checkmark — no icon assets needed.
		draw_line(center + Vector2(-16, 2), center + Vector2(-4, 16), COLOR_CHECKMARK, 5.0)
		draw_line(center + Vector2(-4, 16), center + Vector2(18, -14), COLOR_CHECKMARK, 5.0)
	else:
		draw_circle(center, NODE_RADIUS, Color(ring_color.r, ring_color.g, ring_color.b, 0.12))
		draw_arc(center, NODE_RADIUS, 0.0, TAU, 48, ring_color, 4.0)

	if status == "current":
		# "You're about to fight this one" — a pulsing white ring, distinct
		# from the static state rings above.
		var pulse_radius := NODE_RADIUS + 6.0 + sin(_pulse_time * 4.0) * 4.0
		draw_arc(center, pulse_radius, 0.0, TAU, 48, Color(1, 1, 1, 0.7), 3.0)
