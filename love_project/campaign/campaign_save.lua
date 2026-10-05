-- Ported from godot_project/nodes/campaign_save.gd — local save for
-- campaign progress. A plain Lua module rather than a class: require()
-- already caches a module after its first load, which is exactly the
-- "autoload singleton" behavior Godot's own autoload gives campaign_save.gd
-- (see the port spec, section 3, "Autoloads"). Orchestration/persistence,
-- not simulation — never require this from simulation/ (Regle absolue n1).
--
-- FORMAT DECISION (flagged for the collaborator, per this project's own
-- convention of documenting non-1:1 choices): the Godot version saves JSON.
-- This port saves a plain Lua table literal instead (`return { ... }`,
-- read back via `load()`) — a completely standard, dependency-free pattern
-- for LÖVE save files, and avoids pulling in a JSON library for a save
-- format nothing outside this module actually needs to be JSON. Revisit
-- if the collaborator's own platform expects real JSON on disk.
--
-- Persistence note: load_from_disk()/save_to_disk() use plain io.open, so
-- they work identically under Busted and under `love .` in development.
-- A packaged/fused LÖVE build needs love.filesystem for its writable save
-- directory instead — that swap is Phase 6 (LÖVE integration) work, not
-- here; this module's path is passed in explicitly for exactly that reason
-- (set_save_path()), so the swap only touches load_from_disk/save_to_disk.

local campaign_save = {}

local DEFAULT_SAVE_PATH = "campaign_save.lua"

local _data = {}
local _save_path = DEFAULT_SAVE_PATH
local _autosave_enabled = true

-- character_id -> { currency, campaign_progress, unlocks = {ids...},
-- organizer_defeated, resolved_case_ids = {ids...} }
local function character_entry(character_id)
	if not _data[character_id] then
		_data[character_id] = {
			currency = 0,
			campaign_progress = 0,
			unlocks = {},
			organizer_defeated = false,
			resolved_case_ids = {},
		}
	end
	return _data[character_id]
end

local function contains(list, value)
	for _, item in ipairs(list) do
		if item == value then
			return true
		end
	end
	return false
end

-- Minimal serializer for this module's own data shape (numbers, strings,
-- booleans, and arrays/dicts of those) — not a general-purpose one, and
-- deliberately not needed to be: we only ever serialize what we ourselves
-- wrote to `_data`.
local serialize_value, serialize_table

serialize_table = function(tbl, indent)
	local inner_indent = indent .. "\t"
	local parts = {}
	local array_length = 0
	while tbl[array_length + 1] ~= nil do
		array_length = array_length + 1
	end
	for i = 1, array_length do
		table.insert(parts, inner_indent .. serialize_value(tbl[i], inner_indent))
	end
	for key, value in pairs(tbl) do
		local is_array_index = type(key) == "number" and key >= 1 and key <= array_length and key == math.floor(key)
		if not is_array_index then
			local key_str
			if type(key) == "string" and key:match("^[%a_][%w_]*$") then
				key_str = key
			else
				key_str = "[" .. serialize_value(key, inner_indent) .. "]"
			end
			table.insert(parts, inner_indent .. key_str .. " = " .. serialize_value(value, inner_indent))
		end
	end
	if #parts == 0 then
		return "{}"
	end
	return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

serialize_value = function(value, indent)
	local value_type = type(value)
	if value_type == "number" or value_type == "boolean" then
		return tostring(value)
	elseif value_type == "string" then
		return string.format("%q", value)
	elseif value_type == "table" then
		return serialize_table(value, indent)
	end
	error("campaign_save: cannot serialize a value of type " .. value_type)
end

function campaign_save.set_save_path(path)
	_save_path = path
end

function campaign_save.set_autosave_enabled(enabled)
	_autosave_enabled = enabled
end

