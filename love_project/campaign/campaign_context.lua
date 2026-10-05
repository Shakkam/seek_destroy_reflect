-- Ported from godot_project/nodes/campaign_context.gd — carries a campaign
-- encounter's setup across a screen change, from the campaign map into a
-- match screen and back. A plain Lua module (see campaign_save.lua's own
-- header note: require()'s module cache already gives "autoload"
-- semantics, no class needed). Orchestration, not simulation — never
-- require this from simulation/ (Regle absolue n1).
--
-- 2026-08-24 world-map rework carried over as-is: campaign_step is a flat,
-- fixed-order position across ALL of a character's content (every branch's
-- mook_1/mook_2/rival back to back, then the organizer) — no picking which
-- branch to enter. Progress only ever moves forward: advance_step() is the
-- only way campaign_step changes; a loss re-fights the same step rather
-- than resetting it.
--
-- Three encounter sources coexist, checked in this priority order
-- (mirrors current_encounter() below exactly):
--   1. debug_encounter — the cheat menu's throwaway fight, bypasses
--      everything else.
--   2. graph mode (is_graph_mode) — pending_graph_encounter, set by the
--      map screen right before the scene change; combat nodes can be
--      fought in any order.
--   3. encounter_sequence (JSON-first characters, built by the map screen
--      from an exported PNG+JSON map) if non-empty, else the branch
--      formula (campaign.mini_branches) as the original fallback.

local campaign_context = {}

campaign_context.campaign = nil
campaign_context.campaign_step = 0
campaign_context.is_graph_mode = false
campaign_context.current_graph_node_id = ""
campaign_context.pending_graph_encounter = nil
campaign_context.encounter_sequence = {}
campaign_context.debug_encounter = nil

-- Total tiles in the single world map. When encounter_sequence is
-- populated (JSON-first characters), returns its length directly.
-- Otherwise falls back to the branch formula (#mini_branches * 3 + 1) for
-- characters without a map.
function campaign_context.total_steps()
	if not campaign_context.campaign then
		return 0
	end
	if #campaign_context.encounter_sequence > 0 then
		return #campaign_context.encounter_sequence
	end
	return #campaign_context.campaign.mini_branches * 3 + 1
end

-- Called by the map screen when a character has a JSON map: seq is a flat,
-- index-ordered list of rival_encounter_data built from the branch pools
-- in JSON case order.
function campaign_context.set_encounter_sequence(seq)
	campaign_context.encounter_sequence = seq
end

function campaign_context.is_organizer_fight()
	if campaign_context.debug_encounter or not campaign_context.campaign then
		return false
	end
	if campaign_context.is_graph_mode then
		return campaign_context.pending_graph_encounter ~= nil
			and campaign_context.pending_graph_encounter == campaign_context.campaign.organizer_encounter
	end
	return campaign_context.campaign_step == campaign_context.total_steps() - 1
end

function campaign_context.has_pending_encounter()
	return campaign_context.campaign ~= nil
		and (campaign_context.debug_encounter ~= nil or campaign_context.campaign_step < campaign_context.total_steps())
end

-- The rival_encounter_data for whatever should be fought right now, given
-- campaign_step (or the cheat-menu debug fight). nil once campaign_step
-- has already reached total_steps() (nothing left to fight).
function campaign_context.current_encounter()
	if campaign_context.debug_encounter then
		return campaign_context.debug_encounter
	end
	if not campaign_context.campaign then
		return nil
	end
	if campaign_context.is_graph_mode then
		return campaign_context.pending_graph_encounter
	end
	local step = campaign_context.campaign_step
	local total = campaign_context.total_steps()
	if step < 0 or step >= total then
		return nil
	end
	if #campaign_context.encounter_sequence > 0 then
		return campaign_context.encounter_sequence[step + 1] -- 0-based step -> 1-based Lua array
	end
	-- Branch-based fallback for characters without a JSON map.
	if step == total - 1 then
		return campaign_context.campaign.organizer_encounter
	end
	local branch = campaign_context.campaign.mini_branches[math.floor(step / 3) + 1]
	local slot = step % 3
	if slot == 0 then
		return branch.mook_1
	elseif slot == 1 then
		return branch.mook_2
	end
	return branch.rival
end

-- The branch the current step belongs to, or nil for the organizer/a debug
-- fight, or nil in JSON-first mode (encounter_sequence set) where the
-- branch structure no longer maps to campaign_step. Callers must nil-check.
function campaign_context.current_branch()
	local step = campaign_context.campaign_step
	if campaign_context.debug_encounter
		or not campaign_context.campaign
		or campaign_context.is_organizer_fight()
		or step < 0
		or step >= campaign_context.total_steps() then
		return nil
	end
	if #campaign_context.encounter_sequence > 0 then
		return nil -- JSON mode: no per-step branch mapping
	end
	return campaign_context.campaign.mini_branches[math.floor(step / 3) + 1]
end

function campaign_context.clear()
	campaign_context.campaign = nil
	campaign_context.campaign_step = 0
	campaign_context.debug_encounter = nil
	campaign_context.encounter_sequence = {}
	campaign_context.is_graph_mode = false
	campaign_context.current_graph_node_id = ""
	campaign_context.pending_graph_encounter = nil
end

-- Same partial reset return_to_map() always did — clears the transient
-- debug-fight state without touching campaign/campaign_step, so whichever
-- screen this returns to still knows which character's map and how far
-- along it to show. current_graph_node_id is intentionally kept so the map
-- screen can restore the token at the same node after a loss.
function campaign_context.return_to_map()
	campaign_context.debug_encounter = nil
	campaign_context.pending_graph_encounter = nil
end

-- Cheat menu — fight a specific opponent with a specific twist (or no
-- twist) active, full hp both sides, no campaign progression touched.
function campaign_context.start_debug_fight(campaign_data, encounter)
	campaign_context.campaign = campaign_data
	campaign_context.debug_encounter = encounter
end

-- Called once by the map screen after reading campaign_save's persisted
-- progress for this character — the single entry point into a real
-- (non-debug) campaign run.
function campaign_context.enter_campaign(campaign_data, step)
	campaign_context.campaign = campaign_data
	campaign_context.campaign_step = step
	campaign_context.debug_encounter = nil
end

-- Called after winning the current step's fight.
function campaign_context.advance_step()
	campaign_context.campaign_step = campaign_context.campaign_step + 1
end

return campaign_context
