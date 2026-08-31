---
name: shakkam-cartography-map-format
description: 'Le format de carte de campagne (PNG + JSON) exporté par l''Atelier Cartographe pour Seek and Destroy and Return the Ball : ce que chaque type de case veut dire, comment il se branche dans campaign_map_node.gd, et les invariants à vérifier avant d''intégrer une carte. Use when reading, validating, or wiring a campaign_map PNG+JSON export, or when asked about case types (mook/miniboss/boss/bonus) on the world map.'
---

# Format de carte — Atelier Cartographe → Seek and Destroy and Return the Ball

## D'où vient une carte

L'outil "Atelier Cartographe" (artifact Claude, et son miroir déployé sur
https://pix-map.vercel.app / https://github.com/Shakkam/pix-map) exporte
une paire de fichiers pour un personnage donné :

- **`<perso>_map.png`** — le fond visuel complet (terrain, chemin, décor,
  icônes de case) à la résolution native **1280×720**, tout est déjà cuit
  dans l'image. Rien à redessiner par-dessus, sauf de petits indicateurs de
  statut (voir plus bas).
- **`<perso>_map.json`** — la structure de la carte avec la liste des cases,
  les nœuds de relais, et les arêtes de connexion (voir schéma ci-dessous).

## Schéma JSON — format graphe (2026-08-31)

```json
{
  "width": 1280, "height": 720,
  "character": "mitrailleur",
  "branch_count": 6,
  "case_type_labels": { "mook": "Case Mook", "miniboss": "Case Miniboss (rival)", "boss": "Case Boss (organisateur)", "custom_bonus": "bonus", "custom_depart": "départ" },
  "cases": [
    { "id": "i669", "index": 0, "type": "miniboss", "x": 480, "y": 480 },
    { "id": "i566", "index": 23, "type": "custom_depart", "x": 224, "y": 416 }
  ],
  "path_nodes": [
    { "id": "i745", "x": 224, "y": 352 }
  ],
  "connections": [
    ["i566", "i745"], ["i589", "i745"]
  ]
}
```

### Trois types d'objets

- **`cases`** : toutes les cases nommées de la carte. Chaque case a :
  - `id` : identifiant stable unique (ex. `"i669"`)
  - `index` : ordre pour l'assignation des rencontres (pool) — tri croissant
  - `type` : `"mook"`, `"miniboss"`, `"boss"`, `"custom_depart"`, `"custom_bonus"`, ou autre type custom
  - `x`, `y` : position en pixels dans le PNG 1280×720

