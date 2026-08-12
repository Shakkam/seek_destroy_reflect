class_name SelectScreenBackground
extends Node2D

## Character-select screen backdrop — engine-drawn (no external art asset,
## same "_draw() shapes" convention as CampaignMapNode: nodes/campaign_map_node.gd),
## matching the "wacky vibrant arcade" Air Zonk art-direction brief in the
## GDD ("Fond de l'ecran de selection de personnage" — deep purple into hot
## pink into orange, radiating diagonal energy lines, scattered sparkles, a
## faint glowing abstract arena silhouette in the distance). Sits behind
## CharacterSelect's panels/labels; kept sparse in the center so player
## portraits (added on top later, per Camil: "je remplirai avec les
## images") stay readable — same "not too busy in the foreground" brief
## used for the Gemini prompt version of this background.

const VIEWPORT_SIZE := Vector2(1280.0, 720.0)
const SUNBURST_ORIGIN := Vector2(640.0, 260.0) # above screen center, roughly where the title sits

const COLOR_TOP := Color(0.16, 0.06, 0.28, 1.0) # deep purple
const COLOR_MID := Color(0.55, 0.1, 0.45, 1.0) # hot pink
const COLOR_BOTTOM := Color(0.85, 0.35, 0.08, 1.0) # orange
const GRADIENT_STRIPS := 48 # thin horizontal bands -> smooth-looking gradient with no shader/imported texture

const RAY_COUNT := 16 # half of these actually draw (see _draw_sunburst) — density vs. "not too busy"
const RAY_LENGTH := 900.0
const RAY_ROTATION_SPEED := 0.08 # slow drift, reads as "energy" without being distracting
const RAY_COLOR := Color(1.0, 0.9, 0.6, 0.05)

const STAR_COUNT := 40
const STAR_SEED := 20260812 # fixed seed -> stable layout every run, not re-randomized on each launch

const ARENA_CENTER_Y_FRACTION := 0.62
const ARENA_RADIUS := 260.0

var _time := 0.0
var _stars: Array = [] # Array of {pos: Vector2, phase: float, size: float}

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = STAR_SEED
	for i in STAR_COUNT:
		_stars.append({
			"pos": Vector2(rng.randf_range(0.0, VIEWPORT_SIZE.x), rng.randf_range(0.0, VIEWPORT_SIZE.y)),
			"phase": rng.randf_range(0.0, TAU),
			"size": rng.randf_range(1.5, 3.5),
		})

func _process(delta: float) -> void:
	_time += delta
	queue_redraw() # cheap: a gradient of flat rects + a couple dozen circles/triangles

func _draw() -> void:
	_draw_gradient()
	_draw_arena_silhouette()
	_draw_sunburst()
	_draw_stars()

func _draw_gradient() -> void:
	var strip_height := VIEWPORT_SIZE.y / float(GRADIENT_STRIPS)
	for i in GRADIENT_STRIPS:
		var t := float(i) / float(GRADIENT_STRIPS - 1)
		var color: Color
		if t < 0.5:
			color = COLOR_TOP.lerp(COLOR_MID, t / 0.5)
		else:
			color = COLOR_MID.lerp(COLOR_BOTTOM, (t - 0.5) / 0.5)
		draw_rect(Rect2(0.0, strip_height * i, VIEWPORT_SIZE.x, strip_height + 1.0), color, true) # +1px overlap so seams don't show

func _draw_sunburst() -> void:
	for i in RAY_COUNT:
		if i % 2 == 0:
			continue # every other ray only — half density keeps the center readable
		var angle := (TAU / RAY_COUNT) * i + _time * RAY_ROTATION_SPEED
		var dir := Vector2(cos(angle), sin(angle))
		var perp := dir.orthogonal()
		var far_point := SUNBURST_ORIGIN + dir * RAY_LENGTH
		var half_width := RAY_LENGTH * 0.05
		var triangle := PackedVector2Array([
			SUNBURST_ORIGIN,
			far_point + perp * half_width,
			far_point - perp * half_width,
		])
		draw_colored_polygon(triangle, RAY_COLOR)

func _draw_arena_silhouette() -> void:
	# A faint glowing abstract arena shape far in the distance (GDD brief) —
	# a stylized double ring, not a literal building, sitting low so it
	# reads as "far away" behind the panels/portraits.
	var arena_center := Vector2(SUNBURST_ORIGIN.x, VIEWPORT_SIZE.y * ARENA_CENTER_Y_FRACTION)
	draw_arc(arena_center, ARENA_RADIUS, PI * 1.05, PI * 1.95, 48, Color(1.0, 0.85, 0.5, 0.10), 6.0)
	draw_arc(arena_center, ARENA_RADIUS * 0.85, PI * 1.1, PI * 1.9, 40, Color(1.0, 0.6, 0.8, 0.08), 4.0)

func _draw_stars() -> void:
	for star in _stars:
		var twinkle := 0.5 + 0.5 * sin(_time * 2.0 + star["phase"])
		draw_circle(star["pos"], star["size"], Color(1.0, 1.0, 0.95, 0.3 + 0.5 * twinkle))
