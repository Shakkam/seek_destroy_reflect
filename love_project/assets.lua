-- Central asset registry for the LÖVE port's real art/audio (Phase 7).
-- Copied straight from godot_project/assets/ — same source art, no new
-- generation needed. Loaded once here and shared by every screen that
-- needs it, rather than reloading the same image repeatedly.

local assets = {}

local function character_images(id)
	return {
		portrait = love.graphics.newImage("assets/characters/" .. id .. "/portrait.png"),
		full = love.graphics.newImage("assets/characters/" .. id .. "/full.png"),
		ship = love.graphics.newImage("assets/characters/" .. id .. "/ship.png"),
	}
end

assets.characters = {
	lourd = character_images("lourd"),
	controleur = character_images("controleur"),
	mitrailleur = character_images("mitrailleur"),
	vif = character_images("vif"),
	zoneur = character_images("zoneur"),
	perturbateur = character_images("perturbateur"),
	missiles = character_images("missiles"),
	mini = character_images("mini"),
}

-- Per-weapon-id projectile textures (side-split for machine_gun/turret,
-- same as projectile_factory.gd's own MACHINE_GUN_TEX_P1/P2 and
-- turret_node.gd's BULLET_TEXTURE/BULLET_TEXTURE_SIDE_1).
assets.bullets = {
	machine_gun = {
		[0] = love.graphics.newImage("assets/vfx/mitraillette_shot_bleu.png"),
		[1] = love.graphics.newImage("assets/vfx/mitraillette_shot_rose.png"),
	},
	bazooka = love.graphics.newImage("assets/vfx/bazook.png"),
	mini_shot = love.graphics.newImage("assets/vfx/bonbon.png"),
	stun_boomerang = love.graphics.newImage("assets/vfx/boomerang.png"),
	homing_missile = love.graphics.newImage("assets/vfx/missile.png"),
	vortex = love.graphics.newImage("assets/vfx/wind1.png"),
	turret = {
		[0] = love.graphics.newImage("assets/vfx/turret_bullet.png"),
		[1] = love.graphics.newImage("assets/vfx/turret_bullet_p2.png"),
	},
}
-- Ultra-only weapon ids reuse their base weapon's own art (no dedicated
-- Ultra sprites exist) — Traqueur's La Meute reads as a missile swarm,
-- Spreader's Pluie de Bonbons as a candy rain.
assets.bullets.ultra_la_meute = assets.bullets.homing_missile
assets.bullets.ultra_pluie_de_bonbons = assets.bullets.mini_shot

