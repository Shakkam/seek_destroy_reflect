extends Node

## Epic 4, Story 4.9 — local JSON save for campaign progress. Autoload
## (parallel to MatchSetup) so both the campaign map (Story 4.2/4.3) and the
## match-flow code (Story 4.4/4.6/4.8) can read/write it. Orchestration, not
## simulation — lives in nodes/, never referenced from simulation/ (Regle
## absolue n1). No cloud save in V1 (project-context.md, Additional
## Requirements).

const SAVE_PATH := "user://campaign_save.json"

## character_id -> {"currency": int, "completed_branches": [String, ...],
## "unlocks": [String, ...], "organizer_defeated": bool}
var _data: Dictionary = {}

func _ready() -> void:
	load_from_disk()

func load_from_disk() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_data = {}
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var content := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(content)
	_data = parsed if parsed is Dictionary else {}

func save_to_disk() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(_data))
	file.close()

func _character_entry(character_id: String) -> Dictionary:
	if not _data.has(character_id):
		_data[character_id] = {"currency": 0, "completed_branches": [], "unlocks": [], "organizer_defeated": false}
	return _data[character_id]

func get_currency(character_id: String) -> int:
	return _character_entry(character_id).get("currency", 0)

## Story 4.4 — mook victories grant Exp/Gold.
func add_currency(character_id: String, amount: int) -> void:
	var entry := _character_entry(character_id)
	entry["currency"] = int(entry.get("currency", 0)) + amount
	save_to_disk()

func is_branch_completed(character_id: String, branch_id: String) -> bool:
	return branch_id in _character_entry(character_id).get("completed_branches", [])

func completed_branch_count(character_id: String) -> int:
	return _character_entry(character_id).get("completed_branches", []).size()

## Story 4.6 — rival victories complete a mini-branch and grant its unlock
## (unlock_id left empty for a branch with no unlock, e.g. none currently).
func mark_branch_completed(character_id: String, branch_id: String, unlock_id: String = "") -> void:
	var entry := _character_entry(character_id)
	var branches: Array = entry.get("completed_branches", [])
	if not branch_id in branches:
		branches.append(branch_id)
	entry["completed_branches"] = branches
	if unlock_id != "":
		var unlocks: Array = entry.get("unlocks", [])
		if not unlock_id in unlocks:
			unlocks.append(unlock_id)
		entry["unlocks"] = unlocks
	save_to_disk()

func unlocks_for(character_id: String) -> Array:
	return _character_entry(character_id).get("unlocks", [])

func is_organizer_defeated(character_id: String) -> bool:
	return _character_entry(character_id).get("organizer_defeated", false)

## Story 4.8 — completes that character's campaign run.
func mark_organizer_defeated(character_id: String) -> void:
	var entry := _character_entry(character_id)
	entry["organizer_defeated"] = true
	save_to_disk()

## Title screen (2026-08-09) — true if ANY character has actual progress
## (not just an auto-created blank entry from _character_entry() being
## queried, which never itself calls save_to_disk()). Drives whether
## "Nouvelle partie" needs the "progression sera perdue" warning and
## whether "Continuer la partie" has anything to resume.
func has_any_progress() -> bool:
	for character_id in _data.keys():
		var entry: Dictionary = _data[character_id]
		var branches: Array = entry.get("completed_branches", [])
		if int(entry.get("currency", 0)) > 0 or not branches.is_empty() or entry.get("organizer_defeated", false):
			return true
	return false

## The character_id of an in-progress campaign to resume, or "" if none.
## Only one campaign save slot exists in V1 (project-context.md), so the
## first character with real progress is the one to resume.
func character_with_progress() -> String:
	for character_id in _data.keys():
		var entry: Dictionary = _data[character_id]
		var branches: Array = entry.get("completed_branches", [])
		if int(entry.get("currency", 0)) > 0 or not branches.is_empty() or entry.get("organizer_defeated", false):
			return character_id
	return ""

## "Nouvelle partie" after the "progression sera perdue" warning is confirmed.
func reset_all() -> void:
	_data = {}
	save_to_disk()
