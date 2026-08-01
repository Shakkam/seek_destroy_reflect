---
stepsCompleted: [1, 2, 3]
note: 'Epic 1 fully detailed with stories and acceptance criteria. Epics 2-4 remain title/FR-level only, intentionally paused (2026-07-31) — Camil chose to move to implementation of the playable prototype (Epic 1) rather than complete all epics upfront. Resume story detailing for Epics 2-4 once the prototype is validated.'
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

This document provides the complete epic and story breakdown for Seek and Destroy and Reflect the Ball, decomposing the requirements from the GDD and Architecture (no separate UX Design document exists — UI/UX guidance lives inside the GDD's Art & Audio Direction section) into implementable stories.

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

_No separate UX Design document exists for this project. UI/UX guidance (diegetic HUD, art direction, readability principles) is captured directly in the GDD's "Art and Audio Direction" section and reflected in FR14/FR15 above._

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
