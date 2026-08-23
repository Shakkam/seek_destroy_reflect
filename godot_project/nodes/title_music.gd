extends Node

## Title theme music, promoted to an autoload (2026-08-18, Camil: "faudrait
## que la musique d'intro demarre vraiment au temps 0, et aussi qu'elle
## continue sur l'ecran de selection de personnages"). An AudioStreamPlayer
## that lived as a plain child of TitleScreenNode got destroyed — and the
## music cut dead — the instant change_scene_to_file() swapped the scene
## tree for CharacterSelect/CampaignCharacterSelect. Autoloads sit under
## the SceneTree root, outside whatever scene is "current", so they survive
## scene changes for free — the standard Godot pattern for music that needs
## to persist across screens.
##
## start() is safe to call every time TitleScreenNode._ready() runs (fresh
## launch, or navigating back to the title) — always (re)starts from 0.
## stop() is called by whichever screen finally leaves the title->
## character-select flow for real gameplay (TitleScreenNode's "Continuer la
## partie" -> CampaignMap directly, CampaignCharacterSelectNode ->
## CampaignMap, CharacterSelectNode -> MatchArena) so it doesn't bleed into
## a match's own audio.

signal looped # emitted every time playback (re)starts from 0 — the initial
# start() AND every subsequent loop-back (plain .wav has no built-in loop
# toggle, see _replay()) — so a listener (TitleScreenNode's word-drop
# entrance) can replay its own "track started" animation without owning a
# second copy of the AudioStreamPlayer itself.

const THEME_STREAM := preload("res://assets/audio/music/title_theme.wav")

var _player: AudioStreamPlayer

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.stream = THEME_STREAM
	_player.finished.connect(_replay)
	add_child(_player)

func start() -> void:
	_replay()

func stop() -> void:
	if _player.playing:
		_player.stop()

func _replay() -> void:
	_player.play()
	looped.emit()
