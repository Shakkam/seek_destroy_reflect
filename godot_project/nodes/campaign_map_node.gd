class_name CampaignMapNode
extends Node2D

## Epic 4, Story 4.2/4.3 — the campaign map: one node per mini-branch for
## the character in CampaignContext.campaign (Soul Calibur IV branching-map
## reference, UX-DR1), plus the organizer node at the end of the path.
##
## 2026-08-11, second visual pass — Camil's drawing: "le joueur demarre de
## la case noire. Il choisit un chemin en allant sur l'un des premiers
## points verts (mini combat), puis enchaine un deuxieme point vert et un
## rond bleu (vrai combat rival + gain de l'arme si victoire). Puis il
## choisit encore un chemin... jusqu'au boss final." A REAL branching/
## converging tree — this supersedes both the original Story 4.3
## resolution ("fully free order between branches") and the first visual
## pass's hub/spoke layout (all branches equally available, all feeding
## the organizer independently). See MiniBranchData.prerequisite_ids for
## the unlock rule ("either path unlocks it", not "all paths required").
##
## Layout: a simple layered graph drawing (Sugiyama-style) — each branch's
## depth is 1 + the deepest of its prerequisites (0 if it has none, i.e. a
## root, available from "depart"); branches at the same depth share a
## column, evenly spaced vertically; the organizer sits one column past
## the deepest branch. No external art assets exist yet — same "engine-
## side shapes, no art needed" convention used throughout the weapon VFX —
## nodes are drawn circles/rings via _draw(), not imported textures.

@onready var title_label: Label = $TitleLabel
@onready var currency_label: Label = $CurrencyLabel
@onready var description_label: Label = $DescriptionLabel
@onready var hint_label: Label = $HintLabel
@onready var background: ColorRect = $Background

# Story 4.7 — the organizer's motif "bleeding" into the map as the player
# approaches the final node, environmental storytelling instead of a text
# announcement (2026-08-07 brainstorm, Constraint Injection). Matches the
# organizer's current stand-in character tint (Perturbateur, see
# data/campaigns/vif/organizer_encounter.tres — no dedicated organizer art yet).
const BASE_BG_COLOR := Color(0.07, 0.09, 0.15, 1.0)
const ORGANIZER_MOTIF_COLOR := Color(0.6, 0.8, 1.0, 1.0) # same pale-blue as the stun tint, echoes Perturbateur

const NODE_RADIUS := 40.0
const ORGANIZER_RADIUS := 58.0
const MARGIN_X := 130.0
const ROW_SPACING := 140.0
const PATH_Y_CENTER := 320.0
const COLOR_DONE := Color(0.35, 0.9, 0.55)
const COLOR_AVAILABLE := Color(0.55, 0.75, 1.0)
const COLOR_LOCKED := Color(0.35, 0.37, 0.45)
const COLOR_CHECKMARK := Color(0.05, 0.2, 0.12)

var _selected_index := 0
var _nodes: Array = [] # of MiniBranchData, authoring order (CampaignData.mini_branches) — navigation cycles this order; layout position comes from _depths instead
var _depths: Dictionary = {} # branch id (String) -> int, computed once in _ready()/whenever _nodes changes
var _move_prev := 0.0
# Seeded true, not false (2026-08-08 bug report: arriving here still holding
# the Fire button from the match that just ended instantly re-triggered
# _confirm_selection() on frame 1 — re-launching branch 0 before the map was
# ever visible, which read as "no map at all" + "always the same match").
# True means "was already pressed" so the first frame can never (mis)fire;
# it naturally settles once the button is actually released.
var _confirm_prev := true
var _cheat_prev := false # cheat menu hotkey (2026-08-09) — no carryover risk, "T" isn't shared with any other screen's confirm key
var _pulse_time := 0.0

func _ready() -> void:
	if not CampaignContext.campaign:
		# Reached directly (e.g. editor testing) without picking a campaign
		# first — bounce back rather than crash on a null campaign. Deferred:
		# changing scene synchronously from inside _ready() (still mid
		# scene-tree setup) errors ("Parent node is busy adding/removing
		# children"), caught via headless boot-check.
		get_tree().change_scene_to_file.call_deferred("res://scenes/CampaignCharacterSelect.tscn")
		return
	_nodes = CampaignContext.campaign.mini_branches.duplicate()
	_depths = _compute_depths()
	title_label.text = CampaignContext.campaign.character.display_name
	_refresh()