-- Epic boss (2026-09-05, Camil: "j'aimerais faire un clin d'oeil au dr
-- wily... pour son skin (in game et hors game)") — the organizer's own
-- masked-identity art, overriding whatever the REAL rival secretly playing
-- the boss would otherwise show (see is_boss_ship()/draw_ship() in
-- match_arena.lua). No full.png exists for this one (character_images()
-- would error trying to load it) — falls back to the portrait for the
-- Ultra intro slot, same as ship_node.gd's own BOSS_INTRO_TEXTURE_CANDIDATES.
assets.organisateur = {
	portrait = love.graphics.newImage("assets/characters/organisateur/portrait.png"),
	ship = love.graphics.newImage("assets/characters/organisateur/ship.png"),
}

assets.arena_background = love.graphics.newImage("assets/vfx/arena_background.png")
assets.turret = love.graphics.newImage("assets/vfx/turret.png")
assets.turret_charged = love.graphics.newImage("assets/vfx/turret_charged.png")
assets.hazard_zone = love.graphics.newImage("assets/vfx/hazard_zone.png")
assets.ball = love.graphics.newImage("assets/vfx/ball_1.png")

assets.aliens = {
	love.graphics.newImage("assets/enemies/alien_1.png"),
	love.graphics.newImage("assets/enemies/alien_2.png"),
}

-- Gradius mini-jeu (2026-09-20) — real sprites replacing the old
-- engine-drawn polygon placeholders (see gradius.lua's own draw code).
assets.gradius_drone = love.graphics.newImage("assets/enemies/gradius_drone.png")
assets.gradius_waver = love.graphics.newImage("assets/enemies/gradius_waver.png")
assets.gradius_shooter = love.graphics.newImage("assets/enemies/gradius_shooter.png")
-- Two hand-picked variations (Camil) — alternated across the boss's 5 weak
-- points so they don't all look identical.
assets.gradius_boss_weakpoints = {
	love.graphics.newImage("assets/enemies/gradius_boss_weakpoint1.png"),
	love.graphics.newImage("assets/enemies/gradius_boss_weakpoint2.png"),
}
assets.gradius_boss_hull = love.graphics.newImage("assets/enemies/gradius_boss_hull.png")
assets.powerup_power = love.graphics.newImage("assets/vfx/powerup_power.png")
assets.powerup_speed = love.graphics.newImage("assets/vfx/powerup_speed.png")
assets.powerup_heart = love.graphics.newImage("assets/vfx/powerup_heart.png")

-- Vif's Ultra "Bourrasque" — a dedicated 3-frame wind-vortex flipbook.
assets.bourrasque_vortex_frames = {
	love.graphics.newImage("assets/vfx/wind1.png"),
	love.graphics.newImage("assets/vfx/wind2.png"),
	love.graphics.newImage("assets/vfx/wind3.png"),
}

-- 2026-09-16 (Camil playtest: "les tourbillons de vif devraient faire 1 - 2
-- avec le sprite wind1 et wind3") — the base Tourbillon weapon's own normal
-- shot gets a 2-frame wind1/wind3 flipbook too now (was a single static
-- wind1.png), reusing match_arena.lua's existing generic anim_textures
-- cycling (the same mechanism Bourrasque's 3-frame swarm already uses).
assets.vortex_weapon_frames = {
	love.graphics.newImage("assets/vfx/wind1.png"),
	love.graphics.newImage("assets/vfx/wind3.png"),
}

-- Contrôleur's Ultra "Trou noir" — a 5-frame spinning swirl with its own
-- containment ring baked in.
assets.black_hole_frames = {
	love.graphics.newImage("assets/vfx/black_hole_1.png"),
	love.graphics.newImage("assets/vfx/black_hole_2.png"),
	love.graphics.newImage("assets/vfx/black_hole_3.png"),
	love.graphics.newImage("assets/vfx/black_hole_4.png"),
	love.graphics.newImage("assets/vfx/black_hole_5.png"),
}

-- Perturbateur's charged Boomerang de Feu trail (fire_trail_node.gd): a
-- plain white 4x4 pixel, same as Godot's own `Image.create(4, 4, ...);
-- img.fill(Color.WHITE)` — the actual look comes entirely from the
-- ParticleSystem's own color ramp/size, not the source texture.
do
	local image_data = love.image.newImageData(4, 4)
	image_data:mapPixel(function() return 1.0, 1.0, 1.0, 1.0 end)
	assets.fire_particle = love.graphics.newImage(image_data)
end

-- Campaign map (campaign_map_node.gd's own procedural-fallback art pass,
-- 2026-08-24, Camil: "dans sources je t'ai mis un spritesheet pour te
-- faire plaisir avec la map") — the grass terrain/road/tile-icon look used
-- for every character WITHOUT a real Atelier Cartographe export yet. All
-- 20 mook sprites are loaded (not just as many as any one campaign needs)
-- so a character with more mooks than another still gets distinct art
-- throughout (see campaign_map.lua's own mook-number wraparound).
assets.worldmap = {
	grass_bg = love.graphics.newImage("assets/worldmap/grass_bg.png"),
	road_straight = love.graphics.newImage("assets/worldmap/road_straight.png"),
	rival_tower = love.graphics.newImage("assets/worldmap/rival_tower.png"),
	boss_castle = love.graphics.newImage("assets/worldmap/boss_castle.png"),
	player_token = love.graphics.newImage("assets/worldmap/player_token.png"),
	mook = {},
}
for i = 1, 20 do
	assets.worldmap.mook[i] = love.graphics.newImage(string.format("assets/worldmap/mook_%02d.png", i))
end

-- NOT set to loop natively (see title_music.lua) — title_music.gd's own
-- loop is a manual _player.finished -> _replay() reconnect specifically so
-- every loop-back can be observed (title_screen's word-drop entrance
-- replays on every loop, not just the first). A native seamless loop would
-- hide that boundary completely.
assets.title_music = love.audio.newSource("assets/audio/music/title_theme.wav", "stream")

return assets
