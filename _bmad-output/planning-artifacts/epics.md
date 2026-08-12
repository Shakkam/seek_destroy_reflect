---
stepsCompleted: [1, 2, 3]
note: 'Epic 1 and Epic 2 fully detailed with stories, acceptance criteria, and implemented in Godot. Epic 3 (online multiplayer) explicitly paused by Camil (2026-08-06) — presenting a local-only build to a friend for his portal is the near-term priority. Epic 4 (solo campaign) fully detailed 2026-08-07 (Stories 4.1-4.9) after a dedicated brainstorm + Party Mode session; Camil greenlit direct implementation ("je te laisse coder tout ça") rather than per-story formal review, mirroring how Epic 1/2 moved to implementation.'
inputDocuments:
  - '_bmad-output/planning-artifacts/briefs/brief-seek-and-destroy-and-reflect-the-ball-2026-07-30/brief.md'
  - '_bmad-output/brainstorming-session-2026-07-29.md'
  - '_bmad-output/planning-artifacts/gdds/gdd-seek-and-destroy-and-reflect-the-ball-2026-07-31/gdd.md'
  - '_bmad-output/planning-artifacts/gdds/gdd-seek-and-destroy-and-reflect-the-ball-2026-07-31/epics.md'
  - '_bmad-output/game-architecture.md'
  - '_bmad-output/project-context.md'
---

# seek and destroy and reflect the ball - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for Seek and Destroy and Return the Ball, decomposing the requirements from the GDD and Architecture into implementable stories. UI/UX guidance now lives in a dedicated UX PRD (`_bmad-output/planning-artifacts/prds/prd-ux-seek-and-destroy-and-reflect-the-ball-2026-08-12.md`, split out 2026-08-12 as the GDD's Art & Audio Direction section grew too long) rather than inside the GDD.

## Requirements Inventory

### Functional Requirements

