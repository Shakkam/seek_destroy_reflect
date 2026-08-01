---
project_name: 'seek and destroy and reflect the ball'
user_name: 'Camil'
date: '2026-07-31'
sections_completed: ['technology_stack', 'engine_rules', 'performance_rules', 'organization_rules', 'testing_rules', 'platform_rules', 'anti_patterns']
status: 'complete'
rule_count: 9
optimized_for_llm: true
---

# Project Context for AI Agents

_Ce fichier contient les règles critiques que tout agent IA doit suivre pour implémenter du code sur ce projet. Focus sur les détails non-évidents, pas sur des rappels génériques._

---

## Technology Stack & Versions

- **Moteur :** Godot **4.7.1** (dernière stable au 2026-07-31)
- **Langage principal :** GDScript (C# disponible si besoin futur, non utilisé actuellement)
- **Plateformes cibles :** PC, Console (mobile à l'étude, non engagé)
- **MCP dev tool :** GoPeak (HaD0Yun/Gopeak-godot-mcp) — donne un accès direct à l'éditeur Godot

## Critical Implementation Rules

### Règle absolue n°1 — Frontière simulation/rendu

**Rien dans `simulation/` ne doit jamais référencer un `Node`, une scène, ou quoi que ce soit de Godot.** `simulation/` contient exclusivement des classes `RefCounted` pures (state machines : `ShipState`, `BallState`, `MatchState`, résolveurs : `WeaponResolver`, `GaugeSystem`). Les nœuds Godot dans `nodes/` (ex. `ship_node.gd`) sont fins : ils gèrent rendu/input/audio et **délèguent** à `simulation/`, jamais l'inverse.

**Pourquoi c'est critique :** cette séparation est la condition posée en Party Mode pour ne pas fermer la porte à un futur rollback netcode (simulation déterministe) ni à un futur export console (portabilité du build pipeline). Un agent qui code de la logique de jeu directement dans un `CharacterBody2D` casse cette garantie silencieusement.

### Règle absolue n°2 — Ordre de résolution du tick (Match Tick Resolver)

Chaque tick de simulation doit résoudre les systèmes dans cet ordre fixe, jamais en parallèle non ordonné :
1. Lecture des inputs des deux joueurs
2. `ShipState.update()` pour chaque joueur
3. `BallState.update()` — dépend des positions de vaisseaux déjà mises à jour à l'étape 2, **jamais l'inverse**
4. `WeaponResolver.resolve()` — dépend des états figés aux étapes 2-3
5. Agrégation en `MatchSnapshot` immuable

Tout nouveau système de simulation doit s'insérer à l'étape appropriée de cette séquence. Ne pas court-circuiter l'ordre pour "optimiser" — c'est ce qui rend le tick reproductible bit-à-bit (prérequis rollback).

### Gestion d'état

State Machine explicite **par entité** (une pour le vaisseau, une pour la balle, une pour le match) — pas d'ECS en V1 (jugé trop complexe pour ce stade solo dev). Toute logique de transition passe par une fonction pure `update(state, input) -> new_state`, sans effet de bord, sans lecture de `Time.get_ticks_msec()` ou d'autre source non-déterministe dans `simulation/`.

### Données de personnages et d'armes

**Toujours** via Custom Resources Godot (`.tres`) dans `data/characters/` et `data/weapons/` — **jamais** de stats en dur dans le code (pas de `damage = 10` codé dans une classe). Chaque personnage a un kit fixe de 3-4 armes connu dès le début du match (pas de déblocage aléatoire en cours de partie).

**Ancrages numériques de référence** (issus du GDD, à respecter sauf changement explicite) :
- PV : 100 par personnage
- Dégâts : mitraillette ≈2/tir à 4-6 tirs/s, bazooka ≈10/tir, super ≈20-30/tir
- Balle ratée : remplit la jauge adverse (jamais de dégât direct — la balle ne fait JAMAIS de dégâts)

### Communication inter-systèmes

Signal/Slot natif Godot, **typé**. Nommage des signaux : verbe au passé (`weapon_fired`, `ball_returned`, `gauge_filled`). Ne pas utiliser de chaînes de caractères non typées pour les signaux critiques au gameplay.

### Performance

- **Framerate cible : 30 FPS verrouillés/stables** — pas un minimum, une cible fixe. La stabilité du timing prime sur un framerate plus élevé variable, car les fenêtres de vulnérabilité et le timing de riposte sont du gameplay.
- Pas de pooling d'objets requis en V1 (volume d'entités trop faible : 2 vaisseaux, 1 balle, quelques projectiles) — ne pas sur-ingénierer.

### Organisation du code

- Scripts : `snake_case.gd`
- Classes : `PascalCase` (`ShipState`, `WeaponResolver`)
- Fonctions/variables : `snake_case`
- Constantes : `UPPER_SNAKE_CASE`
- Voir `_bmad-output/game-architecture.md` section "Project Structure" pour l'arborescence complète des dossiers (`simulation/`, `nodes/`, `data/`, `scenes/`, `assets/`, `core/`, `debug/`, `tests/`).

### Tests

Les tests de la couche `simulation/` doivent rester isolés de Godot (pas de dépendance à l'arbre de scène) — c'est justement ce que permet la séparation stricte. `debug/` fournit un mode de forçage de scénarios (matchup X vs Y, PV custom) réutilisable pour les futurs tests d'équilibrage IA (hors scope de ce document — voir `gds-test-design`).

### Plateformes & anti-patterns

- **Export console :** pas immédiat/gratuit sur Godot (passe par un partenaire agréé type W4 Games ou des templates officiels constructeur). Ne jamais coupler la logique de jeu à des hypothèses spécifiques PC dans `simulation/` — c'est déjà couvert par la Règle n°1, mais à garder en tête lors de l'implémentation de l'input/rendu.
- **Netcode rollback :** modèle précis non tranché (traité comme une phase de recherche à part entière, pas une intégration plug-and-play). Ne pas commencer à intégrer un addon de rollback sans une discussion dédiée au préalable — le prototype local (Epic 1) n'en a pas besoin.
- **Ne jamais** utiliser de nombres flottants dépendants du hardware/framerate réel dans `simulation/` — c'est ce qui casserait le déterminisme nécessaire à un futur rollback.

---

## Usage Guidelines

**Pour les agents IA :**
- Lire ce fichier avant d'implémenter du code de jeu
- Suivre TOUTES les règles exactement telles que documentées
- En cas de doute, préférer l'option la plus restrictive (ex. privilégier la séparation simulation/rendu plutôt qu'un raccourci pratique)
- Signaler si un nouveau pattern émerge qui mériterait d'être ajouté ici

**Pour Camil :**
- Garder ce fichier condensé, focalisé sur les besoins des agents
- Mettre à jour si la stack technique ou les patterns évoluent (ex. une fois le netcode tranché)
- Revoir périodiquement pour retirer les règles devenues évidentes

Dernière mise à jour : 2026-07-31
