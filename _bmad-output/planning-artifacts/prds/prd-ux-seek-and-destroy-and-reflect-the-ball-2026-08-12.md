---
title: 'UX/UI PRD - Seek and Destroy and Return the Ball'
game_type: 'fighting'
platforms: ['PC', 'Console']
created: '2026-08-12'
updated: '2026-08-12'
companion_to: '_bmad-output/planning-artifacts/gdds/gdd-seek-and-destroy-and-reflect-the-ball-2026-07-31/gdd.md'
---

# Seek and Destroy and Return the Ball - UX/UI PRD

**Auteur :** Camil
**Périmètre :** tout ce qui touche l'interaction, les écrans, la direction artistique et le flux joueur — pas les mécaniques de gameplay elles-mêmes (celles-ci restent dans le GDD).

2026-08-12 (Camil : "je pense que pour tout ce qui est UX il me faudrait un PRD à part, celui qu'on a est vraiment long") — extrait du GDD principal, qui a grossi au fil de plusieurs sessions de direction artistique (roster complet de prompts personnages) au point de devenir difficile à naviguer. Les sections déplacées ici (Contrôles et input, Direction artistique et audio) ont été **retirées du GDD** et remplacées par un pointeur vers ce document. Les mécaniques de jeu, le roster, les epics et les specs techniques restent dans le GDD — ce document ne les duplique pas.

---

## Contrôles et input

- Déplacement : libre en 2D, dans sa moitié de terrain.
- Sélection d'arme : bouton dédié séparé du mouvement (le mouvement n'est jamais bloqué par la sélection).
- Tir : bouton dédié, déclenche l'arme actuellement sélectionnée.
- Visée/effet de balle : contrôle directionnel + option de spin/lift au moment du renvoi.

> Note de cohérence (2026-08-12) : ce texte date de la conception initiale (GDD 2026-07-31), qui envisageait 3-4 armes par personnage. Depuis le 2026-08-09, chaque personnage n'a plus qu'une seule arme exclusive (voir GDD, roster) — la "sélection d'arme" ci-dessus est donc devenue sans objet pour la version actuelle ; à corriger/retirer si le GDD n'est pas mis à jour en parallèle.

**Écran de sélection de personnage (Versus 2P)** — clavier partagé :
- J1 : `W`/`A`/`S`/`D` pour déplacer le curseur sur la grille (2D, façon Street Fighter II), `Espace` pour valider.
- J2 : flèches directionnelles pour déplacer le curseur, `Entrée` pour valider.
- Manette : stick gauche + gâchette droite, un device par joueur (device 0 = J1, device 1 = J2).

**Carte de campagne / mini-branches** — solo, un seul joueur : flèches haut/bas pour naviguer, `Espace`/`Entrée`/gâchette droite pour valider.

---

## Écrans et flux

Inventaire des écrans existants et de leur état UX, issu de la revue de Sally (UX designer) du 2026-08-11 et des itérations qui ont suivi. Repère de flux : `TitleScreen → CharacterSelect (Versus) ou CampaignMap (solo) → MatchArena → fin de round/match → retour menu`.

### TitleScreen
État : bon, validé à l'écran. Menu 3 entrées (Nouvelle partie / Continuer la partie / Mode Versus), titre stylé bicolore, tagline "Pong x Shoot'em Up x Fighting Game", indice de nav en bas, mention "prototype — pixel art placeholder".

### CharacterSelect (Versus 2P)
**2026-08-12, refonte complète** (Camil : "on avait dit 2 lignes de 4 persos (portraits) et quand on passe sur un perso, sa description arrive, avec image full... Comme street fighter 2 en fait") — remplace l'ancienne liste texte défilante (le premier gap que Sally avait identifié le 2026-08-11).

