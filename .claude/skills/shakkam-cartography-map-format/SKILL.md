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
- **`<perso>_map.json`** — la liste ordonnée des cases qui comptent pour la
  progression, chacune avec sa position dans cette même image :

```json
{
  "width": 1280, "height": 720,
  "branch_count": 4,
  "case_type_labels": { "mook": "Case Mook", "miniboss": "Case Miniboss (rival)", "boss": "Case Boss (organisateur)" },
  "cases": [
    { "index": 0, "type": "mook", "x": 100, "y": 100 },
    { "index": 1, "type": "miniboss", "x": 300, "y": 100 }
  ]
}
```

## Ce que veut dire chaque type de case

- **Ligne/chemin jaune visible dans le PNG** — n'existe QUE dans l'image :
  c'est le trajet que le joueur emprunte visuellement entre les cases.
  Aucune entrée JSON ne lui correspond, ce n'est pas une "case", juste du
  décor de connectivité.
- **`mook`** — un combat simple (échauffement, adversaire affaibli).
- **`miniboss`** — un combat contre l'un des rivaux (un "gros vilain").
- **`boss`** — le combat final de cette carte, contre l'organisateur du
  tournoi. Une seule case `boss` par carte, toujours en dernière position.
- **`bonus`** *(type custom, pas encore un standard figé)* — pour l'instant :
  donne un petit bonus aléatoire (ex. +20 PV pour le prochain combat, ou
  démarrer le prochain combat avec l'Ultra déjà chargée). Explicitement
  provisoire ("on trouvera mieux après", Camil 2026-08-29) — pas de
  mécanique de jeu dédiée encore écrite ; à concevoir/itérer plutôt qu'à
  considérer comme figé.
- **N'importe quel autre type custom** (ex. `depart`) — pur marqueur/tag
  visuel pour l'auteur de la carte, aucune logique de jeu tant que ce n'est
  pas explicitement demandé.

## L'invariant qui compte le plus (mis à jour 2026-08-29)

**La carte JSON est la source de vérité absolue pour la structure de combats.**
Il n'y a plus de formule `mini_branches.size() * 3 + 1`. À la place :

- Les cases `mook`/`miniboss`/`boss` du JSON, **triées par `index`
  croissant**, définissent l'ordre exact des combats (étape 0, 1, 2, ..., N-1).
- Les cases custom (`bonus`, `depart`, etc.) sont ignorées pour la
  séquence de combat — elles restent visuelles uniquement.
- Le total de combats = nombre de cases mook + miniboss + boss dans le JSON.
  Un JSON avec 13 mooks + 6 miniboss + 1 boss donne **exactement 20 étapes**.

### Comportement de repli (backward-compatible)

Les personnages **sans** carte JSON exportée continuent à utiliser l'ancienne
logique de branche (`mini_branches.size() * 3 + 1`) — le moteur bascule
automatiquement selon la présence ou absence du fichier `.json` + `.png`.

## Comment les rencontres sont assignées (mode JSON-first)

Le moteur utilise un mécanisme de **pool** dans `_build_tiles_from_json()` :

1. Deux pools sont construits depuis les branches du personnage, dans l'ordre des branches :
   - `mook_pool` : `[branch[0].mook_1, branch[0].mook_2, branch[1].mook_1, branch[1].mook_2, ...]`
   - `rival_pool` : `[branch[0].rival, branch[1].rival, ...]`
2. Pour chaque case de combat dans le JSON (triée par index) :
   - `mook` → prend le prochain dans `mook_pool` (mook_pool[0], mook_pool[1], …)
   - `miniboss` → prend le prochain dans `rival_pool`
   - `boss` → `campaign.organizer_encounter`
3. La séquence plate résultante est poussée dans `CampaignContext.encounter_sequence`.

**Conséquence pratique** : si le JSON demande N mooks, le pool de branches doit
contenir au moins N rencontres de type mook. Si le pool est plus grand que ce
que le JSON demande, les entrées excédentaires sont silencieusement ignorées.
Si le pool est trop petit, un `push_warning` est loggé et la rencontre est null.

Exemple pour Mitrailleur (carte 2026-08-29) :
- JSON : 6 miniboss, 13 mooks, 1 boss = 20 étapes
- Branches : 7 branches (dont une "vs Mini" ajoutée pour le 13e mook)
  → pool mook : 14 rencontres (13 utilisées, 14e ignorée)
  → pool rival : 7 rencontres (6 utilisées, 7e ignorée)

## Où ça se branche côté Godot

Tout est dans `godot_project/nodes/campaign_map_node.gd` :

- `_map_png_path(character_id)` / `_map_json_path(character_id)` —
  convention de chemin : `res://assets/art/worldmap/maps/<character_id>_map.png`
  et `.json`. Rien d'autre à câbler pour brancher une nouvelle carte, juste
  déposer les deux fichiers à cet endroit avec le bon `character_id`
  (l'identifiant de dossier sous `data/campaigns/<character_id>/`).
- `_load_json_cases(character_id)` — charge le JSON, trie par `index`,
  filtre sur les 3 types core. Retourne un tableau vide si aucune paire
  PNG+JSON n'existe → repli procédural.
- `_build_tiles_from_json(json_cases)` — construit `_tile_types` /
  `_tile_encounters` depuis la séquence JSON + pools, puis pousse la
  séquence plate dans `CampaignContext.set_encounter_sequence()`.
- `_load_custom_map_positions(character_id)` — lit le JSON pour les
  coordonnées (x, y) de chaque case de combat, en respectant le même
  ordre que `_load_json_cases()`.
- `_load_texture_from_disk(path)` — charge le PNG via `Image.load()` plutôt
  que `load()`/`ResourceLoader` : un export tout frais n'a pas encore de
  fichier `.import` (pas besoin d'ouvrir l'éditeur avant que ça marche).
  Produit un WARNING Godot sur la console headless — c'est attendu et
  documenté, pas un bug.
- `_build_layout()` — bascule entre carte réelle et repli procédural. Quand
  JSON-first, `_tile_types.size()` correspond toujours à
  `_load_custom_map_positions().size()` (même filtre).
- `_draw_case_marker(i)` — le SEUL dessin ajouté par-dessus une vraie carte :
  un petit indicateur de statut (fait/en cours/verrouillé) à la position
  `(x, y)` de la case, rien d'autre — pas d'icône de type, pas de route,
  c'est déjà dans le PNG.

Et dans `godot_project/nodes/campaign_context.gd` :

- `encounter_sequence: Array` — séquence plate de `RivalEncounterData`, non
  vide uniquement pour les personnages avec une carte JSON. Quand non vide,
  remplace complètement la logique de branche dans `total_steps()` et
  `current_encounter()`.
- `set_encounter_sequence(seq)` — appelé par `_build_tiles_from_json()`.
- `total_steps()` — retourne `encounter_sequence.size()` si non vide, sinon
  `mini_branches.size() * 3 + 1`.
- `current_branch()` — retourne `null` en mode JSON-first (pas de mapping
  par-étape vers une branche). Les appelants (`match_arena_node.gd`,
  `campaign_map_node.gd`) null-checkent avant usage.

## Navigation à la flèche directionnelle (2026-08-30)

### display_step vs campaign_step

Deux valeurs distinctes coexistent dans `campaign_map_node.gd` :

- **`CampaignContext.campaign_step`** — progression réelle sauvegardée.
  Avance uniquement après la victoire d'un combat (`advance_step()`). Ne
  recule jamais.
- **`_display_step`** — position VISUELLE du token du joueur. Peut être
  `-1` (case `depart`, si elle existe dans le JSON), `0..campaign_step`
  (exploration libre des cases déjà résolues), mais JAMAIS au-delà de
  `campaign_step`.

### Initialisation au chargement de la carte

- Si le JSON contient une case `depart` **et** que `campaign_step == 0` :
  `_display_step = -1` (token sur la case départ, pas encore sur un combat).
- Sinon (joueur de retour après un combat, ou pas de case `depart`) :
  `_display_step = campaign_step` et le dialog de confirmation s'affiche
  immédiatement.

### La case `depart` dans le JSON

Type custom non combat, capturé par `_load_depart_position()` séparément
de `_load_json_cases()` (qui, lui, filtre sur mook/miniboss/boss). Sert
uniquement de point d'ancrage initial pour le token. Aucune logique de
combat ne lui est associée.

```json
{ "index": 0, "type": "depart", "x": 120, "y": 600 }
```

### Navigation par flèches

Le moteur calcule pour chaque paire de cases adjacentes la **direction
dominante** (haut/bas/gauche/droite) d'après le delta (x, y) écran.
Quand le joueur presse une flèche :

- Si elle pointe vers `display_step - 1` (case précédente ou case `depart`)
  → le token recule.
- Si elle pointe vers `display_step + 1` ET `display_step < campaign_step`
  (ou `display_step == -1` pour aller de depart à la case 0) → le token
  avance.
- Si elle ne correspond à aucun voisin valide → rien ne se passe.

Un **Tween 0.35 s EASE_IN_OUT SINE** anime `_token_draw_position` entre
les positions. Les inputs sont ignorés pendant le tween.

### Dialog de confirmation

Quand le token **arrive** sur une case `campaign_step` (de type
mook/miniboss/boss), un dialog s'affiche :

> Voulez-vous déclencher le combat ?
> [Oui (Espace/Entrée)]  [Non (Échap)]

- **Oui** → `_confirm_selection()` → changement de scène vers le combat.
- **Non** → ferme le dialog ; le joueur peut reculer et explorer.
- Appuyer sur une flèche vers l'arrière (depuis le dialog) le ferme aussi
  et lance le déplacement.

Le token (`_draw_player_token`) suit toujours `_token_draw_position`
(animé). Le marqueur de statut pulsant (ring blanc) reste ancré sur la
case `campaign_step`, même si le token est ailleurs.

### Invariants à ne jamais violer

1. `_display_step` ne dépasse jamais `campaign_step`.
2. `_tile_status(i)` (done/current/locked) reste basé sur `campaign_step`,
   pas sur `_display_step`.
3. La case `depart` est **toujours filtrée** de `_tile_types` / `_tile_positions`
   — elle n'est pas une case de combat. Elle est lue séparément dans
   `_load_depart_position()`.

## Avant d'intégrer une nouvelle carte

1. Vérifier que le pool de rencontres dans les branches couvre le nombre de
   cases de chaque type dans le JSON (mooks, rivals). Si trop petit :
   ajouter une branche supplémentaire ou des rencontres standalone.
2. Déposer les deux fichiers sous `res://assets/art/worldmap/maps/`, lancer
   un boot headless de `CampaignMap.tscn` avec ce personnage et confirmer
   dans les logs qu'aucun `push_warning` de repli ne sort (le WARNING sur
   le PNG lui-même est normal et attendu, pas un problème).
3. Le SKILL.md et le `branch_count` dans le JSON sont des métadonnées
   indicatives pour l'auteur de la carte — ce qui fait foi pour le moteur,
   c'est le compte réel de cases mook/miniboss/boss dans `cases[]`.
4. Si la carte a une case `depart`, s'assurer que sa position (x, y) est
   visuellement adjacent à la case 0 dans une direction clairement lisible
   (la flèche à presser sera calculée automatiquement par `_dominant_direction()`
   mais une direction ambiguë (delta ~45°) donne des résultats surprenants).
