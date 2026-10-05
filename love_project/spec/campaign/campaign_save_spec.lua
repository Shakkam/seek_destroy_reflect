local campaign_save = require("campaign.campaign_save")

describe("campaign_save", function()
	before_each(function()
		-- Disable the real disk write for every test except the dedicated
		-- load/save round-trip below — this is an autoload-style singleton
		-- (module state persists across requires), so each test starts from
		-- a clean slate without ever touching the filesystem.
		campaign_save.set_autosave_enabled(false)
		campaign_save.reset_all()
	end)

	it("a never-queried character has no progress", function()
		assert.are.equal(0, campaign_save.get_currency("vif"))
		assert.are.equal(0, campaign_save.get_campaign_progress("vif"))
		assert.is_false(campaign_save.is_organizer_defeated("vif"))
		assert.are.same({}, campaign_save.unlocks_for("vif"))
	end)

	it("add_currency() accumulates per character, independently of other characters", function()
		campaign_save.add_currency("vif", 100)
		campaign_save.add_currency("vif", 50)
		campaign_save.add_currency("lourd", 20)
		assert.are.equal(150, campaign_save.get_currency("vif"))
		assert.are.equal(20, campaign_save.get_currency("lourd"))
	end)

	it("set_campaign_progress() persists a resumable step position", function()
		campaign_save.set_campaign_progress("vif", 5)
		assert.are.equal(5, campaign_save.get_campaign_progress("vif"))
		campaign_save.set_campaign_progress("vif", 6)
		assert.are.equal(6, campaign_save.get_campaign_progress("vif"))
	end)

	it("grant_unlock() is idempotent and ignores an empty id", function()
		campaign_save.grant_unlock("vif", "bonus_weapon")
		campaign_save.grant_unlock("vif", "bonus_weapon")
		campaign_save.grant_unlock("vif", "")
		assert.are.same({ "bonus_weapon" }, campaign_save.unlocks_for("vif"))
	end)

	it("mark_organizer_defeated() completes that character's campaign run", function()
		assert.is_false(campaign_save.is_organizer_defeated("vif"))
		campaign_save.mark_organizer_defeated("vif")
		assert.is_true(campaign_save.is_organizer_defeated("vif"))
	end)

	it("add_resolved_case_id() is idempotent (graph-mode campaigns)", function()
		campaign_save.add_resolved_case_id("vif", "node_3")
		campaign_save.add_resolved_case_id("vif", "node_3")
		campaign_save.add_resolved_case_id("vif", "node_5")
		assert.are.same({ "node_3", "node_5" }, campaign_save.get_resolved_case_ids("vif"))
	end)

	it("has_any_progress()/character_with_progress() see currency, step, organizer-defeated, or a resolved case", function()
		assert.is_false(campaign_save.has_any_progress())
		assert.are.equal("", campaign_save.character_with_progress())

		campaign_save.add_currency("vif", 10)
		assert.is_true(campaign_save.has_any_progress())
		assert.are.equal("vif", campaign_save.character_with_progress())
	end)

	it("reset_all() clears every character's progress", function()
		campaign_save.add_currency("vif", 10)
		campaign_save.set_campaign_progress("lourd", 3)
		campaign_save.reset_all()
		assert.is_false(campaign_save.has_any_progress())
		assert.are.equal(0, campaign_save.get_currency("vif"))
		assert.are.equal(0, campaign_save.get_campaign_progress("lourd"))
	end)

	it("save_to_disk()/load_from_disk() round-trip through a real file", function()
		local path = os.tmpname()
		campaign_save.add_currency("vif", 250)
		campaign_save.set_campaign_progress("vif", 4)
		campaign_save.grant_unlock("vif", "bonus_weapon")
		campaign_save.save_to_disk(path)

		campaign_save.reset_all() -- wipe in-memory state to prove the reload actually reads the file
		assert.are.equal(0, campaign_save.get_currency("vif"))

		campaign_save.load_from_disk(path)
		assert.are.equal(250, campaign_save.get_currency("vif"))
		assert.are.equal(4, campaign_save.get_campaign_progress("vif"))
		assert.are.same({ "bonus_weapon" }, campaign_save.unlocks_for("vif"))

		os.remove(path)
	end)

	it("load_from_disk() of a missing file starts empty rather than erroring", function()
		campaign_save.load_from_disk("this_file_does_not_exist.lua")
		assert.is_false(campaign_save.has_any_progress())
	end)
end)
