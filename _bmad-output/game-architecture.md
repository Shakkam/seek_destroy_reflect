---
title: 'Game Architecture'
project: 'seek and destroy and reflect the ball'
date: '2026-07-31'
author: 'Camil'
version: '1.0'
stepsCompleted: [1, 2, 3, 4, 5, 6, 7, 8, 9]
status: 'complete'
engine: 'Godot 4.7.1'
platform: 'PC, Console (mobile a l etude)'

# Source Documents
gdd: '_bmad-output/planning-artifacts/gdds/gdd-seek-and-destroy-and-reflect-the-ball-2026-07-31/gdd.md'
epics: '_bmad-output/planning-artifacts/gdds/gdd-seek-and-destroy-and-reflect-the-ball-2026-07-31/epics.md'
brief: '_bmad-output/planning-artifacts/briefs/brief-seek-and-destroy-and-reflect-the-ball-2026-07-30/brief.md'
---

# Game Architecture

## Executive Summary

L'architecture de **Seek and Destroy and Reflect the Ball** est conçue pour **Godot 4.7.1**, ciblant PC et Console (mobile à l'étude).

**Décisions architecturales clés :**
- **State Machine explicite par entité** (personnage, balle, match), orchestrée par un pattern novateur — le **Match Tick Resolver** — qui résout chaque tick de simulation dans un ordre fixe et déterministe, condition posée par le Party Mode pour ne pas fermer la porte à un futur rollback netcode.
- **Séparation stricte simulation/rendu dès le premier commit** (structure Hybride : `simulation/` en classes `RefCounted` pures, `nodes/` pour le Godot-natif), matérialisée physiquement dans l'organisation des dossiers — protège à la fois le futur netcode et un futur export console.
- **Roster et armes en Custom Resources Godot** (`.tres`), pattern natif et versionnable, avec un pont de sérialisation prévu pour les futurs tests d'équilibrage assistés par IA.

**Structure du projet :** organisation Hybride avec systèmes core cartographiés (simulation, nœuds, données, scènes, assets, core, debug, tests).

**Patterns d'implémentation :** 1 pattern novateur (Match Tick Resolver) + 4 patterns standards (communication, entité, état, données), tous documentés avec exemples de code.

**Prêt pour :** la phase de création des epics d'implémentation.

## Document Status

Architecture complète — 9/9 étapes réalisées via le workflow GDS Architecture.

---

## Project Context

### Game Overview

**Seek and Destroy and Reflect the Ball** — hybride Pong × Shoot'em Up × Fighting Game en 1v1 compétitif. Le trait distinctif est une double vigilance simultanée (balle façon Pong + combat façon fighting game) qui n'a pas de pattern architectural standard préexistant.

### Technical Scope

**Plateforme :** PC, Console (mobile non tranché)
**Genre :** Fighting (extension Shooter)
**Niveau du projet :** Solo dev, sans deadline, deux paliers de scope (prototype local → MVP complet avec online)

### Core Systems

| Système | Complexité | Référence GDD |
|---|---|---|
| Mouvement & contrôle | Basse-Moyenne | Mécaniques de jeu |
| Physique de balle (visée, spin/lift, couche séparée des tirs) | Moyenne | Mécaniques de jeu |
| Économie d'armes/jauges (dégâts fixes, cadence, vulnérabilité) | Moyenne | Mécaniques de jeu |
| Roster de personnages (8 kits fixes asymétriques) | Moyenne | Fighting Specific Design |
| **Netcode online (rollback recommandé, non tranché)** | **Haute** | Fonctionnalités compétitives |
| UI diégétique (usure/transparence/liseré doré, pas de HUD classique sauf PV) | Moyenne | Art & Audio |
| Campagne solo (déblocages, embranchements, carte du monde) | Moyenne | Modes solo |
| Tests d'équilibrage assistés par IA (simulation agent-vs-agent) | Moyenne (outillage) | Roster |

### Technical Requirements