- Une grille unique 2×4 des 8 personnages (row-major), partagée par les deux joueurs — chacun déplace son propre curseur dessus indépendamment (les deux peuvent viser la même case).
- Curseur = cadre rectangulaire épais avec coins en L ("target lock"), étiqueté J1/J2, couleur par joueur (J1 bleu clair, J2 rose). *Historique : la première version (arc fin pulsant) était quasi invisible à côté de la bordure permanente de chaque case — corrigé 2026-08-12 après retour de Camil ("il faudrait au moins les cadres de selection J1 et J2 qui bougent avec les fleches"), vérifié depuis par un test headless qui simule de vrais événements clavier (tests/character_select_nav_check.gd).*
- Chaque case de la grille et les deux grandes images de prévisualisation sont teintées à la couleur d'accent du personnage (voir table de prompts plus bas) — actuellement des **placeholders** (rectangle teinté + initiale), en attente des vrais portraits Gemini.
- Panneau de prévisualisation par joueur (gauche = J1, droite = J2) : nom, archétype + arme, grande image plein corps (~2:3, futur emplacement du rendu Gemini), statut "PRET !" une fois confirmé.
- Fond d'écran : dégradé violet → rose → orange, sunburst tournant lentement, étoiles scintillantes, silhouette d'arène floue au loin — dessiné en `_draw()` (aucune image importée), reprend le brief de la section Direction artistique ci-dessous.

### CampaignCharacterSelect
Même gabarit de liste texte que l'ancien CharacterSelect (pas encore repassé au même traitement grille/portraits) — un seul personnage jouable actuellement (Vif), les autres affichent `[bientôt disponible]`. **Gap identifié, pas encore traité :** pas de traitement visuel "verrouillé" façon CampaignMapNode (grisé + cadenas dessiné) pour ces entrées à venir.

### MatchArena (gameplay)
**Gap identifié par Sally le 2026-08-11, pas encore traité :** aucune pacing entre l'état "en attente" et le jeu réel. Le label affiche "Match 1 / Pret ? (appuyez sur Tir pour commencer)", et dès que Tir est pressé, `_match_started = true` dégèle vaisseaux + balle **dans la même frame** — zéro compte à rebours, zéro "3...2...1...GO !", zéro freeze-frame. Suggestion de Sally : un beat "Ready... Go !" dessiné (texte + flash + léger freeze de quelques frames avant dégel), dans l'esprit `_draw()`/pas d'asset externe déjà en place pour CampaignMapNode. Reste à vérifier si la fin de round/match a le même problème de zéro-pacing.

### CampaignMap
État : bon, refondu le 2026-08-11 en vrai arbre de branches/convergences dessiné (cercles/lignes/anneaux pulsants via `_draw()`, pas d'assets importés) — précédent technique pour tout traitement "carte"/"grille" du reste du jeu (CharacterSelect s'en inspire directement pour son curseur).

### MiniBranchMap
État : bon, même traitement (3 nœuds mook1 → mook2 → rival, chemin dessiné).

---

## Direction artistique et audio

### Style artistique

Piste **pixel art**, avec exigence forte de **spectacle visuel** — effets et particules riches ("que ça pète de partout"), à l'opposé d'un minimalisme austère. Direction shmup **épurée et lisible** pour les tirs (référence R-Type, Air Zonk), explicitement PAS un style bullet-hell dense (repoussoir : Ikaruga).

**Lisibilité d'état (diégétique) :**
- **PV :** HUD explicite requis (jauge de vie) — lisibilité compétitive non négociable en 1v1.
- **Armes/jauges :** décoloration/usure du vaisseau pour l'état général, transparence progressive de l'icône d'arme selon la charge manquante, puis liseré doré quand pleinement disponible.

### Audio et musique

Direction : **metal avec une touche électronique**. Le créateur est lui-même musicien — la composition musicale est une **compétence interne**, pas un poste à externaliser/budgétiser comme le serait typiquement le cas pour un développeur solo.

### Direction des portraits de personnages (pixel art "délire")

2026-08-11, Sally (UX designer) + Camil — premier passage d'art réel pour le roster (jusque-là, uniquement des formes géométriques placeholder en jeu). Référence confirmée par test : **Air Zonk / Bonk's Adventure**, déjà citée plus haut comme référence shmup — cohérent avec le style existant, pas un nouveau virage. Premier essai (Traqueur) validé par Camil : "HaHa j'adore !".

Deux formats requis par personnage : une **grande image** (pose dynamique plein corps, arme en action) et un **portrait** (buste, façon case de sélection façon Street Fighter II). L'arme réelle du personnage doit toujours être identifiable dans le prompt — jamais une arme générique.

Prompts **déjà assemblés** ci-dessous (style de base + description du perso + rappel de fond en un seul bloc) — copier-coller direct, rien à combiner à la main.

