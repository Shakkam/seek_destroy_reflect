local campaign_context = require("campaign.campaign_context")
local campaign_data = require("simulation.campaign_data")
local mini_branch_data = require("simulation.mini_branch_data")
local rival_encounter_data = require("simulation.rival_encounter_data")

describe("campaign_context", function()
	before_each(function()
		-- A singleton module (require()'s own cache gives the "autoload"
		-- semantics — see its header note), so every test starts from a
		-- clean slate rather than instancing a fresh object like the Godot
		-- test this mirrors does.
		campaign_context.clear()
	end)

	it("sequences mook_1 -> mook_2 -> rival -> organizer as campaign_step advances", function()
		local mook_1 = rival_encounter_data.new({ is_mook = true })
		local mook_2 = rival_encounter_data.new({ is_mook = true })
		local rival = rival_encounter_data.new({ is_mook = false })
		local organizer = rival_encounter_data.new()

		local branch = mini_branch_data.new({ id = "vs_test", mook_1 = mook_1, mook_2 = mook_2, rival = rival })
		local campaign = campaign_data.new({ mini_branches = { branch }, organizer_encounter = organizer })

		campaign_context.enter_campaign(campaign, 0)
		assert.are.equal(0, campaign_context.campaign_step)
		assert.are.equal(mook_1, campaign_context.current_encounter())

		campaign_context.advance_step()
		assert.are.equal(1, campaign_context.campaign_step)
		assert.are.equal(mook_2, campaign_context.current_encounter())

		campaign_context.advance_step()
		assert.are.equal(2, campaign_context.campaign_step)
		assert.are.equal(rival, campaign_context.current_encounter())

		campaign_context.advance_step()
		assert.is_true(campaign_context.is_organizer_fight())
		assert.are.equal(organizer, campaign_context.current_encounter())
	end)

	-- 2026-08-08 regression: even if mook_1 and mook_2 happen to be authored
	-- as the SAME resource, step-based sequencing must still tell them
	-- apart at each of their two steps (this holds trivially here since
	-- current_encounter() only ever reads by step index, never compares
	-- identity against a "seen" set — but is worth pinning explicitly).
	it("tells two identical mook encounters apart by step, not identity", function()
		local shared_mook = rival_encounter_data.new({ is_mook = true })
		local rival = rival_encounter_data.new({ is_mook = false })
		local branch = mini_branch_data.new({ mook_1 = shared_mook, mook_2 = shared_mook, rival = rival })
		local campaign = campaign_data.new({ mini_branches = { branch }, organizer_encounter = rival_encounter_data.new() })

		campaign_context.enter_campaign(campaign, 0)
		assert.are.equal(shared_mook, campaign_context.current_encounter())
		campaign_context.advance_step()
		assert.are.equal(shared_mook, campaign_context.current_encounter())
		campaign_context.advance_step()
		assert.are.equal(rival, campaign_context.current_encounter())
	end)

	it("current_branch() tracks the branch a mook/rival step belongs to, nil for the organizer", function()
		local branch = mini_branch_data.new({
			mook_1 = rival_encounter_data.new(),
			mook_2 = rival_encounter_data.new(),
			rival = rival_encounter_data.new(),
		})
		local campaign = campaign_data.new({ mini_branches = { branch }, organizer_encounter = rival_encounter_data.new() })
		campaign_context.enter_campaign(campaign, 0)
		assert.are.equal(branch, campaign_context.current_branch())

		campaign_context.campaign_step = campaign_context.total_steps() - 1 -- jump straight to the organizer
		assert.is_nil(campaign_context.current_branch())
	end)

	it("an encounter_sequence (JSON-first characters) overrides the branch formula entirely", function()
		local first = rival_encounter_data.new()
		local second = rival_encounter_data.new()
		local campaign = campaign_data.new({ mini_branches = {} }) -- deliberately empty — the sequence is authoritative
		campaign_context.enter_campaign(campaign, 0)
		campaign_context.set_encounter_sequence({ first, second })

		assert.are.equal(2, campaign_context.total_steps())
		assert.are.equal(first, campaign_context.current_encounter())
		assert.is_nil(campaign_context.current_branch()) -- no per-step branch mapping in JSON mode
		campaign_context.advance_step()
		assert.are.equal(second, campaign_context.current_encounter())
	end)

	-- Cheat menu (2026-08-09) — a THIRD case alongside branch/organizer
	-- fights, distinct from both.
	it("a debug fight bypasses campaign progression entirely", function()
		local campaign = campaign_data.new()
		local encounter = rival_encounter_data.new({ is_mook = false })

		campaign_context.start_debug_fight(campaign, encounter)
		assert.is_true(campaign_context.has_pending_encounter())
		assert.is_false(campaign_context.is_organizer_fight())
		assert.are.equal(encounter, campaign_context.current_encounter())

		campaign_context.clear()
		assert.is_nil(campaign_context.debug_encounter)
		assert.is_false(campaign_context.has_pending_encounter())
	end)

	it("has_pending_encounter() is false once campaign_step reaches the end", function()
		local campaign = campaign_data.new({ mini_branches = {} }) -- total_steps() = 0*3+1 = 1 (organizer only)
		campaign_context.enter_campaign(campaign, 1) -- already past the only step
		assert.is_false(campaign_context.has_pending_encounter())
		assert.is_nil(campaign_context.current_encounter())
	end)

	it("return_to_map() clears the debug/graph transient state but keeps campaign_step", function()
		local campaign = campaign_data.new()
		campaign_context.enter_campaign(campaign, 3)
		campaign_context.pending_graph_encounter = rival_encounter_data.new()
		campaign_context.return_to_map()
		assert.is_nil(campaign_context.pending_graph_encounter)
		assert.are.equal(3, campaign_context.campaign_step) -- untouched
	end)
end)