- Framerate cible : **30 FPS verrouillés/stables** — la stabilité du timing prime sur le chiffre brut.
- Multijoueur : local dès le prototype ; online 1v1 (quick-match, sans ranked au lancement) pour le palier MVP complet.
- Architecture réseau : rollback recommandé par convention de genre, non tranché formellement à ce stade.

### Complexity Drivers

**Haute complexité :**
- Netcode rollback pour un jeu combinant simulation de personnages ET un objet balle à physique continue (spin/lift) — combinaison sans pattern standard préexistant (la plupart des références traitent l'un ou l'autre séparément, rarement les deux synchronisés ensemble).
- Moteur non tranché, à construire dans ce document plutôt qu'une contrainte préexistante.

**Concepts novateurs :**
- Combinaison "objet balle physique partagé + rollback netcode + roster asymétrique" — nécessite une discipline de simulation déterministe dès le prototype, pas seulement au moment d'ajouter le online.

**Risques techniques (issus du GDD) :** modèle de netcode ouvert, structure des jauges (partagée/par arme) à valider par prototype, fenêtres de vulnérabilité par arme non chiffrées.

**Insight du Party Mode (2026-07-31) :** le risque du rollback netcode n'est pas éliminatoire pour un solo dev — la clé est de structurer la boucle de simulation (mouvement, balle, dégâts) comme une **fonction pure et déterministe dès le prototype local** (`update(state, input) -> new_state`, découplée du rendu, sans dépendance cachée au framerate réel ou au hardware). Codée ainsi dès le mois 1, le netcode rollback devient une couche ajoutée plus tard plutôt qu'une réécriture complète du moteur physique. Cette contrainte de conception (contrôle sur la boucle de update, déterminisme) doit peser dans le choix du moteur à l'étape suivante — favoriser un moteur qui laisse la main sur la boucle de simulation plutôt qu'un qui l'abstrait trop.

## Engine & Framework

### Selected Engine

**Godot 4** v4.7.1 (dernière stable, 14 juillet 2026)