FR1: The player can move their ship freely in 2D within their half of the arena, confined by a clear center frontier.
FR2: The player can aim and return the ball with directional control and spin/lift effects.
FR3: The ball speed increases slightly with each successful rally exchange.
FR4: The player can select a weapon via a dedicated input without blocking movement.
FR5: The player can fire the currently selected weapon, dealing fixed damage per hit at a weapon-specific fire rate.
FR6: Missing the ball fills the opponent's weapon gauge (equivalent to a full light-weapon charge) rather than dealing direct damage to the player who missed.
FR7: A successful ball return fills the player's own weapon gauge; stylish/trick-shot returns grant a bonus fill, displayed on-screen.
FR8: Heavy weapons impose a vulnerability window (reduced mobility) during their firing animation.
FR9: Each of the 8 roster characters has a fixed, asymmetric kit of 3-4 weapons known from the start of the match (no random unlocks mid-match).
FR10: A match consists of best-of-3 rounds, each targeting 90-120 seconds, with a 100 HP pool per character.
FR11: A round ends when a character's HP reaches 0.
FR12: Turret-type weapons can be freely placed on the arena and then act autonomously.
FR13: Certain weapons can grant a temporary mobility boost (indirect defensive tool) or a stun/setup effect enabling a follow-up hit.
FR14: The player's HP is displayed via an explicit HUD bar.
FR15: Weapon/gauge state is displayed diegetically on the ship (progressive transparency, gold outline when fully charged) rather than via a traditional HUD element.
FR16: The game supports local 1v1 matches.
FR17: (Full-MVP tier) The game supports online 1v1 quick-match play, with no ranked/MMR at launch.
FR18: (Full-MVP tier / aspirational target) A solo campaign offers sequential fights per character with unlockable weapons/bonuses, a light world map, and a final boss per character.
FR19: The player can play a local match against a basic/heuristic AI opponent, so the core loop can be tested solo without a second human player. (Gap identified post-epic-design by Camil — not covered by the GDD's AI-driven balance-testing tooling, which is a dev/production tool, not a player-facing opponent.)
FR20: Each of the 8 roster characters has AI behavior tuned to its specific weapon kit (e.g. a Heavy plays defensively/opportunistically, a Machine-gunner plays aggressively at range), so playing against the AI with any character from the full roster is meaningful. (Identified as a direct consequence of FR19 + FR9 — flagged by Camil.)

### NonFunctional Requirements

NFR1: The game must sustain a locked/stable 30 FPS on the reference development machine.
NFR2: The core simulation loop (movement, ball, weapons) must be a deterministic pure function of (state, input), to support a future rollback netcode integration without requiring a rewrite.
NFR3: Game logic in `simulation/` must remain fully decoupled from Godot nodes/rendering, to preserve future console-export portability.
NFR4: The roster must be balanced such that no character is dominant or unusable, validated via AI-driven agent-vs-agent testing plus human playtesting.
NFR5: Weapon/character data must be defined via Godot Custom Resources (`.tres`), never hardcoded, to support tuning without code changes.

### Additional Requirements

- Engine: Godot 4.7.1, GDScript. No starter template — project initializes from an empty Godot project (explicit architecture decision).
- MCP dev tool: GoPeak (Gopeak-godot-mcp) for AI-assisted Godot editor access during implementation.
- Match Tick Resolver pattern: fixed per-tick resolution order (inputs → ships → ball → weapons → snapshot) must be respected by any new simulation system.
- State Management: explicit State Machine per entity (ship, ball, match) — not ECS in V1.
- Save system: local JSON for settings/progression, no cloud save in V1.
- Netcode model specifics (rollback library choice, sync structure) are intentionally deferred — not an Epic 1/2 requirement, treated as a dedicated future research phase.
- Campaign data model is not yet architected — deferred alongside the campaign's post-MVP/aspirational status.

### UX Design Requirements

_2026-08-12: UI/UX guidance (diegetic HUD, art direction, readability principles, screen-by-screen flow, controls) now lives in a dedicated UX PRD — `_bmad-output/planning-artifacts/prds/prd-ux-seek-and-destroy-and-reflect-the-ball-2026-08-12.md` — split out of the GDD's "Art and Audio Direction" section (still reflected in FR14/FR15 above)._

**UX-DR1 (FR18, Epic 4 — 2026-08-06):** Campaign map structure references *Soul Calibur IV*'s Tower of Lost Souls chapter map: a branching node map per chapter (not a linear stage list), each node showing a stage preview thumbnail, a chapter title, running Exp/Gold counters, a description panel for the selected stage, and a "world map" zoom-out affordance. A stage can unlock multiple next paths (branching, not strictly linear progression).

### FR Coverage Map

FR1: Epic 1 - Mouvement libre en 2D dans sa moitié de terrain
FR2: Epic 1 - Visée et renvoi de balle avec spin/lift
FR3: Epic 1 - Vitesse de balle croissante par échange
FR4: Epic 1 - Sélection d'arme via bouton dédié
FR5: Epic 1 - Tir de l'arme sélectionnée, dégâts fixes
FR6: Epic 1 - Balle ratée remplit la jauge adverse
FR7: Epic 1 - Renvoi réussi remplit la jauge, bonus trick shot
FR8: Epic 1 - Fenêtre de vulnérabilité sur armes lourdes
FR9: Epic 2 - Kits fixes asymétriques des 8 personnages
FR10: Epic 1 - Format best-of-3, 100 PV
FR11: Epic 1 - Fin de round à 0 PV
FR12: Epic 2 - Tourelles à placement libre
FR13: Epic 2 - Boost de mobilité / stun de setup
FR14: Epic 1 - HUD PV explicite (version minimale/fonctionnelle)
FR15: Epic 1 - Lisibilité diégétique des jauges (version minimale/fonctionnelle)
FR16: Epic 1 - 1v1 local
FR17: Epic 3 - 1v1 online quick-match
FR18: Epic 4 - Campagne solo par personnage
FR19: Epic 1 - IA basique/heuristique pour test solo
FR20: Epic 2 - Comportement IA adapté au kit de chaque personnage

## Epic List

### Epic 1: Boucle de duel centrale (1v1 local)
Un joueur peut jouer un match complet en 1v1 local, contre un adversaire, avec la boucle centrale entièrement fonctionnelle : mouvement, renvoi de balle, tir d'arme, jauges, victoire/défaite.
**FRs covered:** FR1, FR2, FR3, FR4, FR5, FR6, FR7, FR8, FR10, FR11, FR14, FR15, FR16, FR19
**Note d'implémentation :** correspond au palier "Prototype" du GDD — roster minimal (2 personnages suffisent pour valider la boucle), pas d'équilibrage poussé requis à ce stade. **Précision issue du Party Mode (2026-07-31) :** le HUD de PV (FR14) et la lisibilité diégétique des jauges (FR15) livrés ici sont des versions **minimales/fonctionnelles** — une barre de vie basique et un état d'arme lisible, pas encore le liseré doré animé avec effets/particules (ce niveau de finition arrive avec l'Epic 5 implicite : passe d'art/audio, distribuée dans les stories plutôt qu'une epic séparée). Nécessaire ici car sans lisibilité minimale des PV/jauges, impossible d'évaluer si le prototype est fun — ce n'est pas du polish, c'est un prérequis de test. **Ajout post-conception (2026-07-31) :** FR19 (adversaire IA basique/heuristique) a été identifié comme un gap par Camil — sans adversaire, impossible de tester le prototype en solo. Distinct des tests d'équilibrage IA du GDD (outil de dev, pas un adversaire jouable). IA volontairement simple à ce stade — réagit à la balle et tire de façon basique, suffisant pour évaluer le fun sans complexifier l'Epic 1 avant de savoir si le jeu est bon.