func _process(delta: float) -> void:
	if not CampaignContext.campaign:
		return # queue_free()'d but still processing this frame (e.g. CampaignContext.clear() ran right after) — _draw() reads campaign state, nothing left to safely draw/navigate
	_pulse_time += delta
	queue_redraw() # cheap for a handful of static circles + a pulsing ring or two

	var move := 0.0
	if Input.is_physical_key_pressed(KEY_DOWN):
		move += 1.0
	if Input.is_physical_key_pressed(KEY_UP):
		move -= 1.0
	var stick_y := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	if absf(stick_y) > 0.3:
		move = stick_y
	if absf(move) > 0.5 and absf(_move_prev) <= 0.5:
		var step := 1 if move > 0.0 else -1
		_selected_index = wrapi(_selected_index + step, 0, _nodes.size() + 1) # +1 for the organizer node
		_refresh()
	_move_prev = move

	var confirm := Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_ENTER) \
		or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.4
	if confirm and not _confirm_prev:
		_confirm_selection()
	_confirm_prev = confirm

	# Cheat menu (2026-08-09, Camil: "tu aurais un sous menu 'cheat' de la
	# campagne, pour que je puisse tester tous les twists ?") — dev/debug
	# entry point, physical "T" (Test), same "physical key" convention as
	# the rest of the project so it's unaffected by AZERTY/QWERTY labeling.
	if Input.is_physical_key_pressed(KEY_T) and not _cheat_prev:
		get_tree().change_scene_to_file("res://scenes/CampaignCheatMenu.tscn")
	_cheat_prev = Input.is_physical_key_pressed(KEY_T)

func _organizer_unlocked() -> bool:
	var character_id: String = CampaignContext.campaign.character.id
	return CampaignSave.completed_branch_count(character_id) >= CampaignContext.campaign.required_branch_count

func _find_branch(id: String) -> MiniBranchData:
	for branch in _nodes:
		if branch.id == id:
			return branch
	return null

## depth(node) = 1 + the DEEPEST of its prerequisites (0 if it has none —
## a root, available from "depart"). Using the deepest (not just "any")
## prerequisite guarantees a node always draws strictly to the right of
## every path that can unlock it, so edges never point backward even when
## multiple prerequisites sit at different depths. Memoized (cache) since
## the same prerequisite can be shared by several branches (a convergence).
func _compute_depths() -> Dictionary:
	var cache := {}
	for branch in _nodes:
		_compute_depth(branch, cache)
	return cache

func _compute_depth(branch: MiniBranchData, cache: Dictionary) -> int:
	if cache.has(branch.id):
		return cache[branch.id]
	cache[branch.id] = 0 # seeded before recursing: an authoring mistake that creates a cycle just bottoms out at 0 instead of infinite-recursing
	var depth := 0
	for prereq_id in branch.prerequisite_ids:
		var prereq := _find_branch(prereq_id)
		if prereq:
			depth = maxi(depth, _compute_depth(prereq, cache) + 1)
	cache[branch.id] = depth
	return depth

func _max_depth() -> int:
	var result := 0
	for branch in _nodes:
		result = maxi(result, _depths.get(branch.id, 0))
	return result

func _branches_at_depth(depth: int) -> Array:
	var result := []
	for branch in _nodes:
		if _depths.get(branch.id, 0) == depth:
			result.append(branch)
	return result

## A branch with nothing pointing at it as a prerequisite — the tree's
## "last step before the organizer" nodes, per the drawing (both final
## converged nodes feed into the boss).
func _is_leaf(branch: MiniBranchData) -> bool:
	for other in _nodes:
		if branch.id in other.prerequisite_ids:
			return false
	return true

func _column_x(depth: int) -> float:
	var columns := _max_depth() + 2 # branch depths 0..max_depth, plus one more column for the organizer
	var usable_width := 1280.0 - MARGIN_X * 2.0
	return MARGIN_X + usable_width * (float(depth) / float(maxi(columns - 1, 1)))

