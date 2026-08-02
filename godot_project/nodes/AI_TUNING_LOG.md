# Journal d'apprentissage — IA adverse (Seek and Destroy and Reflect the Ball)

Historique des ajustements de l'IA, dans l'ordre chronologique. Lu intégralement en début de session par shakkam-ia-seek avant toute modification — ne jamais réinventer une correction déjà tentée (et éventuellement rejetée) précédemment.

---

## 2026-08-01 — IA "collée au filet" : repositionnement mid/arrière par défaut

**Demande utilisateur :** "l'IA se colle beaucoup au filet. dans la logique de contrôle, elle devrait se concentrer sur le milieu / arrière du terrain. s'approcher du filet peut être intéressant pour mieux viser l'adversaire de temps en temps."

**Changement :** l'ancienne logique horizontale (`ball_on_my_side → toujours pousser vers la frontière`) est remplacée par un système de profondeur préférée (`_ai_preferred_depth`, fraction 0=mur arrière à 1=frontière, tirée aléatoirement entre `AI_DEPTH_MIN=0.1` et `AI_DEPTH_MAX=0.5`, re-tirée toutes les 2-4s comme l'errance verticale). L'IA ne pousse à fond vers la frontière (`frontier_reach_x`) que lorsque `ball_close` est vrai (balle à moins de 260px **de sa propre position**, pas juste "de son côté du terrain"). Ajout d'une hystérésis horizontale (`AI_H_DEADZONE_STOP=6`, `AI_H_DEADZONE_START=18`) symétrique à celle déjà en place sur l'axe vertical, pour éviter tout jitter.

**Raisonnement :** l'ancienne règle traitait "balle techniquement de mon côté" comme équivalent à "je dois foncer au filet", ce qui la faisait s'y coller en permanence dès que la balle traversait la moitié de terrain — bien avant que ce soit réellement utile. Le nouveau seuil de proximité (260px, réutilise la même valeur que `_ai_update_lift_attempt`) ne déclenche l'avancée que quand l'interception est réellement imminente.

**À surveiller :** avec une profondeur par défaut assez en retrait (0.1-0.5), l'IA pourrait rater des balles rapides si le seuil de proximité (260px) s'avère trop court pour le temps de trajet à couvrir depuis sa position de repli — si l'utilisateur signale des ratés fréquents en IA plutôt qu'un simple manque d'agressivité, revoir `AI_APPROACH_DISTANCE` à la hausse plutôt que `AI_DEPTH_MAX`.

## 2026-08-01 — Implémentation initiale (Story 1.12)

**Demande utilisateur :** un adversaire IA basique pour pouvoir tester le prototype en solo (FR19 du GDD).

**Changement :** ajout de `ai_controlled`, `ball_ref`, `opponent_ref` sur `ShipNode`. Toggle via **F1** dans `match_arena_node.gd`. Suivi vertical simple de la balle (`_ai_read_input`), tir basique quand aligné avec l'adversaire (`_ai_should_fire`), pas de sélection d'arme, pas de lift.

**Raisonnement :** l'AC (FR19) demande explicitement une IA "pas besoin d'être équilibrée ou très douée" — juste fonctionnelle pour rendre le test solo possible.

**À surveiller :** aucun identifié à ce stade (première implémentation).

---

## 2026-08-01 — Anticipation + anti-jitter + mouvement horizontal

**Demande utilisateur :** "je pense que tu peux faire une IA plus intelligente. D'ailleurs souvent le joueur adverse se 'freeze' un peu."

**Changement :**
- Ajout d'anticipation de trajectoire (`AI_LOOKAHEAD = 0.15s`) : l'IA vise la position future de la balle, pas sa position actuelle.
- Ajout d'une **hystérésis** sur la décision de direction verticale (`AI_DEADZONE_STOP = 4.0`, `AI_DEADZONE_START = 14.0`) au lieu d'un seuil unique (6px) — le seuil unique faisait osciller `_ai_vertical_dir` entre 0 et une direction à chaque frame quand l'IA était proche de sa cible, perçu comme un freeze/stutter.
- Ajout de mouvement horizontal réel : avance vers la frontière quand la balle est de son côté, recule vers son mur arrière sinon (avant : `dir.x` toujours à 0, l'IA restait figée sur l'axe X).

**Raisonnement :** le "freeze" signalé n'était pas un bug d'input mais un jitter de décision (recalcul de direction à chaque frame sans marge). L'hystérésis est la correction standard pour ce genre de symptôme.

**À surveiller :** si l'IA semble "trop précise" avec l'anticipation à mesure que le gameplay évolue (vitesse de balle, tailles de vaisseau), revoir `AI_LOOKAHEAD` à la baisse.

---

## 2026-08-01 — Errance, changement d'arme, tentatives de lift

**Demande utilisateur :** "elle ne doit pas rester trop 'collée' au mouvement de balle", changer d'arme de temps en temps, tenter des lifts occasionnellement.

**Changement :**
- `_ai_update_wander` : cible verticale "d'errance" indépendante, recalculée toutes les 1.2-2.4s (`AI_WANDER_INTERVAL_MIN/MAX`), mélangée à la cible de poursuite de balle via `lerpf` — poids 0.2 quand la balle est urgente (de son côté), 0.6 sinon.
- `_ai_update_weapon_switch` : pulse la sélection d'arme toutes les 3-6s (aléatoire), sans logique stratégique.
- `_ai_update_lift_attempt` : quand la balle approche et se rapproche du bord (< 260px), 30% de chances de tenter un lift court (0.35 ou 0.75s de charge), réutilisant **exactement** le même système de charge/gel que le joueur humain (`_read_lift_held()` → `_lift_charge_timer`) plutôt que de dupliquer une mécanique.

**Raisonnement :** garder l'IA "vivante" sans lui donner de compétence stratégique réelle (toujours conforme à FR19/FR20 — pas besoin d'être douée). La réutilisation du système de charge humain évite la duplication de logique de gameplay.

**À surveiller :** le changement d'arme aléatoire (3-6s) peut occasionnellement tomber en plein milieu d'un duel et sembler "bête" — acceptable pour l'instant (IA volontairement imparfaite), mais à noter si l'utilisateur trouve ça trop fréquent.

---

## 2026-08-01 — Bug : balle qui part en arrière au spawn

**Demande utilisateur :** "quand un joueur se met tout devant, au spawn de la balle elle part en arrière."

**Changement :** ajout d'un délai de grâce au spawn (`_spawn_grace`, `SPAWN_GRACE_DURATION = 0.25s`) dans `ball_node.gd` — `_resolve_ships()` est sauté tant que la grâce n'est pas écoulée. Appliqué à la fois dans `_ready()` et `reset_to_center()`.

**Raisonnement :** ce n'est pas un bug d'IA à proprement parler (touche `ball_node.gd`, pas `ship_node.gd`) mais documenté ici car directement lié au comportement observé pendant les tests IA — un vaisseau (humain ou IA) collé à la frontière chevauche déjà le point de spawn central de la balle, causant un renvoi instantané dès la première frame.

**À surveiller :** si l'IA (ou un joueur) se tient systématiquement collée à la frontière, elle "perdra" les 0.25s de grâce à chaque respawn sans pouvoir intercepter — comportement attendu, pas un bug.
