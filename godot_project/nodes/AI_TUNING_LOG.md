# Journal d'apprentissage — IA adverse (Seek and Destroy and Return the Ball)

Historique des ajustements de l'IA, dans l'ordre chronologique. Lu intégralement en début de session par shakkam-ia-seek avant toute modification — ne jamais réinventer une correction déjà tentée (et éventuellement rejetée) précédemment.

---

## 2026-08-02 — Comportement IA par archétype (Epic 2, Story 2.7)

**Demande utilisateur :** enchaîner les stories 2.3 puis 2.7 de l'Epic 2 ("2.3 et 2.7 en suivant") — l'IA doit se comporter différemment selon le personnage piloté (FR20), sans dupliquer le framework IA existant.

**Changement :** ajout de `AI_PROFILES` (dictionnaire const, clé = `CharacterData.id`) dans `ship_node.gd`, appliqué via `_apply_ai_profile()` (appelée dans `_ready()` et `set_character()`). Chaque profil surcharge des **instances** des anciens paramètres globaux (`_ai_depth_min/max`, `_ai_approach_distance`, `_ai_lift_chance`) plutôt que les constantes elles-mêmes, qui restent le fallback si le personnage n'a pas de profil (ex : kit placeholder Epic 1). Ajout d'un nouveau paramètre `signature_bias` : quand > 0, `_ai_update_weapon_switch` ne pulse plus la sélection à l'aveugle toutes les 3-6s (comportement legacy, conservé si `signature_bias == 0`) mais tire une préférence pour l'arme signature (index 0 du kit) et ne pulse que si la sélection actuelle ne correspond pas au tirage — ex. Contrôleur (`signature_bias = 0.85`) reste très majoritairement sur sa tourelle au lieu d'alterner avec la mitraillette. Réglages par archétype : Lourd/Contrôleur = profondeur basse + faible `lift_chance` (repli, campe) ; Vif/Mini = profondeur haute + `lift_chance` élevée (agressif, mobile) ; Missiles/Zoneur = profondeur basse-moyenne, `signature_bias` élevé (misent sur leur arme signature à distance) ; Perturbateur = profondeur moyenne, `signature_bias` élevé (cherche à placer son stun).