### Epic 2: Roster jouable & variété d'armes
Le joueur peut choisir parmi les 8 personnages du roster complet, chacun avec son kit d'armes fonctionnel et distinct (dont tourelles à placement libre et effets de stun/mobilité).
**FRs covered:** FR9, FR12, FR13, FR20
**Note :** dépend de l'Epic 1 (boucle de jeu déjà fonctionnelle) mais reste autonome — le joueur peut jouer avec 8 personnages complets sans avoir besoin du online ou de la campagne. **Précision issue du Party Mode (2026-07-31) :** la condition de complétion de cette epic est "roster de 8 jouable et fonctionnel", **pas** "roster équilibré". L'équilibrage (NFR4, tests IA agent-vs-agent + playtest humain) est un travail **itératif continu sans ligne d'arrivée fixe** — traité comme une préoccupation permanente documentée séparément (à relier à un futur `gds-test-design`), et non comme une condition de "done" de cette epic, pour éviter qu'elle ne se termine jamais. **Ajout post-conception (2026-07-31) :** FR20 (comportement IA par personnage) identifié par Camil comme conséquence directe du roster complet + de l'IA de l'Epic 1 — sans ça, jouer contre l'IA avec n'importe quel perso du roster n'aurait pas de sens (un Lourd et un Mitrailleur doivent se jouer différemment, y compris pilotés par l'IA).

### Epic 3: Multijoueur en ligne
Le joueur peut jouer un 1v1 rapide contre un adversaire en ligne.
**FRs covered:** FR17
**Note :** dépend des Epics 1-2 (boucle + roster), netcode précis traité en recherche dédiée avant implémentation (voir Architecture — garde-fou Party Mode).

### Epic 4: Campagne solo
Le joueur peut vivre une campagne narrative par personnage avec déblocages progressifs et un boss final.
**FRs covered:** FR18
**Note :** dépend des Epics 1-2 ; palier aspirationnel post-MVP complet selon le GDD.

---

## Epic 1: Boucle de duel centrale (1v1 local)

Un joueur peut jouer un match complet en 1v1 local, contre un adversaire, avec la boucle centrale entièrement fonctionnelle : mouvement, renvoi de balle, tir d'arme, jauges, victoire/défaite.

### Story 1.1: Mouvement du vaisseau dans sa moitié de terrain

As a player,
I want to move my ship freely in 2D within my half of the arena,
So that I can position myself relative to the ball and my opponent.

**Acceptance Criteria:**

**Given** a match has started
**When** the player provides directional input
**Then** the ship moves responsively in 2D at the target speed, feeling like a direct extension of player intent (no acceleration/braking inertia in this first pass)
**And** the ship cannot cross the center frontier into the opponent's half
**And** the ship cannot leave the arena bounds

### Story 1.2: Visée et renvoi de balle avec effet spin/lift

As a player,
I want to aim my ball return and apply a spin/lift effect,
So that I can express skill and make the return harder to predict.

**Acceptance Criteria:**

