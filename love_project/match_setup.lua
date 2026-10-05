-- Ported from godot_project's MatchSetup autoload — carries the Versus
-- character picks from CharacterSelect into MatchArena across the screen
-- change. A plain module (require()'s cache = the autoload singleton),
-- same convention as campaign/campaign_context.lua.

local match_setup = {}

match_setup.p1_character = nil
match_setup.p2_character = nil

return match_setup