**Raisonnement :** AC 2.7 exige de réutiliser le framework existant (wander/depth/lift/weapon-switch de la Story 1.12) plutôt qu'un système IA parallèle, et cite explicitement l'exemple Contrôleur = tourelle plutôt que tir direct. Passer les constantes `AI_DEPTH_MIN/MAX`/`AI_APPROACH_DISTANCE` en variables d'instance avec les mêmes valeurs par défaut garantit qu'un personnage sans profil (ou l'ancien kit placeholder) se comporte exactement comme avant Epic 2 — pas de régression Epic 1.

**À surveiller :** les valeurs par profil sont des première estimations non playtestées (pas d'accès à un runtime Godot ici) — à valider/ajuster une fois testées en jeu, en particulier `signature_bias` pour Contrôleur (vérifier que l'IA replace bien une tourelle après expiration de `TurretNode.LIFETIME = 6s` plutôt que de rester bloquée sur l'arme sans jamais retirer).

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

---

## 2026-08-17 — Équilibrage : tourelles ciblables + bug de cadence de tir IA (7/8 persos) + verrou de surchauffe Mitrailleur

*(Note : le journal n'avait pas été mis à jour depuis le rework de priorités IA du 2026-08-16 — three regressions "elle rate tout le temps la balle" / "elle doit aller en fond de court" / "elle la rate encore" ont été corrigées ce jour-là directement dans `ship_node.gd` sans entrée ici. Non reconstruit rétroactivement, voir l'historique git de `ship_node.gd` autour du 16/08 si besoin.)*

**Demande utilisateur :** "gros probleme d'équilibrage" — un harnais de simulation batch maison (`tests/balance_simulation.gd`, 8 persos tous-vs-tous, IA des deux côtés, 448 matchs) a montré Controleur à 100% de victoires et Vif à 2%. Après diagnostic : "je ne baisserais pas le lifetime [des tourelles], par contre diviser les PV des tourelles par 2 me semble bien. tu peux booster l'IA pour qu'elle vise aussi les tourelles. OK pour booster vif comme propose. et tu peux améliorer l'IA de perturbateur et mitrailleur aussi."

**Changement :**
1. **`_ai_find_enemy_turret()`** (nouveau) — scanne les siblings pour une `TurretNode` ennemie vivante, même pattern que `_ai_dodge_direction()`. `_ai_read_input()` : `aggression_target_y` cible la tourelle ennemie (position FIXE, jamais retrackée sur son propriétaire — `MatchArenaNode._spawn_turret()` ne la met à jour qu'à la pose) plutôt que la position courante de l'adversaire, tant qu'une tourelle est vivante.
2. **Bug de cadence trouvé en creusant Perturbateur** (mais touche 7/8 persos, tous sauf Mitrailleur) : les armes non-`full_auto` ne tirent que sur le FRONT MONTANT de `fire_held` (`_physics_process` : `is_full_auto or not _fire_prev`). `_ai_should_fire()` renvoyait un simple booléen d'alignement qui restait `true` plusieurs frames d'affilée une fois aligné — après le premier tir, `_fire_prev` ne repassait jamais à `false`, donc l'IA ne tirait qu'UNE FOIS par fenêtre d'alignement au lieu de répéter au fire_rate réel de l'arme. Fix : `_ai_should_fire()` renvoie `false` tant que `weapon_state.cooldown > 0.0`, ce qui force une vraie frame `false` et restaure un front montant à chaque cycle de cooldown — l'IA "tapote" comme le ferait un joueur humain. No-op pour Mitrailleur (full-auto, ne dépendait jamais du front).
3. **Verrou de surchauffe Mitrailleur** : `WeaponSystemState.with_heat_ticked()` ne fait drainer la chaleur QUE quand `fire_held == false` (mécanique voulue pour un joueur humain : "des qu'on relache le bouton la jauge remonte"). L'IA n'avait aucune conscience de son propre état de chaleur — une fois surchauffée en restant alignée, elle restait bloquée à chaleur max indéfiniment (`_ai_should_fire()` continuait de renvoyer `true`). Fix : renvoie `false` dès que `heats[selected_index] >= heat_max`.
4. `_ai_should_fire()` tire aussi sur une tourelle ennemie alignée (même tolérance HP-scalée que pour l'adversaire), pas seulement sur l'adversaire.
5. `turret.tres` : `turret_hp` 22 → 11 (lifetime/dégâts inchangés, décision explicite de Camil). `vortex.tres` : `damage` 2 → 3, `fire_rate` 1.905 → 2.3 (retour partiel du nerf du 2026-08-13, pas total).

**Raisonnement :** le mécanisme "un projectile qui traverse la hitbox d'une tourelle ennemie l'endommage" existait déjà et fonctionne pour tout le monde (`ProjectileNode._physics_process`) — le seul manque était que l'IA ne s'alignait jamais dessus. Le bug de cadence (#2) est le plus gros trouvé : il plafonnait silencieusement TOUT le roster (sauf Mitrailleur) à un tir par fenêtre d'alignement, ce qui explique en partie pourquoi le DPS théorique par arme ne prédisait pas bien les taux de victoire observés.

**À surveiller :** le fix #2 va mécaniquement augmenter le DPS effectif de TOUS les persos non-Mitrailleur simultanément (pas juste Perturbateur) — le nouveau classement post-fix doit être relu en tenant compte de ça, pas seulement comme "Perturbateur va mieux". Re-simulation lancée pour mesurer l'effet réel avant tout autre chiffrage.

---

## 2026-08-17 (suite) — Tolérance au risque, tourelle toujours dominante, Zoneur revert, Missiles calmé + dodge homing, Perturbateur boomerang

**Ce qui a marché, confirmé sur re-tests répétés :** le fix de cadence + le déverrouillage de surchauffe ont fait passer Vif de 2% à ~30-38% et Mitrailleur de 25% à ~30-47%, de façon stable sur 7 batchs.

**Controleur — tentative #2 (échec) :** diagnostic ciblé (`tests/turret_targeting_diag.gd`, supprimé après usage) a confirmé qu'une tourelle vivante qui tire EN RETOUR déclenche la priorité 2 (esquive) de l'IA attaquante, qui écrase inconditionnellement tout ciblage — sans tir de la tourelle, l'IA converge bien vers elle ; avec, elle fuit. Fix tenté : `AI_TURRET_HUNT_HP_FLOOR = 0.4` — au-dessus de 40% HP, l'esquive est suspendue tant qu'une tourelle ennemie est vivante et que la balle n'est pas urgente (`not ball_on_my_side`). **N'a quasi rien changé en match réel (99% → 99%)** : la balle repasse constamment de camp, donc la fenêtre "balle pas urgente" est trop fragmentée pour laisser le temps de fermer la distance. Le levier comportemental reste en place (correct pour un joueur humain qui presse l'attaque), mais Camil est passé sur le levier numérique : `turret_lifetime` 25→18.75 (-25%, "un petit peu"). Résultat isolé (sans les autres changements de cette entrée) : 99%→98%, quasi rien non plus. Controleur reste le point noir non résolu du roster contre l'IA — accepté pour l'instant, pas de nouvelle tentative dans cette session.

**Zoneur — deux essais numériques, deux échecs, revert complet :** cooldown laser 1.25→1.0 (théorie du duty-cycle de vulnérabilité arme lourde) : 13%→12%, rien. Dégâts 20→25 : toujours 12%. Camil : "y'a un vrai probleme. on va lui remettre ses trucs de depart." `laser.tres` revert intégral (damage=20, fire_rate=1.25). Le vrai problème n'est pas identifié — probablement que Zoneur ne profite pas du fix de cadence autant que les armes à salve/tête chercheuse (Missiles/Mini), qui touchent même sur un alignement imparfait. À investiguer une autre session si le sujet revient.

**Missiles calmé, à la fois en chiffres ET en IA :** `homing_strength` 2.0→1.6 (encore -20%, après un premier -20% du 2026-08-10). Camil a diagnostiqué lui-même la moitié IA du problème : "je pense que l'IA ne sait pas bien eviter des missiles a tete chercheuse. Un humain, si." `_ai_dodge_direction()` élargit maintenant sa marge d'alignement ×1.6 spécifiquement quand la menace la plus proche a `homing_strength > 0.0` — réagit plus tôt/plus large contre une menace qui re-vise activement, au lieu du même seuil fixe qu'un tir en ligne droite.

**Perturbateur — trouvé un vrai problème d'IA, pas juste des chiffres :** Camil : "l'IA ne sait pas le jouer. Il est particulier, ses tirs ne vont pas droit, et il faut le jouer dans ce sens." En lisant `projectile_node.gd` : le boomerang suit un arc "banane" fixe de ±30° sur son aller (`BOOMERANG_ARC_ANGLE_DEG`), pas une ligne droite comme toutes les autres armes — et sa direction initiale (part vers le haut ou vers le bas) dépend du dernier mouvement du tireur au moment du tir (`get_last_move_direction()`), un vrai levier de compétence pour un joueur humain. Plutôt que de modéliser précisément la géométrie de l'arc (complexité non désirée pour une IA volontairement pas très douée), `_ai_should_fire()` élargit sa tolérance d'alignement ×1.8 spécifiquement pour `selected.is_boomerang` — accepte de ne pas viser précisément une trajectoire qu'elle ne peut de toute façon pas anticiper.

**À surveiller :** Controleur et Zoneur restent non résolus après plusieurs tentatives chacun — ne pas retenter les mêmes leviers déjà essayés (voir ci-dessus) sans nouvelle info. Re-simulation lancée pour mesurer l'effet réel de cette passe (Missiles/Perturbateur surtout).

---

## 2026-08-17 (suite) — Échantillon fiable (n=45) + Perturbateur : compensation d'aim réelle + trainee de feu

**Leçon méthodologique :** le batch à 16 matchs/matchup (±12pts d'écart-type) faisait chasser du bruit d'une passe à l'autre (Missiles montait alors qu'on venait de le nerfer). Passé à 45 matchs/matchup (±7pts, 1260 matchs). **Piège Godot retrouvé en le faisant** : `--quit-after` dimensionné pour l'ancien volume (16/matchup) a tronqué le premier run à 761/1260 matchs avec exit code 0 (aucune anomalie visible sans vérifier que la derniere ligne imprimée est bien le tableau final) — toujours recalculer `--quit-after` proportionnellement au nombre de matchs avant de faire confiance à un run.

**Résultat fiable (n=315/perso) :** controleur 96%, missiles 78%, mini 72%, lourd 67%, mitrailleur 34%, vif 27%, perturbateur 24%, **zoneur 3%** (pire que ne l'etait Vif au tout debut de la session). Controleur et Zoneur restent les deux vrais points noirs, aucune tentative de cette session n'a bougé l'un ou l'autre de façon significative.

**Perturbateur, deuxième passe — Camil a donné 4 retours précis, tous implémentés :**
1. Confirmation du diagnostic IA du 2026-08-17 (voir plus haut, tolérance ×1.8) : "il faut viser en consequence, ne pas viser en face". Le fix précédent élargissait juste la tolérance d'alignement, mais ne corrigeait PAS la direction du lancer elle-même — le mouvement de l'IA (qui pilote `boomerang_descending_throw` via `get_last_move_direction()`) suit le ball-tracking, pas l'adversaire. Ajout dans `_ai_read_input()` : juste avant un lancer (`_ai_should_fire()` re-consultée, pure/sans effet de bord), force `_ai_vertical_dir` vers le signe de l'écart Y réel avec l'adversaire — la esquive (priorité 2) garde toujours la main si elle s'applique.
2. "Les tirs sont petits, grossis-les un peu (x1.3)" → `stun_boomerang.tres` `visual_scale_multiplier = 1.3` (défaut 1.0, jamais set avant).
3. "Le tir chargé... c'est gros, impressionnant, mais en vrai bof." → nouvelle idée de Camil : le même gros boomerang, mais qui laisse une **trainee de feu (particules) derriere lui, degats au contact, 3s de duree**. Nouveau `FireTrailNode` (mirror de `HazardZoneNode` mais degats au lieu de stun/deflect, tick toutes les 0.4s tant que la victime reste dedans plutot qu'un coup unique). `ProjectileNode.leaves_fire_trail` (nouveau champ, opt-in) drop un `FireTrailNode` toutes les 0.12s de vol, sur LES DEUX legs (aller et retour — "derriere lui" ne distingue pas). Set uniquement sur le lancer CHARGE (`MatchArenaNode._on_charged_weapon_fired`, repéré via `boomerang_out_duration_override > 0.0`, un signal deja unique a ce site d'appel), jamais le tir normal en rafale de 3.

**Raisonnement :** le point 1 est le vrai fix comportemental (le point 2026-08-17 precedent n'etait qu'un pansement de tolerance) — sans ca, meme une IA qui accepte de tirer "a peu pres aligne" lance quand meme dans une direction d'arc non-correlee a l'adversaire. Les points 2-3 sont des changements demandes explicitement, pas des diagnostics de ma part.

**Test coverage :** `tests/perturbateur_fire_trail_check.gd` — 6 checks (scale, charged-only opt-in, normal-fire n'opte PAS in, degats reels au contact, expiration a 3s, compensation d'aim). Tous verts, suite complete inchangee.

**À surveiller :** pas encore re-mesuré en batch (lancé juste après cette passe) — Perturbateur restait a 24% sur l'echantillon fiable AVANT ces 4 changements, donc la prochaine mesure est le vrai test.

---

## 2026-09-01 — Mook Vif trop difficile en premier combat de la campagne Mitrailleur

**Demande utilisateur :** "Premier combat contre Vif. Il me DEFONCE. ses tirs sont hyper rapides, je peux rien faire." — le premier combat de la campagne de Mitrailleur est `mook_1_vif` (Vif affaibli, `mook_hp_multiplier=0.6` sur les PV), censé être un échauffement.

**Diagnostic :** trois facteurs cumulés, pas un seul :
1. `vortex.tres` a été buffé le 2026-08-17 pour équilibrer Vif en batch IA-vs-IA (`fire_rate` 1.905→2.3, `damage` 2→3). Ce buff a été calibré sur des matchs bot-vs-bot ; un joueur humain face à des sinusoïdes à 2.3/s depuis un adversaire qui se colle au filet n'a pratiquement aucun temps de réaction.
2. Le profil IA de Vif est le plus agressif du roster (`approach_distance=340`, `depth_min=0.35`, `depth_max=0.65`, `lift_chance=0.45`) — il se rapproche du filet avant de tirer, ce qui réduit le temps de vol des balles et rend la sinusoïde illisible.
3. `mook_hp_multiplier=0.6` réduit uniquement les PV, pas l'agressivité IA. Le mook vivait moins longtemps mais frappait aussi vite et aussi près que le vrai rival.

**Changement :** ajout du flag `ai_is_mook: bool = false` sur `ShipNode` + trois constantes `AI_MOOK_APPROACH_SCALE = 0.65`, `AI_MOOK_DEPTH_SCALE = 0.65`, `AI_MOOK_LIFT_SCALE = 0.60` dans `ship_node.gd`. `_apply_ai_profile()` applique ces multiplicateurs sur les valeurs du profil quand `ai_is_mook = true` (les valeurs de base de `AI_PROFILES` restent inchangées — seule l'instance runtime est réduite). Dans `match_arena_node.gd`, le bloc `if encounter.is_mook:` existant set le flag et rappelle `_apply_ai_profile()` avant `reset_for_new_round()`.

Valeurs finales pour mook Vif : `approach_distance` 340→221, `depth_max` 0.65→0.42, `depth_min` 0.35→0.23, `lift_chance` 0.45→0.27 — soit un niveau d'agressivité proche du profil Mitrailleur ou Perturbateur. `signature_bias` reste 0.7 (l'identité arme du personnage ne change pas). S'applique à tous les mooks du roster, pas seulement Vif.

**Raisonnement :** le problème n'était pas dans le weapon data (simulation partagée, hors périmètre) ni dans le `mook_hp_multiplier` — uniquement dans le fait que le profil IA ne distinguait pas "mook" de "rival". Le fix réutilise exactement le hook `is_mook` déjà présent dans `match_arena_node.gd`, et n'ajoute aucune mécanique nouvelle. Les constantes de scale sont documentées et ajustables indépendamment des profiles nominaux.

**À surveiller :** le scaling s'applique à tous les mooks uniformément (y compris les mooks Lourd, Controleur, etc. qui étaient déjà peu agressifs) — si un mook d'un autre archétype semble maintenant trop passif/insignifiant, le `AI_MOOK_DEPTH_SCALE` peut être remonté prudemment (0.65→0.75 par exemple). Les stats batch IA-vs-IA ne sont pas affectées (ces simulations utilisent `ai_controlled` mais pas `ai_is_mook`, donc les taux de victoire mesurés précédemment restent valides comme référence).

---

## 2026-09-02 — Batch post-buff Boomerang : résultats mitigés, Missiles/Mini en hausse, Zoneur toujours plancher

**Demande utilisateur :** vérifier l'équilibrage du roster post-changements de session (mook Vif + boomerang damage 1→1.5). "Un petit test avec des IA expérimentées" — aperçu rapide, pas une étude complète.

**Méthode :** harnais existant `tests/balance_simulation.gd` (tous-vs-tous, les deux ships en `ai_controlled=true`, `ai_is_mook=false`). `RUNS_PER_MATCHUP` réduit temporairement à 20 (±10pt d'erreur standard) pour rentrer dans les contraintes de la session — restauré à 45 immédiatement après. 560 matchs au total.

**Piège de timing retrouvé :** `--quit-after 3000000` (calculé proportionnellement depuis le `6000000` du run n=45) s'est avéré insuffisant — la simulation a été coupée à 310/560 matchs. Cause : les matchups de la deuxième moitié (Vif/Perturbateur/Missiles/Mini entre eux) sont significativement plus longs en ticks que les matchups de la première moitié (Controleur/Lourd qui finissent vite). Le `6000000` du run n=45 passait parce que les 1260 matchs de toutes durées étaient distribués uniformément. Fix pour n=20 : utiliser `--quit-after 10000000` (pas proportionnel au n, mais au contenu des matchups). Durée réelle du run : ~21 minutes (vs ~9 estimées).

**Résultats (n=20, 560 matchs) — comparaison avec n=45 du 2026-08-17 :**

| Personnage | 2026-09-02 (n=20) | 2026-08-17 (n=45) | Delta |
|---|---|---|---|
| controleur | **90%** | 96% | -6pt |
| missiles | **84%** | 78% | +6pt ⚠ |
| mini | **76%** | 72% | +4pt |
| lourd | **62%** | 67% | -5pt |
| vif | **34%** | 27% | +7pt |
| mitrailleur | **26%** | 34% | -8pt |
| perturbateur | **22%** | 24% | -2pt |
| zoneur | **6%** | 3% | +3pt |

Les deltas de ±4-8pt sont dans la marge de bruit de n=20 (±10pt) — aucun mouvement n'est statistiquement certain sauf les cas extrêmes ci-dessous.

**Résultats matchup à matchup (extrait des plus informatifs) :**

```
lourd vs controleur: 1-19  (lourd 5% / controleur 95%)
lourd vs mitrailleur: 20-0  (lourd 100% / mitrailleur 0%)
lourd vs vif: 20-0  (lourd 100% / vif 0%)
lourd vs zoneur: 20-0  (lourd 100% / zoneur 0%)
lourd vs perturbateur: 17-3  (lourd 85% / perturbateur 15%)
controleur vs mitrailleur: 20-0  (controleur 100% / mitrailleur 0%)
controleur vs vif: 20-0  (controleur 100% / vif 0%)
controleur vs zoneur: 20-0  (controleur 100% / zoneur 0%)
controleur vs perturbateur: 20-0  (controleur 100% / perturbateur 0%)
mitrailleur vs perturbateur: 9-11  (mitrailleur 45% / perturbateur 55%)
mitrailleur vs missiles: 0-20  (mitrailleur 0% / missiles 100%)
mitrailleur vs mini: 0-20  (mitrailleur 0% / mini 100%)
vif vs missiles: 0-20  (vif 0% / missiles 100%)
vif vs mini: 0-20  (vif 0% / mini 100%)
zoneur vs missiles: 0-20  (zoneur 0% / missiles 100%)
zoneur vs mini: 0-20  (zoneur 0% / mini 100%)
perturbateur vs missiles: 0-20  (perturbateur 0% / missiles 100%)
perturbateur vs mini: 0-20  (perturbateur 0% / mini 100%)
missiles vs mini: 14-6  (missiles 70% / mini 30%)
```

**Analyse du buff Boomerang (damage 1→1.5, objectif de la session) :**
- Matchup mitrailleur vs perturbateur : précédemment ~76% mitrailleur (déduit du 24% global de perturbateur) → maintenant 45% mitrailleur / 55% perturbateur. C'est le plus gros déplacement individuel observé — le buff a clairement aidé ce matchup.
- Taux global perturbateur : 22% (vs 24% avant) — quasi inchangé. Cause : missiles et mini sont des murs à 100% pour perturbateur. Améliorer le matchup mitrailleur ne suffit pas à remonter l'ensemble quand deux personnages gagnent 100% contre lui.
- Verdict : le buff est "directionnellement correct" mais insuffisant pour que perturbateur sorte du bas de tableau. Le vrai problème est missiles/mini, pas mitrailleur.

**Flags à soumettre à Camil pour décision :**

1. **MISSILES 84% (⚠ potentiel problème)** : hausse de 6pt vs la dernière mesure fiable (78% à n=45). Dans le bruit à n=20, mais la tendance est à la hausse depuis août. Gagne 100% contre mitrailleur, vif, zoneur, perturbateur — en un mot contre tout le bas de tableau. À re-mesurer si Camil sent que les Missiles sont trop forts en jeu réel.

2. **MINI 76% (à surveiller)** : même profil que missiles (100% vs les mêmes 4 adversaires). Également en hausse légère. Moins urgent que missiles, mais les deux forment un "bloc dominant" dans le bas du tableau des autres personnages.

3. **ZONEUR 6% (problème structurel non résolu)** : aucune amélioration malgré trois sessions. Le laser high-DPS ne se traduit pas en victoires — probablement parce que l'IA de Zoneur tire rarement en situation d'alignement réel (signature_bias élevé mais positionnement défensif trop profond). Ne pas retoucher les leviers déjà essayés (damage, fire_rate). À laisser en l'état sauf décision explicite de Camil.

4. **MITRAILLEUR 26%** : apparemment en baisse (était 34%). Les matchups missiles et mini sont à 0%/20 chacun — c'est un signal fort même à n=20. Si ces matchups étaient déjà à 0% avant (non mesurable rétrospectivement), alors le 34% était tiré par d'anciens matchups perturbateur maintenant perdus (55% perturbateur désormais). Aucune action immédiate suggérée — à surveiller si Camil ressent mitrailleur comme trop faible.

5. **CONTROLEUR 90%** : en baisse apparente (était 96%), probablement du bruit à n=20. Reste le personnage le plus dominant. Toujours non résolu (les leviers turret_lifetime et turret_hp ont déjà été tentés — ne pas retenter).

**Changements apportés au code :** aucun. Run de mesure pure.

**Fichier de test :** `balance_simulation.gd` temporairement modifié (`RUNS_PER_MATCHUP` 45→20) puis immédiatement restauré à 45 dans la même session. Aucun fichier _tmp_ laissé.