func _node_position(index: int) -> Vector2:
	if index == _nodes.size():
		return Vector2(_column_x(_max_depth() + 1), PATH_Y_CENTER)
	var branch: MiniBranchData = _nodes[index]
	var depth: int = _depths.get(branch.id, 0)
	var siblings := _branches_at_depth(depth)
	var row := siblings.find(branch)
	var y := PATH_Y_CENTER + (float(row) - float(siblings.size() - 1) / 2.0) * ROW_SPACING
	return Vector2(_column_x(depth), y)

func _refresh() -> void:
	var character_id: String = CampaignContext.campaign.character.id
	currency_label.text = "Gold: %d" % CampaignSave.get_currency(character_id)

	# Story 4.7 — the closer to unlocking the organizer, the more its motif
	# bleeds into the map's own background.
	var progress := float(CampaignSave.completed_branch_count(character_id)) / float(CampaignContext.campaign.required_branch_count)
	background.color = BASE_BG_COLOR.lerp(ORGANIZER_MOTIF_COLOR, clampf(progress, 0.0, 1.0) * 0.35)

	if _selected_index < _nodes.size():
		var branch: MiniBranchData = _nodes[_selected_index]
		match branch_node_status(_selected_index):
			"locked":
				var prereq_names := []
				for prereq_id in branch.prerequisite_ids:
					var prereq := _find_branch(prereq_id)
					if prereq:
						prereq_names.append(prereq.display_name)
				description_label.text = "%s : verrouille. Termine %s pour debloquer." % [branch.display_name, " ou ".join(prereq_names)]
			"done":
				description_label.text = "%s : deja terminee." % branch.display_name
			_:
				description_label.text = "Mini-branche : %s\n2 combats d'echauffement, puis le rival." % branch.display_name
	elif _organizer_unlocked():
		description_label.text = "Combat final contre l'organisateur du tournoi."
	else:
		description_label.text = "Complete %d mini-branches pour debloquer ce combat (%d/%d actuellement)." % [
			CampaignContext.campaign.required_branch_count,
			CampaignSave.completed_branch_count(character_id),
			CampaignContext.campaign.required_branch_count,
		]
	queue_redraw()

## Exposed for headless testing (campaign_setup_check.gd) — the old
## approach parsed the rendered list label's text ("[fait]" / cursor "> ");
## now that state is conveyed visually (node color/checkmark/lock icon),
## tests read this directly instead of scraping drawn output they can't
## screenshot headless. Three states now, not two — "locked" is new
## (2026-08-11 tree redesign; branches used to always be "available").
func branch_node_status(index: int) -> String:
	var character_id: String = CampaignContext.campaign.character.id
	var branch: MiniBranchData = _nodes[index]
	if CampaignSave.is_branch_completed(character_id, branch.id):
		return "done"
	return "available" if _branch_available(branch) else "locked"

func _branch_available(branch: MiniBranchData) -> bool:
	if branch.prerequisite_ids.is_empty():
		return true # a root — available from "depart"
	var character_id: String = CampaignContext.campaign.character.id
	for prereq_id in branch.prerequisite_ids:
		if CampaignSave.is_branch_completed(character_id, prereq_id):
			return true # EITHER path unlocks it — see MiniBranchData.prerequisite_ids
	return false

func _draw() -> void:
	if not CampaignContext.campaign:
		return # a queue_redraw() from an earlier frame can still fire _draw() once after CampaignContext.campaign goes null (e.g. cleared right after queue_free()) — the _process() guard alone isn't enough, redraws aren't synchronous with it

	# Edges: each branch to its own prerequisite(s) (parent -> child), plus
	# every leaf branch (nothing depends on it) straight to the organizer —
	# exactly the shape in Camil's drawing, generalized to however deep/wide
	# the authored tree actually is.
	for i in _nodes.size():
		var branch: MiniBranchData = _nodes[i]
		for prereq_id in branch.prerequisite_ids:
			var prereq := _find_branch(prereq_id)
			if not prereq:
				continue
			var prereq_index := _nodes.find(prereq)
			var lit := branch_node_status(prereq_index) == "done"
			draw_line(_node_position(prereq_index), _node_position(i), COLOR_DONE if lit else COLOR_LOCKED, 3.0)
		if _is_leaf(branch):
			var lit_leaf := branch_node_status(i) == "done"
			draw_line(_node_position(i), _node_position(_nodes.size()), COLOR_DONE if lit_leaf else COLOR_LOCKED, 3.0)

	for i in _nodes.size():
		_draw_branch_node(i)
	_draw_organizer_node()