**Given** the ball is approaching the player's ship
**When** the player is in range to return it and provides an aim direction (and optionally a spin/lift modifier)
**Then** the ball's outgoing trajectory reflects the chosen aim angle and curves according to the applied spin/lift
**And** a return with no aim input defaults to a straightforward reflection
**And** the ball never deals damage on contact with a ship — it is purely a resource-catch mechanic

### Story 1.3: Vitesse de balle croissante par échange

As a player,
I want the ball to speed up slightly with each successful rally exchange,
So that the tail end of a rally feels more intense.

**Acceptance Criteria:**

**Given** the ball has been successfully returned one or more times in the current rally
**When** each additional return occurs
**Then** the ball's base speed increases by a small fixed increment
**And** the speed resets to baseline at the start of a new rally (after a point is resolved)

### Story 1.4: Sélection d'arme sans bloquer le mouvement

As a player,
I want to select which weapon from my kit is active via a dedicated input,
So that I can switch weapons without interrupting my movement.

**Acceptance Criteria:**

**Given** the player's ship has a fixed weapon kit assigned
**When** the player presses the dedicated weapon-select input
**Then** the active weapon changes accordingly
**And** ship movement is never blocked or delayed by this input
**And** the currently selected weapon is visually indicated on the ship (minimal placeholder feedback acceptable at this stage)

### Story 1.5: Tir de l'arme sélectionnée, dégâts fixes

As a player,
I want to fire my currently selected weapon,
So that I can damage my opponent.

**Acceptance Criteria:**

**Given** a weapon is selected and has sufficient charge in its gauge
**When** the player presses the fire input
**Then** the weapon fires according to its fixed damage and fire-rate values (e.g. machine-gun ≈2 dmg at 4-6 shots/s)
**And** firing consumes the appropriate amount of the weapon's gauge
**And** firing with an empty gauge has no effect (no damage, no ammo consumed)

### Story 1.6: Balle ratée remplit la jauge adverse

As a player,
I want a missed ball return to fill my opponent's weapon gauge,
So that my mistakes create a real, visible risk without dealing me direct damage.

**Acceptance Criteria:**

**Given** the ball reaches a player's side without being returned
**When** the miss is resolved
**Then** the missing player takes no direct damage
**And** the opponent's currently selected weapon gauge is filled by a significant amount (equivalent to a full light-weapon charge)

### Story 1.7: Renvoi réussi remplit sa jauge, bonus trick shot

As a player,
I want a successful return to fill my own weapon gauge, with a bonus for stylish returns,
So that skillful play is directly rewarded with resources.

**Acceptance Criteria:**

**Given** the player successfully returns the ball
**When** the return is resolved
**Then** the player's currently selected weapon gauge fills by a standard amount
**And** if the return used a spin/lift/trick-shot modifier, an additional bonus fill is applied and displayed on-screen (e.g. a "+X%" popup)

### Story 1.8: Fenêtre de vulnérabilité sur arme lourde

As a player,
I want heavy weapons to leave me briefly vulnerable when fired,
So that using powerful weapons carries a real positioning risk.

**Acceptance Criteria:**

**Given** the player fires a heavy-tier weapon (e.g. bazooka-equivalent)
**When** the firing animation plays
**Then** the ship's mobility is reduced for the duration of a defined vulnerability window
**And** normal movement responsiveness resumes once the window ends
**And** light weapons (e.g. machine gun) do not trigger this vulnerability window

### Story 1.9: PV, format best-of-3, fin de round

As a player,
I want matches to follow a best-of-3 round format with a 100 HP pool,
So that matches have clear stakes and a satisfying structure.

**Acceptance Criteria:**

**Given** a match has started
**When** either player's HP reaches 0
**Then** the current round ends and is awarded to the other player
**And** a new round starts with both players reset to 100 HP, unless a player has already won 2 rounds
**And** the match ends when one player wins 2 rounds

### Story 1.10: HUD minimal — barre de PV + lisibilité des jauges

As a player,
I want to see my HP and weapon gauge state at a glance,
So that I can make informed decisions during a match.

**Acceptance Criteria:**

**Given** a match is in progress
**When** the player looks at the screen
**Then** an explicit HP bar is visible and updates in real time for both players
**And** the currently selected weapon's gauge/charge state is visibly indicated on the ship (minimal/functional version — e.g. a simple fill indicator; the final diegetic wear/gold-outline treatment from the GDD is deferred to a later art pass, not required for this story)

