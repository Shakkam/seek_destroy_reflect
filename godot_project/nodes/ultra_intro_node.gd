class_name UltraIntroNode
extends Node2D

## "Systeme des 5 balles" ultra-trigger intro beat (2026-08-14, Camil):
## "quand un ultra se declenche, le jeu se met en pause. une barre
## blanche et le mot 'ultra' arrivent de la droite, le perso en -image
## arrive de la gauche. animation 1/3 seconde, reste statique 1 seconde,
## puis la barre blanche et le 'ULTRA' sortent vers la gauche et le perso
## vers la droite (1/3 seconde), le jeu se de-freeze et l'ULTRA se
## lance." MatchArenaNode freezes ships/ball, adds this as a child of
## DebugHUD (drawn on top of the HP bars/labels too — this is meant to
## cover the whole screen for a moment), awaits `finished`, unfreezes,
## THEN actually resolves the ultra's damage/projectiles — the intro
## isn't just decoration playing over the attack, it gates it.
##
## Reuses the same per-character full-body art as CharacterSelect
## (nodes/character_select_node.gd's FULL_TEXTURES/ACCENT_COLORS) —
## duplicated here rather than shared, matching this project's existing
## "explicit preload + id lookup per node" convention (see
## match_arena_node.gd's own weapon-sprite consts, or CharacterSelect's
## own copy of the same idea).

signal finished

const SLIDE_DURATION := 1.0 / 3.0
const HOLD_DURATION := 1.0

const VIEWPORT_SIZE := Vector2(1280.0, 720.0)
const BAR_Y := 250.0
const BAR_HEIGHT := 180.0
const IMAGE_SIZE := Vector2(280.0, 420.0) # ~2:3, matches the GDD's "grande image" ratio, scaled up for impact
const IMAGE_REST_CENTER := Vector2(300.0, 340.0) # left-of-center, vertically inside the bar's band

const FULL_TEXTURES := {
	"lourd": preload("res://assets/art/characters/lourd/full.png"),
	"missiles": preload("res://assets/art/characters/missiles/full.png"), # Traqueur
	"controleur": preload("res://assets/art/characters/controleur/full.png"),
	"mitrailleur": preload("res://assets/art/characters/mitrailleur/full.png"),
	"zoneur": preload("res://assets/art/characters/zoneur/full.png"),
	"perturbateur": preload("res://assets/art/characters/perturbateur/full.png"),
	"mini": preload("res://assets/art/characters/mini/full.png"), # Spreader
	"vif": preload("res://assets/art/characters/vif/full.png"),
}
const ACCENT_COLORS := {
	"lourd": Color(0.85, 0.4, 0.15),
	"controleur": Color(0.6, 0.63, 0.68),
	"mitrailleur": Color(0.65, 0.78, 0.88),
	"vif": Color(0.15, 0.55, 1.0),
	"zoneur": Color(0.25, 0.9, 0.45),
	"perturbateur": Color(0.6, 0.5, 0.9),
	"missiles": Color(0.2, 0.85, 0.9), # Traqueur
	"mini": Color(1.0, 0.85, 0.2), # Spreader
}

enum Phase { SLIDE_IN, HOLD, SLIDE_OUT }
var phase := Phase.SLIDE_IN
var _phase_timer := SLIDE_DURATION
var character: CharacterData

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # keep the pixel-art character image crisp when scaled, same convention as CharacterSelectNode

func _process(delta: float) -> void:
	_phase_timer -= delta
	if _phase_timer <= 0.0:
		match phase:
			Phase.SLIDE_IN:
				phase = Phase.HOLD
				_phase_timer = HOLD_DURATION
			Phase.HOLD:
				phase = Phase.SLIDE_OUT
				_phase_timer = SLIDE_DURATION
			Phase.SLIDE_OUT:
				finished.emit()
				return # the parent frees this node right after — nothing left to draw
	queue_redraw()

func _draw() -> void:
	_draw_bar()
	_draw_character() # drawn after/on top of the bar, not hidden behind it

## Fraction of the SLIDE phase elapsed, 0.0 (just started) -> 1.0 (fully
## slid). Shared by both the bar and the character, each applying it to
## their own distinct off-screen start/end points per phase.
func _slide_t() -> float:
	return 1.0 - clampf(_phase_timer / SLIDE_DURATION, 0.0, 1.0)

func _bar_left_x() -> float:
	match phase:
		Phase.SLIDE_IN:
			return lerpf(VIEWPORT_SIZE.x, 0.0, _slide_t()) # arrives from the right
		Phase.SLIDE_OUT:
			return lerpf(0.0, -VIEWPORT_SIZE.x, _slide_t()) # exits to the left
		_: # HOLD
			return 0.0

func _character_left_x() -> float:
	var rest_x := IMAGE_REST_CENTER.x - IMAGE_SIZE.x / 2.0
	match phase:
		Phase.SLIDE_IN:
			return lerpf(-IMAGE_SIZE.x, rest_x, _slide_t()) # arrives from the left
		Phase.SLIDE_OUT:
			return lerpf(rest_x, VIEWPORT_SIZE.x, _slide_t()) # exits to the right
		_: # HOLD
			return rest_x

func _draw_bar() -> void:
	var rect := Rect2(_bar_left_x(), BAR_Y, VIEWPORT_SIZE.x, BAR_HEIGHT)
	draw_rect(rect, Color(1, 1, 1, 1), true)
	draw_rect(rect, Color(0.05, 0.05, 0.08, 1), false, 5.0)
	var font := ThemeDB.fallback_font
	var text := "ULTRA"
	var font_size := 72
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := rect.position + rect.size / 2.0 - Vector2(text_size.x / 2.0, -text_size.y * 0.35)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.08, 0.08, 0.1, 1))

func _draw_character() -> void:
	if not character:
		return
	var texture: Texture2D = FULL_TEXTURES.get(character.id)
	if not texture:
		return
	var rect := Rect2(Vector2(_character_left_x(), IMAGE_REST_CENTER.y - IMAGE_SIZE.y / 2.0), IMAGE_SIZE)
	var accent: Color = ACCENT_COLORS.get(character.id, Color.WHITE)
	draw_rect(rect.grow(6.0), accent, false, 6.0) # a simple accent-colored frame — no dedicated intro-specific art needed
	draw_texture_rect(texture, rect, false)