func _draw_branch_node(i: int) -> void:
	var center := _node_position(i)
	var branch: MiniBranchData = _nodes[i]
	var status := branch_node_status(i)
	match status:
		"done":
			draw_circle(center, NODE_RADIUS, COLOR_DONE)
			# A simple drawn checkmark — no icon assets needed.
			draw_line(center + Vector2(-15, 2), center + Vector2(-4, 15), COLOR_CHECKMARK, 5.0)
			draw_line(center + Vector2(-4, 15), center + Vector2(17, -13), COLOR_CHECKMARK, 5.0)
		"available":
			draw_circle(center, NODE_RADIUS, Color(COLOR_AVAILABLE.r, COLOR_AVAILABLE.g, COLOR_AVAILABLE.b, 0.12))
			draw_arc(center, NODE_RADIUS, 0.0, TAU, 48, COLOR_AVAILABLE, 4.0)
		_: # "locked"
			draw_circle(center, NODE_RADIUS, Color(COLOR_LOCKED.r, COLOR_LOCKED.g, COLOR_LOCKED.b, 0.18))
			draw_arc(center, NODE_RADIUS, 0.0, TAU, 48, COLOR_LOCKED, 3.0)
			_draw_lock_icon(center) # silhouette-in-fog substitute — no dedicated art yet
	_draw_selection_ring(center, NODE_RADIUS, i == _selected_index)
	_draw_label(branch.display_name, center, NODE_RADIUS)

func _draw_organizer_node() -> void:
	var index := _nodes.size()
	var center := _node_position(index)
	var unlocked := _organizer_unlocked()
	var base_color := ORGANIZER_MOTIF_COLOR if unlocked else COLOR_LOCKED
	draw_circle(center, ORGANIZER_RADIUS, Color(base_color.r, base_color.g, base_color.b, 0.2 if unlocked else 0.3))
	var ring_radius := ORGANIZER_RADIUS
	if unlocked:
		# Pulses continuously once available, not just when selected — reads
		# as "the boss is ready" from anywhere on the map, matching the
		# background motif bleed-in above.
		ring_radius += sin(_pulse_time * 3.0) * 5.0
	draw_arc(center, ring_radius, 0.0, TAU, 56, base_color, 5.0)
	if not unlocked:
		_draw_lock_icon(center)
	_draw_selection_ring(center, ORGANIZER_RADIUS, index == _selected_index)
	_draw_label("Organisateur", center, ORGANIZER_RADIUS)

func _draw_lock_icon(center: Vector2) -> void:
	draw_rect(Rect2(center + Vector2(-10, -2), Vector2(20, 16)), Color(0.7, 0.72, 0.8), true)
	draw_arc(center + Vector2(0, -6), 8.0, PI, TAU, 16, Color(0.7, 0.72, 0.8), 3.0)

func _draw_selection_ring(center: Vector2, radius: float, is_selected: bool) -> void:
	if not is_selected:
		return
	var pulse_radius := radius + 10.0 + sin(_pulse_time * 4.0) * 4.0
	draw_arc(center, pulse_radius, 0.0, TAU, 48, Color(1, 1, 1, 0.8), 3.0)

func _draw_label(text: String, center: Vector2, radius: float) -> void:
	var font := ThemeDB.fallback_font
	var font_size := 16
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(font, center + Vector2(-text_size.x / 2.0, radius + 22.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.9, 0.91, 0.97))

func _confirm_selection() -> void:
	var character_id: String = CampaignContext.campaign.character.id
	if _selected_index < _nodes.size():
		var branch: MiniBranchData = _nodes[_selected_index]
		var status := branch_node_status(_selected_index)
		if status != "available":
			return # already done, or still locked behind a prerequisite — nothing to start
		CampaignContext.start_branch(CampaignContext.campaign, branch)
		get_tree().change_scene_to_file("res://scenes/MiniBranchMap.tscn") # visible per-branch progress (2026-08-08 UX request) instead of jumping straight into a fight
	elif _organizer_unlocked():
		CampaignContext.start_organizer_fight(CampaignContext.campaign)
		get_tree().change_scene_to_file("res://scenes/MatchArena.tscn")