- **`path_nodes`** : nœuds de RELAIS — purs waypoints de traversée, aucune
  logique de combat. Chaque relais a `id`/`x`/`y` (pas de `type` ni d'`index`).
  Type effectif = `""` (chaîne vide) dans le moteur.

- **`connections`** : liste de paires `[idA, idB]` référençant indifféremment
  des `id` de `cases` ou de `path_nodes` — arêtes NON-DIRIGÉES du graphe de
  déplacement. Le moteur construit la liste d'adjacence symétrique.

### Détection du mode graphe

Le moteur détecte automatiquement le mode graphe si le JSON possède
à la fois `path_nodes` ET `connections` (ET `cases`). Sans ces champs,
le JSON reste en mode linéaire (séquence plate, ancien format).

## Ce que veut dire chaque type de case

- **`mook`** — un combat simple (adversaire affaibli).
- **`miniboss`** — un combat contre l'un des rivaux.
- **`boss`** — le combat final de cette carte, contre l'organisateur. Victoire
  sur le boss = campagne terminée → retour à l'accueil.
- **`custom_depart`** (ou `"depart"`) — point de départ du token. Non-combat,
  aucune logique de jeu. Le moteur place le token ici au début de la campagne.
- **`custom_bonus`** — case décorative non-combat (provisoire). Traversable
  librement, aucune logique de jeu pour l'instant.
- Tout autre type custom — tag visuel sans logique de jeu.

## Comment les rencontres sont assignées (mode graphe)

Même mécanisme de **pool** que le mode JSON-linéaire antérieur :

1. Deux pools construits depuis les branches du personnage, dans l'ordre des branches :
   - `mook_pool` : `[branch[0].mook_1, branch[0].mook_2, branch[1].mook_1, ...]`
   - `rival_pool` : `[branch[0].rival, branch[1].rival, ...]`
2. Les cases de combat du JSON, **triées par `index` croissant** (le seul usage
   de `index` en mode graphe), déterminent l'ordre de consommation des pools :
   - `mook` → prend le prochain dans `mook_pool`
   - `miniboss` → prend le prochain dans `rival_pool`
   - `boss` → `campaign.organizer_encounter`
3. Les cases non-combat (`custom_depart`, `custom_bonus`) sont ignorées du tri.
4. La séquence plate résultante est poussée dans `CampaignContext.encounter_sequence`
   (pour compatibilité arrière — l'encounter actif en combat est surtout servi
   via `CampaignContext.pending_graph_encounter`, pas via l'index de séquence).

**Conséquence pratique** : si le JSON demande N mooks, le pool de branches doit
contenir au moins N rencontres de type mook. Pool trop petit → `push_warning`.
Pool trop grand → les entrées excédentaires sont silencieusement ignorées.

Exemple pour Mitrailleur (carte 2026-08-31) :
- JSON : 6 miniboss, 14 mooks, 1 boss = **21 cases de combat**
- Branches : 7 branches → pool mook : 14 rencontres (exact), pool rival : 7 (6 utilisées, 1 ignorée)

## Invariant de source de vérité

**La carte JSON est la source de vérité absolue pour la structure de combats.**

- En mode graphe : la TOPOLOGIE (qui est voisin de qui) définit le chemin réel
  du joueur. Il n'y a plus d'ordre global imposé. Chaque case se bat
  indépendamment dans l'ordre choisi par le joueur.
- `index` n'est utilisé que pour l'assignation des rencontres depuis les pools
  (pas pour définir un ordre de combat obligatoire).
- Les cases custom ne comptent pas pour l'assignation — elles sont uniquement visuelles.

### Comportement de repli (backward-compatible)

Les personnages **sans** carte JSON exportée (ou avec un JSON sans `path_nodes`
ni `connections`) continuent à utiliser l'ancienne logique de branche
(`mini_branches.size() * 3 + 1`) — le moteur bascule automatiquement selon la
présence des champs.

Les personnages avec un JSON en ancien format (sans `path_nodes`/`connections`
mais avec `cases` trié par `index`) continuent en mode JSON-linéaire (séquence
plate, `campaign_step` monotone croissant).

## Architecture graphe — résolution par ID (2026-08-31)

### Ce qui remplace display_step / campaign_step

En mode graphe, la progression n'est **plus un entier monotone** :

| Ancien (linéaire) | Nouveau (graphe) |
|---|---|
| `campaign_step` (int, avance de 1 à chaque victoire) | `_resolved_ids: Dictionary[id → true]` |
| `_display_step` (int, position visuelle) | `_current_node_id: String` |
| `CampaignSave.campaign_progress` (int) | `CampaignSave.resolved_case_ids` (Array[String]) |
| `CampaignContext.advance_step()` | `CampaignSave.add_resolved_case_id(character_id, node_id)` |

`campaign_step` et `campaign_progress` restent intacts pour les personnages en
mode branche ou JSON-linéaire — le mode graphe ne les touche pas.

### Navigation en graphe (flèches directionnelles)

Depuis `_current_node_id`, le moteur calcule pour chaque voisin direct (via
`_graph_adj`) la **direction dominante** (haut/bas/gauche/droite). Une flèche
pressée déplace le token vers le voisin le plus proche dans cette direction.

**Règle de blocage** (Camil : "ne peut PAS continuer au-delà d'une case non
résolue") :

- Depuis un nœud non-combat (relais, depart, bonus) ou un nœud RÉSOLU :
  → Tous les voisins sont accessibles.
- Depuis un nœud combat NON RÉSOLU :
  → Le token peut uniquement RECULER vers `_previous_node_id` (le nœud
    d'où il venait). Si `_previous_node_id` est vide (rechargement après
    perte), peut reculer vers n'importe quel voisin résolu ou non-combat.

Ce blocage n'est PAS global : le joueur peut emprunter n'importe quel autre
chemin sur la carte pour contourner une case bloquée (si la topologie le permet).

### Arrivée sur un nœud

- Nœud relais / bonus / depart → rien ne se passe (pas de dialog).
- Nœud combat déjà résolu → rien (juste visiter).
- Nœud combat NON résolu → dialog "Voulez-vous déclencher le combat ?"
  - **Oui** → `_confirm_selection()` → scène de combat.
  - **Non** / Échap / Flèche arrière → dialog fermé, le token peut reculer.

### Fin de campagne

Vaincre le nœud `boss` → `mark_organizer_defeated()` → retour à TitleScreen.
Aucune condition "tout doit être battu avant" — il suffit d'atteindre et de
vaincre le boss, ce qui peut nécessiter de résoudre certaines cases selon la
topologie.

## Où ça se branche côté Godot

**`godot_project/nodes/campaign_map_node.gd`** :

- `_load_graph_data(character_id)` → bool — lit le JSON, détecte le mode
  graphe (présence de `path_nodes` + `connections`), peuple `_graph_nodes`,
  `_graph_adj`, `_depart_node_id`.
- `_assign_graph_encounters()` — assigne les rencontres via les pools, peuple
  `_graph_combat_encounters`, `_tile_types`, `_tile_node_ids`, `_tile_positions`.
- `_is_graph_combat_node(id)` / `_is_node_resolved(id)` — helpers de statut.
- `_can_move_to_graph_neighbor(neighbor_id)` — règle de blocage.
- `_target_node_for_graph_key(key)` — voisin le plus proche dans la direction.
- `_handle_graph_arrow_navigation()` / `_move_to_graph_node(id)` — déplacement.
- `_on_arrive_at_graph_node(id)` — dialog si combat non résolu.
- `_tile_status(i)` — en mode graphe : lit `_resolved_ids` et `_current_node_id`.
- `_refresh_graph_mode()` — description + hint selon le nœud courant.
- `_confirm_selection()` — en mode graphe : set `CampaignContext.current_graph_node_id`
  et `pending_graph_encounter`, puis change_scene_to_file().

**`godot_project/nodes/campaign_context.gd`** :

- `is_graph_mode: bool` — flag global, set par `_build_tiles()`.
- `current_graph_node_id: String` — le nœud en cours de combat (préservé par
  `return_to_map()` pour restaurer la position après une perte).
- `pending_graph_encounter: RivalEncounterData` — l'encounter du nœud courant,
  set juste avant le changement de scène. Utilisé par `current_encounter()`.
- `is_organizer_fight()` — en mode graphe : vérifie `pending_graph_encounter == campaign.organizer_encounter`.
- `clear()` — remet à zéro tous les champs graphe.
- `return_to_map()` — conserve `current_graph_node_id`, efface `pending_graph_encounter`.

**`godot_project/nodes/campaign_save.gd`** :

- `get_resolved_case_ids(character_id)` → Array — set d'IDs résolus pour ce personnage.
- `add_resolved_case_id(character_id, id)` — ajoute un ID résolu et persiste.
- `campaign_progress` (int) reste intact pour les personnages en mode branche/linéaire.
- `has_any_progress()` / `character_with_progress()` considèrent aussi `resolved_case_ids`.

**`godot_project/nodes/match_arena_node.gd`** (+ `breakout_node.gd`, `space_invaders_node.gd`) :

- Sur victoire en mode graphe (`CampaignContext.is_graph_mode == true`) :
  → `CampaignSave.add_resolved_case_id(character_id, CampaignContext.current_graph_node_id)`
  → PAS d'`advance_step()` ni de `set_campaign_progress()` (inutiles en mode graphe).

## Avant d'intégrer une nouvelle carte

1. Vérifier que le pool de rencontres dans les branches couvre le nombre de
   cases de chaque type dans le JSON (mooks, rivals). Pool trop petit → warning.
2. Vérifier que le JSON a `path_nodes` + `connections` pour activer le mode graphe.
3. Déposer les deux fichiers sous `res://assets/art/worldmap/maps/`, lancer
   un boot headless de `CampaignMap.tscn` avec ce personnage et confirmer
   dans les logs qu'aucun `push_warning` de repli ne sort (le WARNING sur
   le PNG lui-même est normal et attendu).
4. Le `branch_count` dans le JSON est une métadonnée indicative pour l'auteur —
   ce qui fait foi pour le moteur, c'est le compte réel de cases dans `cases[]`.
5. Après intégration, lancer la suite de régression complète pour vérifier
   que les autres personnages (mode branche/linéaire) ne sont pas affectés.

## Invariants à ne jamais violer (mode graphe)

1. `_current_node_id` est toujours une clé valide de `_graph_nodes` (ou `""` avant init).
2. `_tile_node_ids`, `_tile_types`, `_tile_positions` sont des tableaux parallèles
   de même taille — toujours remplis ensemble dans `_assign_graph_encounters()` +
   `_build_layout()`.
3. `_resolved_ids` est toujours synchronisé avec `CampaignSave.get_resolved_case_ids()`
   au chargement de la carte. Jamais modifié localement — les modifications passent
   par `CampaignSave.add_resolved_case_id()` (appelé par MatchArena/Breakout/SpaceInvaders).
4. `CampaignContext.pending_graph_encounter` est toujours `null` sauf pendant
   le transit entre CampaignMap et la scène de combat — remis à null par `return_to_map()`.
5. Les cases custom (`custom_depart`, `custom_bonus`) ne sont JAMAIS dans
   `_tile_node_ids` / `_tile_types` / `_tile_positions` — elles sont stockées
   dans `_graph_nodes` et `_graph_adj` uniquement pour la navigation, pas pour le rendu des statuts.