**Rationale :** pipeline 2D natif et optimisé (pas un patch sur un moteur pensé pour la 3D, contrairement à Unity), licence MIT gratuite sans risque de royalties (aligné avec le budget solo/perso), GDScript accessible pour une reprise en main en douceur après une longue pause de code (C# disponible si préférence future), écosystème d'addons de rollback netcode actif et maintenu (godot-rollback-netcode de Snopek Games + son fork GDExtension "Delta Rollback"), et surtout : Godot laisse la main sur la boucle de simulation plutôt que de trop l'abstraire — condition posée par le Party Mode pour garder le déterminisme sous contrôle en vue d'un futur rollback.

**Validé en Party Mode (2026-07-31)**, avec deux garde-fous explicites à respecter dans les décisions d'architecture qui suivent :

1. **Séparation stricte logique de jeu / rendu / input dès le premier commit** — pour ne pas compromettre un futur export console (l'export console sur Godot n'est pas aussi immédiat/gratuit que sur PC : passe par un partenaire agréé type W4 Games ou l'obtention de templates officiels Nintendo/Sony/Microsoft). Tant que la logique reste découplée, le portage console reste un problème de *build pipeline*, pas de réécriture du jeu.
2. **Le rollback netcode doit être traité comme une phase de recherche/prototypage à part entière** quand le projet y arrivera — l'écosystème d'addons est communautaire et actif, pas un service premium garanti type GGPO officiel. Pas disqualifiant pour un projet perso sans deadline, mais pas à sous-estimer non plus.

### Engine-Provided Architecture

| Composant | Solution | Notes |
|---|---|---|
| Rendu | Pipeline 2D natif Godot (Vulkan) | Optimisé pixel-perfect, adapté au pixel art visé |
| Physique | Moteur physique 2D Godot 4 (réécrit) | À utiliser avec discipline déterministe pour la balle/mouvement (voir garde-fous) |
| Audio | AudioStreamPlayer natif Godot | Suffisant pour la direction metal/électro prévue |
| Input | InputMap natif Godot | Gère nativement clavier/manette, utile pour PC + Console à terme |
| Gestion de scènes | Scene tree / noeuds Godot | Adapté à un roster de personnages modulaire |
| Build system | Godot export templates | Natif PC ; export console nécessite un partenaire agréé (voir garde-fou 1) |

### Remaining Architectural Decisions

Ces décisions restent à trancher explicitement dans la suite de ce document :
- Structure du projet et organisation du code (séparation simulation/rendu/input)
- Modèle de netcode précis (quel addon rollback, structure de synchronisation)
- Système de données pour le roster (Resources Godot vs. fichiers de config externes)
- Gestion d'état (state machine pour les personnages, la balle, les matchs)
- Stratégie de test automatisé (incl. simulation agent-vs-agent pour l'équilibrage IA)

### Project Initialization

Départ d'un **projet Godot vide** plutôt qu'un starter template générique — l'architecture sur mesure (séparation stricte simulation/rendu/input) serait en tension avec la structure imposée par un starter existant.

**Référence à étudier (pas un starter à forker) :** [Godot-Rollback-Fighter-Demo](https://github.com/blast-harbour/Godot-Rollback-Fighter-Demo) (blast-harbour) — démontre des mécaniques de fighting game avec l'addon de rollback "Delta Rollback" sur Godot 4.2.2. À consulter au moment d'attaquer le netcode, pour la structuration des states/animations/sérialisation.

### AI Development Tools (MCP)

**MCP recommandé :** [GoPeak (HaD0Yun/Gopeak-godot-mcp)](https://github.com/HaD0Yun/Gopeak-godot-mcp) — serveur MCP open-source (~95 outils couvrant édition-exécution-inspection de l'éditeur Godot). Gratuit, licence ouverte, tourne en local via Node.js — aucun abonnement.

**Complément recommandé :** Context7 (upstash/context7) pour un accès à jour à la documentation Godot, indépendant du moteur.

**Statut :** intégration acceptée par Camil (2026-07-31).

## Architectural Decisions

### Decision Summary

| Catégorie | Décision | Rationale |
|---|---|---|
| Gestion d'état | State Machine explicite par entité (personnage, balle, match) | Soutient directement le garde-fou déterministe (`update(state, input) -> new_state`) ; ECS jugé trop complexe pour la V1 solo, mais migration future possible |
| Structure du projet | Hybride — nœuds Godot légers déléguant à des classes `RefCounted` pures pour la logique | Seule option respectant le garde-fou "simulation pure dès le premier commit" sans sacrifier l'ergonomie Godot |

### State Management

**Approche :** State Machine explicite, une par entité simulée (personnage, balle, état de match). Toute la logique de transition est contenue dans une fonction pure `update(state, input) -> new_state`, sans effet de bord ni dépendance au rendu ou au framerate réel. Pas d'ECS complet en V1 — complexité jugée disproportionnée pour un solo dev en reprise de code, mais l'architecture reste migrable vers ECS si le roster/les systèmes grandissent significativement post-MVP.

### Project Structure

**Approche :** Hybride. Les nœuds de scène Godot (`CharacterBody2D`, etc.) restent fins — ils gèrent le rendu, la capture d'input, et l'audio — et délèguent toute la logique de jeu (mouvement, physique de balle, dégâts, jauges) à des classes `RefCounted` pures et testables indépendamment de l'arbre de scène. C'est ce qui permet de respecter le garde-fou du Party Mode (simulation découplée dès le premier commit) sans réinventer les patterns natifs de Godot.

### Data-Driven Roster System

**Approche :** Custom Resources Godot (`.tres`) — un fichier ressource par personnage et par arme, éditable directement dans l'inspecteur Godot. Pattern natif et standard (confirmé par la documentation Godot 4), lisible et versionnable en Git (format texte). Un pont de sérialisation léger sera nécessaire si les futurs tests d'équilibrage IA doivent générer/lire ces données par script externe — détail d'implémentation, pas un blocage architectural.

### Asset Management

**Stratégie de chargement :** Scene-based — chargement par scène (arène, écrans de sélection). Volume d'assets modeste en V1 (8 personnages, une arène pixel art) ; le streaming serait de la sur-ingénierie à cette échelle.

### Scene Structure

Une scène de match générique (arène + emplacements de personnages) instanciant dynamiquement les 2 personnages sélectionnés, plutôt qu'une scène figée par matchup — évite une explosion combinatoire (8×8 = 64 combinaisons possibles).

### Data Persistence

**Système de sauvegarde :** fichier local JSON/binaire pour les réglages (contrôles, options) et, une fois la campagne développée, la progression/déblocages. Pas de cloud save en V1 — aucun compte joueur ni backend prévu à ce stade.

### Architecture Decision Records

1. **State Machine par entité plutôt qu'ECS** — priorité au déterminisme et à la simplicité pour un solo dev, migration ECS possible plus tard si nécessaire.
2. **Séparation simulation/rendu dès le premier commit** — condition posée par le Party Mode pour ne pas compromettre un futur export console ni un futur rollback netcode.
3. **Custom Resources pour le roster** — pattern Godot standard, lisible et versionnable, avec un pont de sérialisation à prévoir pour les tests d'équilibrage IA.
4. **Pas de cloud save / pas de backend en V1** — cohérent avec l'absence d'ambition multijoueur online dès le palier prototype.

## Cross-cutting Concerns

Ces patterns s'appliquent à TOUS les systèmes et doivent être suivis par toute implémentation, humaine ou IA.

### Error Handling

**Stratégie :** Signal/Event Based pour les erreurs de gameplay récupérables (état invalide détecté en cours de match), combiné à des **Result Objects** pour les fonctions de simulation pures — `update(state, input)` retourne toujours soit un état valide, soit une erreur explicite typée, jamais d'exception silencieuse. Rien ne doit interrompre le jeu en match ; les erreurs de gameplay sont loguées et gérées en dégradé. Seules les erreurs critiques au chargement (ressource manquante, etc.) peuvent bloquer.

### Logging

**Format :** texte simple avec préfixe de niveau (`[ERROR]`, `[WARN]`, `[INFO]`, `[DEBUG]`, `[TRACE]`).
**Destination :** console en développement, fichier local en dehors.
**Niveaux :** DEBUG/TRACE désactivés par défaut hors développement actif — le projet tourne principalement en local sur la machine du créateur en V1.

### Configuration

Trois couches :
1. **Constantes en dur** pour les valeurs qui ne changent jamais (ex. formules de calcul de dégâts)
2. **Custom Resources Godot** pour les valeurs d'équilibrage (roster/armes — voir Data-Driven Roster System)
3. **Fichier JSON local** pour les réglages joueur (contrôles, options — voir Data Persistence)

### Event System

**Pattern :** Signal/Slot natif Godot, typé. Pattern natif du moteur, performant, suffisant pour découpler les systèmes (ex. "arme tirée" déclenchant la mise à jour du HUD sans couplage direct).

### Debug Tools

Mode debug activable par raccourci clavier dédié, incluant : affichage des hitboxes/hurtboxes, overlay de l'état des jauges/armes, et un mode permettant de forcer des scénarios de test (matchup personnage X vs Y, PV personnalisés). Utile pour le développement solo et réutilisable pour les futurs tests d'équilibrage assistés par IA (voir GDD).

## Project Structure

### Organization Pattern

**Pattern :** Hybride — types de fichiers en surface (`simulation/`, `nodes/`, `data/`, `scenes/`, `assets/`), domaines de jeu à l'intérieur de chacun. Choisi pour matérialiser physiquement, au niveau des dossiers, la frontière simulation/rendu posée comme garde-fou en Party Mode.

### Directory Structure

```
seek_and_destroy_and_reflect_the_ball/
├── simulation/              # Logique pure, RefCounted, sans dépendance à la scène
│   ├── ship_state.gd            # State Machine du vaisseau (mouvement, PV, esquive)
│   ├── ball_state.gd            # State Machine de la balle (position, spin, vitesse)
│   ├── match_state.gd           # État global du match (round, score, timer)
│   ├── weapon_resolver.gd       # Résolution des dégâts/cadence/vulnérabilité
│   └── gauge_system.gd          # Remplissage/dépense des jauges d'armes
├── nodes/                   # Nœuds Godot fins (rendu, input, audio)
│   ├── ship_node.gd              # CharacterBody2D — délègue à ship_state
│   ├── ball_node.gd              # Délègue à ball_state
│   └── hud_node.gd               # HUD PV + éléments diégétiques (usure, liseré doré)
├── data/                    # Custom Resources (.tres)
│   ├── characters/               # Un .tres par personnage (8 fichiers)
│   └── weapons/                  # Un .tres par arme
├── scenes/
│   ├── match_arena.tscn          # Scène de match générique
│   ├── character_select.tscn
│   └── main_menu.tscn
├── assets/
│   ├── art/
│   │   ├── characters/
│   │   ├── vfx/                  # Effets spectaculaires (pilier art direction)
│   │   └── ui/
│   └── audio/
│       ├── music/                # Compositions metal/électro
│       └── sfx/
├── core/                    # Managers globaux (autoloads Godot)
│   ├── event_bus.gd              # Signal/Slot centralisé
│   └── save_manager.gd           # Sauvegarde JSON locale
├── debug/                   # Outils de debug (hitbox overlay, forçage de scénarios)
├── tests/                   # Tests de la couche simulation (isolée, sans Godot)
└── docs/
```

### System Location Mapping

| Système | Emplacement | Responsabilité |
|---|---|---|
| Mouvement, PV, esquive du vaisseau | `simulation/ship_state.gd` | Logique pure, déterministe |
| Physique de balle (visée, spin/lift) | `simulation/ball_state.gd` | Logique pure, déterministe |
| Dégâts, cadence, fenêtres de vulnérabilité | `simulation/weapon_resolver.gd` | Logique pure |
| Jauges d'armes | `simulation/gauge_system.gd` | Logique pure |
| Rendu et input des vaisseaux | `nodes/ship_node.gd` | Délègue à `simulation/`, gère Godot |
| Roster et armes (données) | `data/characters/`, `data/weapons/` | Custom Resources `.tres` |
| HUD (PV explicite + éléments diégétiques) | `nodes/hud_node.gd` | Lecture d'état, pas de logique de jeu |
| Communication inter-systèmes | `core/event_bus.gd` | Signal/Slot typé |
| Sauvegarde | `core/save_manager.gd` | JSON local |
| Outils de debug | `debug/` | Hitboxes, forçage de scénarios |
| Tests de simulation | `tests/` | Isolés de Godot |

### Naming Conventions

**Fichiers :**
- Scripts : `snake_case.gd` (convention native GDScript)
- Scènes : `PascalCase.tscn` pour les scènes principales, `snake_case.tscn` pour les composants
- Assets : `snake_case` descriptif (ex. `ship_idle_01.png`)

**Éléments de code :**

| Élément | Convention | Exemple |
|---|---|---|
| Classes | PascalCase | `ShipState`, `WeaponResolver` |
| Fonctions | snake_case | `update_state()`, `resolve_damage()` |
| Variables | snake_case | `current_hp`, `gauge_fill` |
| Constantes | UPPER_SNAKE_CASE | `MAX_HP`, `MATCH_DURATION_SECONDS` |

**Spécifique au jeu :**
- Signaux : verbe au passé (`weapon_fired`, `ball_returned`, `gauge_filled`)
- Ressources de personnage/arme : `snake_case` correspondant au nom du personnage/arme (ex. `heavy_01.tres`, `machine_gun.tres`)

### Architectural Boundaries

**Règle absolue (à faire respecter par tout agent IA qui implémente du code) :** rien dans `simulation/` ne doit référencer un nœud Godot, une scène, ou du rendu. C'est la garantie physique, au niveau des dossiers, du garde-fou déterministe posé en Party Mode — nécessaire pour ne pas compromettre un futur export console ni un futur rollback netcode.

## Implementation Patterns

Ces patterns garantissent une implémentation cohérente, quel que soit l'agent (humain ou IA) qui écrit le code.

### Novel Patterns

#### Match Tick Resolver

**Objet :** résoudre chaque tick de simulation — mouvement, physique de balle, tirs — dans un ordre fixe et déterministe, condition nécessaire à un futur rollback netcode et au cœur de la "double vigilance" (balle + combat jamais résolus arbitrairement l'un avant l'autre sans règle explicite).

**Composants :**
- `MatchState` — orchestrateur, appelle les sous-systèmes dans un ordre fixe et documenté
- `ShipState` × 2 — état de chaque vaisseau
- `BallState` — état de la balle
- `WeaponResolver` — résolution des tirs actifs

**Flux de données (par tick, ordre fixe) :**
1. Lecture des inputs des deux joueurs (capturés en amont par `nodes/`)
2. `ShipState.update()` pour chaque joueur → nouvelle position/état
3. `BallState.update()` → nouvelle position de la balle, dépend des positions de vaisseaux déjà mises à jour (jamais l'inverse, pour éviter les dépendances circulaires)
4. `WeaponResolver.resolve()` → dégâts/jauges appliqués, à partir des états déjà figés aux étapes 2-3
5. `MatchState` agrège le tout en un `MatchSnapshot` immuable pour ce tick

**Exemple d'implémentation :**

```gdscript
# simulation/match_state.gd
func tick(inputs: Dictionary) -> MatchSnapshot:
    var ship_a = ship_state_a.update(inputs.player_a)
    var ship_b = ship_state_b.update(inputs.player_b)
    var ball = ball_state.update(ship_a, ship_b)
    var resolution = weapon_resolver.resolve(ship_a, ship_b, ball)
    return MatchSnapshot.new(ship_a, ship_b, ball, resolution)
```

**Usage :** tout agent qui ajoute un nouveau système de simulation doit l'insérer à l'étape appropriée de cette séquence fixe, jamais en parallèle non ordonné — c'est ce qui rend le tick reproductible bit-à-bit.

### Communication Patterns

**Pattern :** Event-based, Signal/Slot typé natif Godot (décidé en Cross-cutting Concerns). Utilisé pour découpler les systèmes de simulation des nœuds de présentation (ex. `weapon_fired` déclenchant une mise à jour visuelle du HUD sans que `simulation/` ne connaisse `nodes/`).

### Entity Patterns

**Création :** instanciation de scène pilotée par `MatchState`, alimentée par les Custom Resources du roster (décidé en Data-Driven Roster System). Pas de pooling d'objets en V1 — volume d'entités trop faible (2 vaisseaux, 1 balle, quelques projectiles) pour que ce soit nécessaire.

### State Patterns

**Pattern :** State Machine explicite par entité (décidé en Architectural Decisions), orchestrée par le Match Tick Resolver ci-dessus.

### Data Patterns

**Accès :** Resources/Autoload natif Godot (décidé en Data-Driven Roster System) — le roster et les armes sont chargés comme Custom Resources, référencés par les scènes de personnage.

### Consistency Rules

| Pattern | Convention | Enforcement |
|---|---|---|
| Ordre de résolution du tick | Fixe : inputs → ships → ball → weapons → snapshot | Revue de code manuelle + tests de simulation isolés |
| Frontière simulation/rendu | `simulation/` ne référence jamais Godot | Structure de dossier + revue de code |
| Nommage des signaux | Verbe au passé (`weapon_fired`) | Convention de nommage (voir Project Structure) |
| Données de personnage/arme | Toujours via Custom Resources, jamais en dur dans le code | Revue de code manuelle |

## Architecture Validation

### Validation Summary

| Check | Result | Notes |
|---|---|---|
| Decision Compatibility | Pass | Moteur, patterns, cross-cutting et structure s'articulent sans contradiction |
| GDD Coverage | Pass avec réserves assumées | Netcode et campagne intentionnellement différés (voir Coverage Report) |
| Pattern Completeness | Pass | Entity creation, communication, state, error handling, data access, event handling tous définis avec exemples |
| Epic Mapping | Pass avec réserves assumées | Epics 1, 2, 5 prêts ; Epic 3 (online) partiel par choix ; Epic 4 (campagne) non architecturé, cohérent avec le scope post-MVP |
| Document Completeness | Pass | Toutes les sections obligatoires présentes, versions vérifiées, aucun placeholder |

### Coverage Report

**Systèmes couverts :** 6/8 systèmes identifiés en Project Context entièrement couverts (mouvement, balle, armes/jauges, roster, UI diégétique, cross-cutting) ; 2 différés volontairement (netcode précis, campagne).
**Patterns définis :** 1 pattern novateur (Match Tick Resolver) + 4 patterns standards (communication, entité, état, données).
**Décisions prises :** 6 décisions architecturales majeures, toutes documentées avec rationale.

### Issues Resolved / Assumées

- **Netcode online** : modèle précis (structure exacte de synchronisation, choix entre l'addon Snopek Games et son fork GDExtension) non tranché ici — traité comme une phase de recherche/prototypage à part entière par décision explicite du Party Mode, pas un oubli.
- **Mode Campagne** : aucun modèle de données défini dans cette passe d'architecture — cohérent avec son statut post-MVP dans le GDD (Epic 4). À reprendre lors d'une future itération de ce document une fois le palier MVP complet amorcé.
- **Pipeline de tests d'équilibrage IA** : `debug/` prévoit le forçage de scénarios de test manuels, mais pas de pipeline agent-vs-agent automatisé — relève explicitement de `gds-test-design`/`gds-test-automate`, hors scope de ce document d'architecture.

Camil a confirmé (2026-07-31) accepter ces réserves telles quelles plutôt que de les traiter maintenant.

### Validation Date

2026-07-31

## Development Environment

### Prerequisites

- **Godot 4.7.1** (dernière stable, éditeur avec support .NET optionnel si besoin de C# plus tard)
- **Git** pour le versioning (déjà en place — projet poussé sur GitHub)
- **Node.js** (requis pour faire tourner le serveur MCP GoPeak en local)

### AI Tooling (MCP Servers)

Le serveur MCP suivant a été retenu durant l'architecture pour renforcer le développement assisté par IA :

| Serveur MCP | Usage | Type d'installation |
|---|---|---|
| [GoPeak (HaD0Yun/Gopeak-godot-mcp)](https://github.com/HaD0Yun/Gopeak-godot-mcp) | Inspection de scènes, création de nœuds, lecture des logs Godot en direct (~95 outils) | Serveur Node.js local, gratuit, licence ouverte |

**Complément recommandé :** Context7 (upstash/context7) pour un accès à jour à la documentation Godot.

Ces outils donnent à Claude Code un accès direct à l'éditeur Godot — inspection de scènes et assets réels plutôt que des descriptions, génération de code consciente du contexte du projet.

### Setup Commands

```bash
# 1. Installer Godot 4.7.1 depuis godotengine.org
# 2. Créer le projet vide dans Godot (nom : seek_and_destroy_and_reflect_the_ball)
# 3. Installer le serveur MCP GoPeak
git clone https://github.com/HaD0Yun/Gopeak-godot-mcp.git
cd Gopeak-godot-mcp && npm install && npm run build
# 4. Configurer le client MCP (Claude Code) pour pointer vers le serveur construit
```

### First Steps

1. Initialiser le projet Godot vide avec la structure de dossiers définie (voir Project Structure)
2. Créer les premières Custom Resources pour 1-2 personnages de test (pas les 8 tout de suite)
3. Configurer le serveur MCP GoPeak (voir AI Tooling ci-dessus)
4. Implémenter le Match Tick Resolver avec `ShipState` et `BallState` minimaux — c'est le cœur de l'Epic 1 (Prototype du Core Loop)