### Story 1.11: Match 1v1 local à deux joueurs

As two players sharing one device,
We want to play a full match against each other locally,
So that we can test the core loop head-to-head.

**Acceptance Criteria:**

**Given** two players are ready to play
**When** a local match is started
**Then** each player controls their own ship using a distinct local input scheme (e.g. separate keyboard zones or two gamepads)
**And** the full core loop (movement, ball, weapons, gauges, HP, rounds) functions correctly for both sides simultaneously

### Story 1.12: Adversaire IA basique/heuristique

As a solo player,
I want to play a local match against a basic AI opponent,
So that I can test and enjoy the core loop without needing a second human player.

**Acceptance Criteria:**

**Given** a solo match is started against the AI
**When** the ball approaches the AI's side
**Then** the AI attempts to reposition and return the ball using simple heuristics (e.g. move toward predicted ball position)
**And** the AI fires its selected weapon using basic reactive logic (e.g. fires when the opponent is roughly in range)
**And** the AI does not need to be balanced or highly skilled at this stage — it exists to make solo testing possible, not to be competitively tuned

---

## Epic 2: Roster jouable & variété d'armes

Le joueur peut choisir parmi les 8 personnages du roster complet, chacun avec son kit d'armes fonctionnel et distinct (dont tourelles à placement libre et effets de stun/mobilité).

**Composition du roster confirmée (2026-08-02) :**

| # | Archétype | Profil |
|---|---|---|
| 1 | Lourd | Gros dégâts, lent, forte vulnérabilité |
| 2 | Contrôleur | Tourelles à placement libre, zone control |
| 3 | Mitrailleur | Cadence élevée, dégâts unitaires faibles |
| 4 | Vif | Mobilité élevée, dégâts réduits |
| 5 | Zoneur/Précision | Arme laser, gros dégâts à distance, étroite/lente |
| 6 | Perturbateur | Arme boomerang, signature stun/setup (FR13) |
| 7 | Missiles téléguidés | Tracking fort, complexité élevée (référence Zangief) |
| 8 | Glass cannon "Mini" | Hitbox réduite, pleine puissance, très mobile mais fragile |

### Story 2.1: Modèle de données personnage

As a developer,
I want a data-driven character definition (Custom Resource),
So that adding or tuning a character never requires touching gameplay code.

**Acceptance Criteria:**

**Given** the project's data-driven architecture decision (Custom Resources for the roster)
**When** a character resource is created
**Then** it defines at minimum: id, display name, archetype label, weapon kit (ordered list of WeaponData references), and a complexity tier (beginner/intermediate/advanced, echoing the Zangief-style spread from the GDD)
**And** a ShipNode can load any character resource and use its kit exactly as it currently uses the shared placeholder kit — no code change required to add a 9th character later

### Story 2.2: Composition et définition des 8 personnages

As a player,
I want each of the 8 characters to have a distinct, functional weapon kit matching its archetype,
So that character choice is meaningful.

**Acceptance Criteria:**