2026-08-11 v2 (Camil : "argggh il me met toujours un background sur la grosse image") — le modèle traitait "wide stance" / "mid-dash" comme une scène qui appelle un sol, et oubliait la consigne de fond noyée au milieu du prompt. Deux corrections : (1) la consigne de fond passe maintenant en **toute fin de prompt** (poids de récence plus fort sur ces modèles), (2) le perso est cadré explicitement comme "isolated character sprite floating in empty space" pour couper court à toute implication de décor/sol.

| Perso | Genre | Accent | Arme | Prompt "grande image" | Prompt "portrait" |
|---|---|---|---|---|---|
| **Traqueur** (Missiles) | Femme | Cyan / orange | Missiles téléguidés à l'épaule | v3 (2026-08-11, apres retour de Camil : "pas mal de glitches dans l'image... double main etc... on va abandonner les jumelles... pas de sourire pleine dents, un petit sourire narquois serait mieux") — jumelles retirees (source probable du glitch de mains en double, combinees a une pose deja chargee), sourire adouci en smirk, clause anatomique ajoutee : *Wacky exaggerated cartoon pixel art video game character sprite, Air Zonk / Bonk's Adventure style — chibi proportions (oversized head, compact body), huge expressive eyes, thick bold black outlines, saturated two-tone color scheme (armor + accent), hard pixel edges with cel-shaded highlights. Full-body shot, framed wide enough to show the character from head to feet including legs and feet, dynamic full-body action pose (not a close-up bust). A female hunter-type character with a confident sly smirk (not a big open-mouth grin), huge determined cartoon eyes, exaggerated shoulder-mounted missile pods way bigger than realistic mounted on her back, bright orange and cyan color scheme, hands free and relaxed — one on her hip, the other loose at her side — standing in a confident wide-legged pose. Anatomically correct: exactly two arms and two hands, no extra limbs, no duplicated hands. Isolated character sprite floating in empty space — absolutely no floor, no ground, no horizon line, no scenery, no shadow, no gradient. The entire background must be a single flat solid hot magenta color (#FF00FF), nothing else. No text/logo/watermark.* | *Wacky exaggerated cartoon pixel art video game character sprite, Air Zonk / Bonk's Adventure style — chibi proportions (oversized head, compact body), huge expressive eyes, thick bold black outlines, saturated two-tone color scheme (armor + accent), hard pixel edges with cel-shaded highlights. Female hunter character, close bust portrait, confident sly smirk (not a big open-mouth grin), one shoulder-mounted missile pod visible over her shoulder in frame, cyan and orange armor. Anatomically correct: exactly two arms and two hands, no extra limbs, no duplicated hands. Isolated character sprite floating in empty space — absolutely no floor, no ground, no horizon line, no scenery, no shadow, no gradient. The entire background must be a single flat solid hot magenta color (#FF00FF), nothing else. No text/logo/watermark.* |
| **Mitrailleur** | Homme | Bleu pâle / gris | Mitraillette full-auto | *Wacky exaggerated cartoon pixel art video game character sprite, Air Zonk / Bonk's Adventure style — chibi proportions (oversized head, compact body), huge expressive eyes, big toothy grin, thick bold black outlines, saturated two-tone color scheme (armor + accent), hard pixel edges with cel-shaded highlights. Full-body shot, framed wide enough to show the character from head to feet including legs and feet, dynamic full-body action pose (not a close-up bust). Stocky male gunner in dynamic wide stance, spraying a compact rapid-fire machine gun with a stream of tiny bullet-pixel muzzle flash, huge cocky grin, pale blue and gray armor, buzz cut hair. Isolated character sprite floating in empty space — absolutely no floor, no ground, no horizon line, no scenery, no shadow, no gradient. The entire background must be a single flat solid hot magenta color (#FF00FF), nothing else. No text/logo/watermark.* | *Wacky exaggerated cartoon pixel art video game character sprite, Air Zonk / Bonk's Adventure style — chibi proportions (oversized head, compact body), huge expressive eyes, big toothy grin, thick bold black outlines, saturated two-tone color scheme (armor + accent), hard pixel edges with cel-shaded highlights. Stocky male gunner bust portrait, gripping his machine gun close to his chest, wild excited grin, pale blue and gray color scheme. Isolated character sprite floating in empty space — absolutely no floor, no ground, no horizon line, no scenery, no shadow, no gradient. The entire background must be a single flat solid hot magenta color (#FF00FF), nothing else. No text/logo/watermark.* |
| **Vif** | Femme | Bleu électrique | Tourbillon (mini-tornade) | *Wacky exaggerated cartoon pixel art video game character sprite, Air Zonk / Bonk's Adventure style — chibi proportions (oversized head, compact body), huge expressive eyes, big toothy grin, thick bold black outlines, saturated two-tone color scheme (armor + accent), hard pixel edges with cel-shaded highlights. Full-body shot, framed wide enough to show the character from head to feet including legs and feet, dynamic full-body action pose (not a close-up bust). Lean athletic female character mid-dash, hair and jacket whipped sideways by motion, summoning a small cartoon whirlwind/tornado spinning beside her hand, electric blue and white color scheme, sly energetic smirk. Isolated character sprite floating in empty space — absolutely no floor, no ground, no horizon line, no scenery, no shadow, no gradient. The entire background must be a single flat solid hot magenta color (#FF00FF), nothing else. No text/logo/watermark.* | *Wacky exaggerated cartoon pixel art video game character sprite, Air Zonk / Bonk's Adventure style — chibi proportions (oversized head, compact body), huge expressive eyes, big toothy grin, thick bold black outlines, saturated two-tone color scheme (armor + accent), hard pixel edges with cel-shaded highlights. Lean female character bust portrait, hair swept sideways as if mid-motion, a tiny cartoon whirlwind spinning just past her shoulder, electric blue color scheme, sly smirk. Isolated character sprite floating in empty space — absolutely no floor, no ground, no horizon line, no scenery, no shadow, no gradient. The entire background must be a single flat solid hot magenta color (#FF00FF), nothing else. No text/logo/watermark.* |
| **Lourd** | Homme | Rouge-orange | Bazooka | *Wacky exaggerated cartoon pixel art video game character sprite, Air Zonk / Bonk's Adventure style — chibi proportions (oversized head, compact body), huge expressive eyes, big toothy grin, thick bold black outlines, saturated two-tone color scheme (armor + accent), hard pixel edges with cel-shaded highlights. Full-body shot, framed wide enough to show the character from head to feet including legs and feet, dynamic full-body action pose (not a close-up bust). Massive heavily-armored male character in wide stable stance, a huge oversized bazooka resting on one shoulder, warm red-orange armor plating, stoic but exaggerated determined expression. Isolated character sprite floating in empty space — absolutely no floor, no ground, no horizon line, no scenery, no shadow, no gradient. The entire background must be a single flat solid hot magenta color (#FF00FF), nothing else. No text/logo/watermark.* | *Wacky exaggerated cartoon pixel art video game character sprite, Air Zonk / Bonk's Adventure style — chibi proportions (oversized head, compact body), huge expressive eyes, big toothy grin, thick bold black outlines, saturated two-tone color scheme (armor + accent), hard pixel edges with cel-shaded highlights. Massive male character bust portrait, bazooka barrel visible resting on his shoulder in frame, red-orange armor, unshakeable stern-but-cartoonish expression. Isolated character sprite floating in empty space — absolutely no floor, no ground, no horizon line, no scenery, no shadow, no gradient. The entire background must be a single flat solid hot magenta color (#FF00FF), nothing else. No text/logo/watermark.* |
| **Spreader** (Éventail) | Femme | Jaune | Éventail qui tire des bonbons | *Wacky exaggerated cartoon pixel art video game character sprite, Air Zonk / Bonk's Adventure style — chibi proportions (oversized head, compact body), huge expressive eyes, big toothy grin, thick bold black outlines, saturated two-tone color scheme (armor + accent), hard pixel edges with cel-shaded highlights. Full-body shot, framed wide enough to show the character from head to feet including legs and feet, dynamic full-body action pose (not a close-up bust). Flamboyant female character mid-flourish, holding an ornate open folding fan that's launching a spread of small round candy-shaped projectiles, dramatic theatrical pose, bright yellow and white color scheme, big dazzling grin. Isolated character sprite floating in empty space — absolutely no floor, no ground, no horizon line, no scenery, no shadow, no gradient. The entire background must be a single flat solid hot magenta color (#FF00FF), nothing else. No text/logo/watermark.* | *Wacky exaggerated cartoon pixel art video game character sprite, Air Zonk / Bonk's Adventure style — chibi proportions (oversized head, compact body), huge expressive eyes, big toothy grin, thick bold black outlines, saturated two-tone color scheme (armor + accent), hard pixel edges with cel-shaded highlights. Flamboyant female character bust portrait, folding fan held up near her face with a couple candy-shaped projectiles visible mid-air, bright yellow color scheme, theatrical wink. Isolated character sprite floating in empty space — absolutely no floor, no ground, no horizon line, no scenery, no shadow, no gradient. The entire background must be a single flat solid hot magenta color (#FF00FF), nothing else. No text/logo/watermark.* |
| **Contrôleur** | Femme | Gris acier | Tourelles autonomes | *Wacky exaggerated cartoon pixel art video game character sprite, Air Zonk / Bonk's Adventure style — chibi proportions (oversized head, compact body), huge expressive eyes, big toothy grin, thick bold black outlines, saturated two-tone color scheme (armor + accent), hard pixel edges with cel-shaded highlights. Full-body shot, framed wide enough to show the character from head to feet including legs and feet, dynamic full-body action pose (not a close-up bust). Calm female technician character standing confidently, a small stubby autonomous turret hovering/perched beside her, arms crossed, tool-belt with gadgets, cool steel-gray and white color scheme, composed but playful smirk. Isolated character sprite floating in empty space — absolutely no floor, no ground, no horizon line, no scenery, no shadow, no gradient. The entire background must be a single flat solid hot magenta color (#FF00FF), nothing else. No text/logo/watermark.* | *Wacky exaggerated cartoon pixel art video game character sprite, Air Zonk / Bonk's Adventure style — chibi proportions (oversized head, compact body), huge expressive eyes, big toothy grin, thick bold black outlines, saturated two-tone color scheme (armor + accent), hard pixel edges with cel-shaded highlights. Female technician bust portrait, a tiny turret visible peeking over her shoulder, steel-gray color scheme, calm confident smirk. Isolated character sprite floating in empty space — absolutely no floor, no ground, no horizon line, no scenery, no shadow, no gradient. The entire background must be a single flat solid hot magenta color (#FF00FF), nothing else. No text/logo/watermark.* |
| **Zoneur** | Homme | Vert laser | Laser | *Wacky exaggerated cartoon pixel art video game character sprite, Air Zonk / Bonk's Adventure style — chibi proportions (oversized head, compact body), huge expressive eyes, big toothy grin, thick bold black outlines, saturated two-tone color scheme (armor + accent), hard pixel edges with cel-shaded highlights. Full-body shot, framed wide enough to show the character from head to feet including legs and feet, dynamic full-body action pose (not a close-up bust). Angular male character in a sharp stance, wearing a visor with a glowing green laser-sight beam projecting from one eye, holding a sleek laser rifle, laser-green and black color scheme, minimal but focused cartoon expression. Isolated character sprite floating in empty space — absolutely no floor, no ground, no horizon line, no scenery, no shadow, no gradient. The entire background must be a single flat solid hot magenta color (#FF00FF), nothing else. No text/logo/watermark.* | *Wacky exaggerated cartoon pixel art video game character sprite, Air Zonk / Bonk's Adventure style — chibi proportions (oversized head, compact body), huge expressive eyes, big toothy grin, thick bold black outlines, saturated two-tone color scheme (armor + accent), hard pixel edges with cel-shaded highlights. Angular male character bust portrait, glowing green laser-sight visor over one eye, laser rifle barrel visible at frame edge, green and black color scheme. Isolated character sprite floating in empty space — absolutely no floor, no ground, no horizon line, no scenery, no shadow, no gradient. The entire background must be a single flat solid hot magenta color (#FF00FF), nothing else. No text/logo/watermark.* |
| **Perturbateur** | Homme | Bleu pâle / violet | Boomerang | *Wacky exaggerated cartoon pixel art video game character sprite, Air Zonk / Bonk's Adventure style — chibi proportions (oversized head, compact body), huge expressive eyes, big toothy grin, thick bold black outlines, saturated two-tone color scheme (armor + accent), hard pixel edges with cel-shaded highlights. Full-body shot, framed wide enough to show the character from head to feet including legs and feet, dynamic full-body action pose (not a close-up bust). Grinning male jester-type character mid-throw, an asymmetric mismatched wacky outfit, a boomerang spinning through the air beside him, gleeful chaotic energy, pale stun-blue and purple color scheme. Isolated character sprite floating in empty space — absolutely no floor, no ground, no horizon line, no scenery, no shadow, no gradient. The entire background must be a single flat solid hot magenta color (#FF00FF), nothing else. No text/logo/watermark.* | *Wacky exaggerated cartoon pixel art video game character sprite, Air Zonk / Bonk's Adventure style — chibi proportions (oversized head, compact body), huge expressive eyes, big toothy grin, thick bold black outlines, saturated two-tone color scheme (armor + accent), hard pixel edges with cel-shaded highlights. Male jester-type character bust portrait, boomerang held up next to his face, huge mischievous "gnihihi" grin, pale blue and purple color scheme. Isolated character sprite floating in empty space — absolutely no floor, no ground, no horizon line, no scenery, no shadow, no gradient. The entire background must be a single flat solid hot magenta color (#FF00FF), nothing else. No text/logo/watermark.* |

Fond magenta uni choisi car aucune couleur d'accent du roster n'est proche du magenta (détourage sûr par sélection couleur, ex. GIMP, sans manger un bout de personnage). Si le fond persiste malgré la v2, essayer en plus : régénérer plusieurs variantes (les modèles d'image sont non-déterministes, un essai raté n'invalide pas le prompt) et/ou reformuler la pose pour éviter les mots impliquant un sol ("stance", "standing on") au profit de poses en l'air ou de cadrage buste uniquement.

**Détourage post-génération (GIMP) :** Sélectionner → Par couleur (seuil ~15-20) sur le fond magenta → `Suppr` → si liseré résiduel, Sélection → Grandir de 1px avant de supprimer. Exporter en PNG (alpha).

**Dimensions finales visées :**

| Format | Dimensions finales | Ratio | Pourquoi |
|---|---|---|---|
| Portrait (buste) | 128 × 128 px | 1:1 (carré) | Sert à la fois pour la grille de sélection et pour le gros visage façon Ryu — un carré reste lisible aux deux usages |
| Grande image (plein corps) | 256 × 384 px | 2:3 (vertical) | Assez de hauteur pour un perso debout avec son arme en action, sans être écrasé |

Gemini ne sort pas de pixel art basse résolution natif — il génère en haute résolution (souvent 1024×1024) avec un style qui imite le pixel art. Workflow : générer en carré pour le portrait / en format vertical (proche 2:3) pour la grande image si l'outil le permet (sinon générer carré et recadrer en 2:3 dans GIMP avant redimensionnement, plutôt que d'étirer) → GIMP, Image → Échelle de l'image → dimensions finales ci-dessus → **interpolation "Aucun"** impérativement (une interpolation linéaire/cubique floute les pixels au lieu de les garder nets).

### Fond de l'écran de sélection de personnage

Fond seul, sans personnage ni texte ni UI — Camil compose la grille de portraits par-dessus lui-même une fois les 8 personnages prêts, aux bons ratios. Format large (16:9) pour correspondre au viewport du jeu (1280×720).

**Prompt :**

```
Wacky vibrant arcade pixel art backdrop, Air Zonk / Bonk's Adventure
style — dynamic diagonal energy lines radiating outward from the
center, bold saturated color gradient (deep purple into hot pink into
orange), scattered small star/sparkle particles, a faint glowing
abstract arena or stage silhouette in the far distance, empty
foreground and center with no characters, no creatures, no text, no
logos, no UI elements of any kind — pure background art only for a
character-select screen. Wide 16:9 landscape format. Energetic but not
too busy or cluttered in the center/foreground, since character
portraits will be placed on top afterward and need to stay readable.
Hard pixel edges with cel-shaded highlights, no blur, no photographic
elements.
```

Dimensions finales visées : 1280 × 720 px (même downscale nearest-neighbor que les portraits une fois reçu).

**Statut (2026-08-12) :** un fond de remplacement dessiné en `_draw()` (gradient + sunburst + étoiles + silhouette d'arène) tourne déjà dans `CharacterSelect.tscn` en attendant le rendu Gemini réel — voir "Écrans et flux" ci-dessus. Le prompt reste la cible finale si/quand Camil génère l'image réelle en remplacement.
