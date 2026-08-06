extends Node

## Autoload singleton — carries each player's chosen CharacterData from
## CharacterSelect.tscn to MatchArena.tscn (Story 2.3). Godot has no built-in
## way to pass data across a change_scene_to_file() call, so this is the
## thin persistent bridge between the two scenes; it holds no gameplay logic
## of its own (see project-context.md, Regle absolue n1 — this is orchestration,
## not simulation).

var p1_character: CharacterData
var p2_character: CharacterData