**Given** the 8 archetypes confirmed above
**When** each character's data resource is authored
**Then** each has a kit of weapons consistent with its archetype description (e.g. the Lourd's kit leans toward high-damage/low-fire-rate weapons, the Mitrailleur's toward high-fire-rate/low-damage)
**And** every weapon referenced already exists as WeaponData (reuses Epic 1's machine_gun/bazooka pattern, extended with new weapon resources as needed per archetype)
**And** none of the 8 are required to be balanced against each other yet (NFR4/balance is explicitly out of this story's completion condition — see Epic 2's own note in the Epic List)

### Story 2.3: Sélection de personnage

As a player,
I want to choose which of the 8 characters I play as before a match starts,
So that I can pick a kit that matches how I want to play.

**Acceptance Criteria:**

**Given** the pre-match "ready?" gate (already implemented in Epic 1)
**When** each player selects a character before confirming ready
**Then** both players can independently choose any of the 8 characters (including choosing the same one)
**And** the chosen character's data resource determines that player's ShipNode kit for the match
**And** selection happens locally for both players on one screen (no networking involved — that's Epic 3)

### Story 2.4: Arme tourelle — placement libre et action autonome

As a player using a Contrôleur-archetype character,
I want to place a turret weapon freely on the arena,
So that I can control zones instead of aiming directly.

**Acceptance Criteria:**

**Given** the player has a turret-type weapon selected with sufficient gauge charge
**When** the player fires
**Then** a turret is placed at the ship's current position (or a short-range placement point) rather than firing a traveling projectile
**And** once placed, the turret fires autonomously at the opponent using its own basic targeting, with no further player input required
**And** the turret respects the same fixed-damage-per-hit model as other weapons (Story 1.5)

### Story 2.5: Effet boost de mobilité

As a player using a character with a mobility-boost weapon,
I want a weapon that temporarily increases my movement speed instead of dealing damage,
So that I have an indirect defensive/repositioning tool.

**Acceptance Criteria:**

**Given** the player fires a mobility-boost weapon with sufficient gauge
**When** the effect triggers
**Then** the player's movement speed is increased by a defined amount for a defined duration (mirroring the existing vulnerability-window pattern from Story 1.8, but as a buff instead of a debuff)
**And** the weapon deals no direct damage
**And** the effect is visually distinguishable from the normal movement state (reuse the existing tint-on-Visual pattern already used for vulnerability/lift charge)

### Story 2.6: Effet stun/setup

As a player using the Perturbateur character,
I want a weapon that briefly stuns my opponent,
So that I can follow up with a heavier hit.

**Acceptance Criteria:**

**Given** the player fires a stun-type weapon and it connects with the opponent
**When** the stun applies
**Then** the opponent's ability to fire and/or move is disabled for a short, fixed duration (~1 second, per the GDD's original combo-system note)
**And** the stunned player retains their HP and gauges unchanged — the stun only removes agency temporarily, it is not itself damage
**And** the stun is visually clear on the affected ship (distinct from the vulnerability/lift tints already in use)

### Story 2.7: Comportement IA adapté au kit de chaque personnage

As a solo player facing the AI,
I want the AI's behavior to reflect whichever character it's playing,
So that fighting the AI with any of the 8 characters feels meaningful (FR20).

**Acceptance Criteria:**

**Given** the AI is controlling a character with a specific archetype
**When** the AI makes movement and firing decisions
**Then** its behavior parameters reflect that archetype (e.g. a Lourd-piloting AI favors its preferred-depth/positioning differently than a Vif-piloting AI; a Contrôleur-piloting AI places turrets instead of just firing directly)
**And** this reuses the existing AI heuristic framework from Story 1.12 (wander, depth preference, lift attempts) rather than introducing a parallel AI system
**And** the AI remains deliberately unskilled overall (per FR19/FR20) — this story is about behavioral variety per character, not competitive tuning

## Epic 4: Campagne solo

Le joueur peut vivre une campagne narrative par personnage avec déblocages progressifs et un boss final, structurée à partir de la session de brainstorm du 2026-08-07 (voir `_bmad-output/brainstorming-session-2026-08-07.md` et son keepsake Party Mode).

**Décisions de design actées en brainstorm :**
- **Univers :** tournoi chaotique façon cartoon (ton Tenkaichi Budôkai/premier arc Dragon Ball) — un **organisateur-présentateur récurrent** invente les règles au fil du chaos et devient le boss final en piochant dans le kit de chaque personnage du roster.
- **Structure :** les 8 branches (une par perso) sont des **qualifications**, pas le tournoi lui-même — adversaires fixes à l'intérieur d'une branche, ordre libre entre branches. Chaque branche perso a 7 mini-branches rivales possibles (une par autre archétype), le joueur en complète 3-4 sur 7 (choix libre desquelles) pour débloquer l'acte final — ce qui force la rejouabilité de façon organique.
- **Mini-arc en 3 temps par mini-branche :** 2 combats contre des "sous-adversaires" (mooks, version mineure de l'archétype rival, rapportent Exp/Gold) → le "vrai" rival (rapporte un déblocage) → une **trace mécanique de l'adversaire vaincu** (façon Mega Man, mais une variante bonus inspirée du rival, pas son arme copiée — garde les 8 campagnes intactes).
- **Pool de twists de combat réutilisable** (7 entrées, une par "vrai" rival/boss, jamais de twist bespoke par combat — discipline de scope solo dev) : double/triple balle, jauge à plancher (miss adverse préservé), zone qui rétrécit (animée, garde-fou anti-sortie-de-cadre), invisibilité de l'adversaire, épines+rebond de balle, zone neutre mobile (même garde-fou), "double moi" (leurre visuel). Le boss a en plus son twist signature : billes d'énergie ramassables (+20% jauge).
- **Narration sans texte expositoire** (titres/noms acceptés, pas de pavés de lore) — tout passe par le visuel/l'environnement/l'animation.
- **Hors scope explicite :** un power meter façon shmup + arme unique par joueur (remplacerait le switch à 2 armes actuel) a été proposé puis explicitement mis de côté — touche FR9/FR4 du jeu de base, mérite sa propre session, pas décidé ici.

**FRs covered:** FR18
**Note :** dépend des Epics 1-2 (boucle + roster) ; palier aspirationnel post-MVP selon le GDD. Epic 3 (online) reste en pause — cette epic n'en dépend pas.

### Story 4.1: Modèle de données de campagne

As a developer,
I want data-driven campaign definitions (mini-branches, rivals, mooks, unlocks) as Custom Resources,
So that campaign content can be authored and tuned without touching gameplay code.

**Acceptance Criteria:**

**Given** the project's data-driven architecture decision, extended from the `CharacterData`/`WeaponData` pattern (Epic 2)
**When** a character's campaign is authored
**Then** each of the 8 characters has up to 7 associated mini-branch resources, each referencing two mook encounters (an archetype reference + a reduced-difficulty tier) and one "real" rival encounter (an archetype reference + a twist-pool entry id, Story 4.5)
**And** each mini-branch resource defines the unlock granted on rival victory — a bonus variant reference tied to the rival's identity, never a literal copy of the rival's own weapon
**And** the resource format supports a per-character "minimum mini-branches to unlock the final act" count (3-4 per the brainstorm), without hardcoding that count in gameplay code

### Story 4.2: Carte de campagne à embranchements

As a player,
I want a branching campaign map screen,
So that I can navigate a character's campaign the way the Soul Calibur IV reference established (UX-DR1).

**Acceptance Criteria:**

**Given** a character's campaign has been selected
**When** the map screen loads
**Then** it shows the character's mini-branch nodes, a stage-preview thumbnail per node, a chapter title, running Exp/Gold counters, and a description panel for the currently-selected node
**And** locked nodes render in silhouette/fog rather than being hidden outright — environmental storytelling over text, per the Constraint Injection insight from the brainstorm
**And** once the character's required number of mini-branches (Story 4.1) are completed, the final node (the organizer fight, Story 4.8) unlocks and becomes visible/selectable

### Story 4.3: Sélection de mini-branche

As a player,
I want to freely choose which of a character's 7 possible mini-branches to tackle, and in what order,
So that replaying a character's campaign can produce a different outcome each time.

**Acceptance Criteria:**

**Given** a character's campaign map (Story 4.2)
**When** the player selects an uncompleted mini-branch node
**Then** no other mini-branch's completion state is a prerequisite — the order across mini-branches is fully free
**And** once inside a mini-branch, its two mooks and its rival occur in a fixed, non-reorderable sequence — matches the brainstorm's resolution that opponents within a branch are never player-chosen, only which branch and in what order

### Story 4.4: Combat contre un sous-adversaire (mook)

As a player,
I want to fight a weaker "mook" version of an archetype before its "real" rival,
So that each mini-branch has pacing and build-up rather than being a flat gauntlet of full-strength duels.

**Acceptance Criteria:**

**Given** a mini-branch's first or second encounter (a mook)
**When** the match starts
**Then** the mook is AI-controlled using the target archetype's existing AI profile (Story 2.7), tuned down (e.g. reduced HP or a less aggressive `AI_PROFILES` entry) rather than via a new AI system
**And** victory grants Exp/Gold, tracked as campaign currency (Story 4.9) — not a weapon-trace unlock, which is reserved for the "real" rival (Story 4.6)
**And** losing does not end the campaign run permanently — the player can retry the encounter, consistent with a solo-dev-scale campaign with no permadeath

### Story 4.5: Système de twists de combat réutilisable

As a developer,
I want a reusable, data-driven "match twist" system,
So that the 7 validated battle-rule modifiers can be applied to any rival or boss encounter without bespoke per-fight code.

**Acceptance Criteria:**

**Given** the validated twist pool (double/triple ball, floored gauge regen, shrinking arena, opponent invisibility, spike-and-deflection hazards, drifting neutral zone, visual decoy)
**When** a mini-branch's rival encounter or the organizer fight references a twist by id
**Then** the match arena applies exactly that twist's configuration for the duration of the encounter, with no code changes required to unrelated systems
**And** each twist is a self-contained, independently testable configuration — extending `WeaponSystemState` for the gauge-floor twist (`self_fill_locked` + passive trickle, `MISS_GAUGE_FILL` untouched), treating `arena_bounds`/the neutral zone as functions of match time for the shrinking-arena and drifting-neutral-zone twists, a render-only toggle for invisibility and the visual decoy, and a `BallState`/`ShipState` hazard-zone extension for the spike/deflection twist
**And** the shrinking-arena and drifting-neutral-zone twists animate their transition over 1-2 seconds and never allow a ship to be pushed outside the (moving) legal bounds — the explicit edge-case guard raised in the brainstorm

### Story 4.6: Combat contre le "vrai" rival et déblocage

As a player,
I want to fight a mini-branch's "real" rival with a battle twist applied, and earn a bonus flavored by that rival,
So that finishing a mini-branch feels distinct and rewarding.

**Acceptance Criteria:**

**Given** the player has cleared both mooks in a mini-branch (Story 4.4)
**When** the rival encounter starts
**Then** it applies the mini-branch's assigned twist (Story 4.5) and the rival's own archetype/AI profile at full strength
**And** victory unlocks the mini-branch's defined bonus variant (Story 4.1) and marks the mini-branch completed in the campaign save (Story 4.9)
**And** the unlock reveal happens visually — the player's shield-of-orbs gains the new variant's color/orb — never via a stats popup or text, per the no-expository-text constraint from the brainstorm

### Story 4.7: Présence narrative de l'organisateur

As a player,
I want the tournament organizer to appear as a recurring, wordless presence throughout a campaign,
So that the campaign has a narrative throughline without needing a dialogue/text system.

**Acceptance Criteria:**

**Given** a mini-branch's rival encounter carries a twist (Story 4.5/4.6)
**When** the encounter begins
**Then** the arena telegraphs the twist environmentally before the fight starts (e.g. a visibly non-standard arena shape, a hazard already visible pre-fight) rather than via a text announcement
**And** the organizer's established visual/color motif is present on the campaign map itself (Story 4.2), with the map's palette shifting toward that motif as the player approaches the final node — the "chaos bleeding in" idea from Phase 2 of the brainstorm

### Story 4.8: Combat final contre l'organisateur

As a player,
I want a final campaign encounter against the tournament organizer that feels categorically different from every rival fight,
So that finishing a character's campaign has a real climax.

**Acceptance Criteria:**

**Given** a character's campaign has reached its required number of completed mini-branches (Story 4.1/4.3)
**When** the player enters the final node
**Then** the organizer's kit draws from multiple roster weapons rather than a single fixed kit, reflecting "he invented every rule"
**And** energy-orb pickups (+20% weapon gauge, reusing `WeaponSystemState.with_gauge_added()`) spawn periodically as the organizer's signature mechanic — not shared with the general twist pool (Story 4.5)
**And** victory completes that character's campaign run and is recorded in the campaign save (Story 4.9)

### Story 4.9: Sauvegarde de la progression de campagne

As a player,
I want my campaign progress saved locally,
So that I don't lose it between play sessions.

**Acceptance Criteria:**

**Given** the project's existing architecture decision (local JSON save, no cloud save in V1)
**When** the player completes a mook fight, a rival fight, or the organizer fight
**Then** the outcome (Exp/Gold total, completed mini-branches, unlocked bonus variants) is persisted to a local save file, per character
**And** relaunching the game restores the exact campaign state (map node states, currency, unlocks) from that file
**And** the save/load logic lives outside `simulation/` (per project-context.md, Règle absolue n°1) — it is orchestration, not deterministic gameplay simulation