function campaign_save.load_from_disk(path)
	path = path or _save_path
	local file = io.open(path, "r")
	if not file then
		_data = {}
		return
	end
	local content = file:read("*a")
	file:close()
	local chunk = load(content, "campaign_save")
	if not chunk then
		_data = {}
		return
	end
	local ok, result = pcall(chunk)
	_data = (ok and type(result) == "table") and result or {}
end

function campaign_save.save_to_disk(path)
	path = path or _save_path
	local file = io.open(path, "w")
	if not file then
		return
	end
	file:write("return " .. serialize_table(_data, "") .. "\n")
	file:close()
end

local function autosave()
	if _autosave_enabled then
		campaign_save.save_to_disk()
	end
end

function campaign_save.get_currency(character_id)
	return character_entry(character_id).currency
end

-- Story 4.4 — mook victories grant Exp/Gold.
function campaign_save.add_currency(character_id, amount)
	local entry = character_entry(character_id)
	entry.currency = entry.currency + amount
	autosave()
end

function campaign_save.get_campaign_progress(character_id)
	return character_entry(character_id).campaign_progress
end

-- Called after every win (mook, rival, or organizer) with CampaignContext's
-- own campaign_step, so resuming later ("Continuer la partie") lands back
-- on the exact right tile of the single world map.
function campaign_save.set_campaign_progress(character_id, step)
	local entry = character_entry(character_id)
	entry.campaign_progress = step
	autosave()
end

-- Story 4.6 — rival victories grant their unlock (empty unlock_id for a
-- branch with no unlock).
function campaign_save.grant_unlock(character_id, unlock_id)
	if unlock_id == "" or unlock_id == nil then
		return
	end
	local entry = character_entry(character_id)
	if not contains(entry.unlocks, unlock_id) then
		table.insert(entry.unlocks, unlock_id)
	end
	autosave()
end

function campaign_save.unlocks_for(character_id)
	return character_entry(character_id).unlocks
end

function campaign_save.is_organizer_defeated(character_id)
	return character_entry(character_id).organizer_defeated
end

-- Story 4.8 — completes that character's campaign run.
function campaign_save.mark_organizer_defeated(character_id)
	local entry = character_entry(character_id)
	entry.organizer_defeated = true
	autosave()
end

local function entry_has_progress(entry)
	return entry.currency > 0
		or entry.campaign_progress > 0
		or entry.organizer_defeated
		or #entry.resolved_case_ids > 0
end

-- Title screen — true if ANY character has actual progress (not just an
-- auto-created blank entry from character_entry() being queried, which
-- never itself autosaves). Drives whether "Nouvelle partie" needs the
-- "progression sera perdue" warning and whether "Continuer la partie" has
-- anything to resume.
function campaign_save.has_any_progress()
	for _, entry in pairs(_data) do
		if entry_has_progress(entry) then
			return true
		end
	end
	return false
end

-- The character_id of an in-progress campaign to resume, or "" if none.
-- Only one campaign save slot exists in V1, so the first character with
-- real progress is the one to resume.
function campaign_save.character_with_progress()
	for character_id, entry in pairs(_data) do
		if entry_has_progress(entry) then
			return character_id
		end
	end
	return ""
end

-- Graph-mode campaigns (JSON with path_nodes + connections): the set of
-- resolved combat node ids for this character. Empty for branch/linear-mode
-- characters (they use campaign_progress instead).
function campaign_save.get_resolved_case_ids(character_id)
	return character_entry(character_id).resolved_case_ids
end

-- Called after winning a fight in graph-mode campaigns. Idempotent (safe to
-- call with a duplicate id). Does not interfere with campaign_progress.
function campaign_save.add_resolved_case_id(character_id, case_id)
	if case_id == "" or case_id == nil then
		return
	end
	local entry = character_entry(character_id)
	if not contains(entry.resolved_case_ids, case_id) then
		table.insert(entry.resolved_case_ids, case_id)
	end
	autosave()
end

-- "Nouvelle partie" after the "progression sera perdue" warning is confirmed.
function campaign_save.reset_all()
	_data = {}
	autosave()
end

return campaign_save
