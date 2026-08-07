---
title: 'Game Brainstorming Session'
date: '2026-08-07'
author: 'Camil'
version: '1.0'
stepsCompleted: [1, 2]
status: 'in-progress'
---

# Game Brainstorming Session

## Session Info

- **Date:** 2026-08-07
- **Facilitator:** Game Designer Agent
- **Participant:** Camil
- **Focus:** Epic 4 — Campagne solo (FR18) de *Seek and Destroy and Return the Ball*

---

_Ideas will be captured as we progress through the session._

## Brainstorming Approach

**Selected Mode:** YOLO — facilitator-driven, comprehensive technique coverage, refined via Advanced Elicitation (Meta-Prompting Analysis) into an explicit 4-phase structure so each phase's output feeds the next, rather than jumping unordered between narrative and systems thinking.

**Structural note:** *Core Loop Brainstorming* deliberately excluded — the core 1v1 loop is already built (Epic 1-2) and re-brainstorming it risks reinventing the game instead of dressing the campaign around it. Where the loop needs to flex for campaign purposes (e.g. a boss imposing a temporary constraint on the loop), that's handled inside Phase 4 (Failure State Design / Constraint-Based Creativity), not as its own technique.

**Phase 1 — Fondation (le pourquoi) :** Player Fantasy Mining, MDA Framework, Emotion Targeting → ce que chaque personnage fait ressentir en campagne, avant d'inventer du contenu.

**Phase 2 — Univers & narration :** Genre Mashup, Ludonarrative Harmony, Environmental Storytelling → quel monde, et comment le *gameplay* le raconte (pas le texte).

**Phase 3 — Structure & systèmes :** Progression Curve Sculpting, Meta-Game Layer Design, Reward Schedule Architecture, Player Agency Moments → la carte façon Soul Calibur IV, les déblocages, le branching.

**Phase 4 — Défi & boss :** Failure State Design, Constraint-Based Creativity, What If Scenarios → les boss comme pièces mécaniques, pas juste narratives.

**Focus Areas:**
- Core Gameplay Loop (comment la campagne réutilise/étend la boucle 1v1 existante, sans la réinventer)
- Player Fantasy (ce que chaque campagne perso fait ressentir)
- Narrative and World (univers, thème, ce qui relie les 8 campagnes)
- Progression Systems (déblocages, structure de carte, méta-progression)
- Challenge and Difficulty (design des boss, courbe de difficulté par perso)

### Morphological Analysis — paramètres indépendants de la campagne

| Paramètre | Options envisageables | Phase couvrante |
|---|---|---|
| Univers/thème | guerre galactique de tournois · zones/dimensions propres à chaque perso · compétition-spectacle façon jeu télévisé · post-apo sportif | Phase 2 |
| Structure de progression | carte unique à 8 branches (façon SC4) · 8 cartes séparées par perso · hub central + niveaux · linéaire simple | Phase 3 |
| Type de déblocage | variantes d'armes · cosmétiques · lore/dialogues · mini-buffs permanents | Phase 3 |
| Combats intermédiaires | 1v1 standard, IA taguée par archétype · règles spéciales par stage (handicap, arène qui rétrécit) · combats à objectif (survie, chrono) | Phase 3 **et** 4 |
| Design du boss | IA qui casse une règle du jeu · plusieurs phases · arène spéciale · mini-jeu unique | Phase 4 |
| Fil narratif par perso | origin story · rivalité · rédemption · simple "pourquoi il/elle se bat" | Phase 1/2 |
| Lien inter-campagnes | antagoniste commun · tournoi commun · 8 histoires isolées, aucun lien | Phase 2 |
| Reward loop | Exp/Gold façon SC4 · déblocage direct sans monnaie · monnaie dépensable dans un shop | Phase 3 |

**Insight clé :** les twists de règles (Failure State Design, Constraint-Based Creativity) ne doivent pas être réservés qu'au boss final — un stage normal peut déjà casser une règle (arène qui rétrécit, handicap temporaire) pour garder la campagne vivante entre les gros combats. Phase 4 s'applique potentiellement à *tous* les stages, pas seulement au boss.

### Graph of Thoughts — réseau caché entre les phases

- **Player Fantasy Mining (P1) ↔ Player Agency Moments (P3)** : le fantasme d'un perso doit se matérialiser en un vrai choix, pas juste du flavor text (ex. Lourd "inarrêtable" → un stage où être lent et puissant bat littéralement un obstacle basé sur la vitesse).
- **Emotion Targeting (P1) ↔ Failure State Design (P4)** : ce que *perdre* fait ressentir doit matcher l'émotion cible du perso (perdre avec Perturbateur = "je me suis fait avoir", pas juste "j'ai plus de PV").
- **Ludonarrative Harmony (P2) ↔ Constraint-Based Creativity (P4)** — lien le plus fort du graphe : la règle cassée d'un boss *est* le climax narratif exprimé mécaniquement, pas un reskin. Narration (P2) et boss (P4) doivent se concevoir ensemble.
- **Environmental Storytelling (P2) ↔ Meta-Game Layer Design (P3)** : la carte façon SC4 n'est pas qu'un système de progression — son état visuel raconte déjà une histoire sans texte.

**Pattern révélé :** la structure n'est pas un pipeline strict 1→2→3→4 mais une **étoile** — Phase 1 (fantasme/émotion par perso) irrigue directement 2, 3 et 4 en parallèle, et 2↔4 doivent être pensées en aller-retour. On garde l'ordre de travail comme fil conducteur, mais on boucle explicitement vers P1/P2 au moment de designer les boss.

### Second-Order Thinking — effets en cascade de démarrer par Phase 1

**Risque identifié :** épuiser Phase 1 sur les 8 persos avant de toucher l'univers (P2) peut produire 8 tons incompatibles (noir/heist à côté de sport-anime à côté de post-apo) — fragmenté, et ça fragilise un éventuel lien inter-campagnes.

**Séquence révisée qui en découle :** passage léger sur P1 (une phrase de fantasme par perso) → P2 pour poser un **cadre englobant élastique** (le classique "tournoi de gladiateurs" façon jeu de combat — Street Fighter, Tekken, SC4 lui-même — qui laisse chaque combattant garder un ton radicalement différent sous une même bannière) → *ensuite* on approfondit P1 perso par perso à l'intérieur de ce cadre → P3 → P4.

**Conséquence sur la grille morphologique :** "Lien inter-campagnes" penche vers **tournoi commun** (structure la plus sûre pour cette séquence sans fragmentation) plutôt que "8 histoires isolées" — à confirmer/challenger en Phase 2, pas figé définitivement.

### Constraint Injection — "pas de texte de narration, tout passe par le gameplay/l'environnement"

**Contrainte appliquée :** aucune boîte de dialogue, aucun pavé de lore. Tout ce que le joueur comprend de l'histoire/du perso/du boss doit passer par ce qu'il voit ou joue.

Ce que ça force :
- **Intro perso :** vignette silencieuse (pose/environnement qui parle seul), pas de texte de backstory.
- **Victoire/défaite de stage :** sting visuel exploitant l'existant (bouclier à orbes qui explose dans la couleur du vainqueur ; défaite lisible dans l'archétype — pods de Missiles qui crachotent, Mini qui recule de façon disproportionnée).
- **Carte du monde :** nœuds verrouillés en silhouette/brume, palette de l'antagoniste qui "bave" sur l'art à mesure qu'on approche du boss final.
- **Reveal de la règle cassée du boss :** télégraphié dans l'arène avant le combat (forme d'arène inhabituelle, tourelle ennemie déjà visible), pas annoncé par dialogue.
- **Reveal de déblocage :** le bouclier à orbes gagne une nouvelle couleur/orbe au moment de la victoire, pas de popup de stats.

**Évaluation :** la règle brute ("zéro texte, jamais") est trop dure — titres de chapitre et noms de perso restent acceptables. Ce qu'il faut vraiment garder : **zéro texte *expositoire*** (pas de pavés de lore), pas zéro texte tout court.

## Ideas Generated

### Phase 1 — Player Fantasy Mining (passage léger, une ligne par perso)

**[Fantasme #1] Lourd** : Inébranlable, indestructible
_Core Loop_ : encaisser sans broncher, faire sentir à l'adversaire que rien ne le fait bouger
_Novelty_ : le fantasme du mur — le joueur ne fuit jamais, il absorbe

**[Fantasme #2] Contrôleur** : Je gère la situation, je gère l'autre
_Core Loop_ : imposer le rythme, forcer l'adversaire à jouer sur son terrain (tourelle)
_Novelty_ : puissance par la maîtrise de l'espace, pas par la force brute

**[Fantasme #3] Mitrailleur** : Je suis un bourrin
_Core Loop_ : arroser, ne jamais lâcher la gâchette
_Novelty_ : simplicité assumée — la puissance dans le volume, pas la finesse

**[Fantasme #4] Vif** : Insaisissable, intouchable
_Core Loop_ : ne jamais être là où l'adversaire tire
_Novelty_ : le fantasme de l'évasion permanente — gagner en n'étant jamais touché

**[Fantasme #5] Zoneur/Précision** : Où que je sois, je touche ma cible — un vrai sniper
_Core Loop_ : viser, toucher, peu importe la distance/position
_Novelty_ : la certitude du tir — le contraire du hasard

**[Fantasme #6] Perturbateur** : Gnihihi, je suis pénible !
_Core Loop_ : emmerder l'adversaire, casser son rythme, rire en le faisant
_Novelty_ : le seul fantasme volontairement malveillant/joueur du roster — la puissance par l'agacement

**[Fantasme #7] Missiles téléguidés** : Je fais courir l'adversaire partout
_Core Loop_ : forcer le déplacement constant par la menace omniprésente
_Novelty_ : pression sans contact direct — l'adversaire se bat contre l'espace, pas juste contre moi

**Décision de nommage (2026-08-07) :** le personnage "Mini" est renommé **Éventail**, pour prendre le nom de son arme signature — cohérent avec Perturbateur/Zoneur dont l'identité vient déjà de leur arme. À répercuter dans `data/characters/mini.tres` et le code une fois la session terminée.

**[Fantasme #8] Éventail (ex-Mini)** : Quitte ou double
_Core Loop_ : tout miser sur une salve unique plutôt que l'endurance
_Novelty_ : cohérent avec l'arme (5 tirs simultanés, 1 fois/sec, pas de sustained fire) — le seul perso du roster qui joue le tout-ou-rien plutôt que la gestion de ressource continue

**Connexions repérées :**
- Lourd (inébranlable) ↔ Vif (insaisissable) : polarité pure, pile-face du roster
- Contrôleur (gérer l'espace) ↔ Perturbateur (gérer par le chaos) : deux formes de contrôle, une posée, une chaotique
- Zoneur (certitude) ↔ Missiles (pression constante) : deux versions de la pression à distance, l'une précise, l'autre omniprésente

**Idée/thème noté pour plus tard (Camil, 2026-08-07) :** le lore/fantasme de chaque perso peut informer l'équilibrage mécanique, pas juste la narration — ex. Lourd "inébranlable" pourrait justifier plus de PV mais moins de vitesse, Vif "insaisissable" l'inverse, Éventail "quitte ou double" un pool de PV plus bas compensé par le burst de dégâts. **Explicitement mis de côté pour plus tard** — hors scope de cette session (Epic 2 balance est un chantier continu séparé, voir NFR4), à revisiter quand on retouchera les stats.

---

### Phase 2 — Univers & narration (Genre Mashup, Ludonarrative Harmony)

**[Univers #1] Tournoi chaotique façon cartoon** : "combat" + "sport-spectacle" + "chaos assumé façon cartoon" (Camil, 2026-08-07)
_Core Loop narratif_ : un tournoi dont les règles elles-mêmes sont un peu n'importe quoi, ça part en cacahuète en permanence — plus Looney Tunes/WarioWare qu'une compétition sérieuse et cadrée
_Novelty_ : cadre assez élastique pour laisser cohabiter 8 tons radicalement différents (mur increvable, sniper certain, trublion, quitte-ou-double) sans les lisser — validé par Camil ("2" au choix binaire spectacle-sérieux vs chaos-cartoon)

**[Univers #2] L'organisateur du tournoi = boss final commun** (construit ensemble, validé par Camil : "ça me botte !")
_Core Loop narratif_ : l'entité qui organise le tournoi invente les règles au fur et à mesure du chaos ambiant — et au combat final, elle casse SA PROPRE règle
_Novelty_ : ferme la boucle Ludonarrative Harmony ↔ Constraint-Based Creativity repérée en Graph of Thoughts — "pourquoi le boss ne respecte pas les règles normales" a une réponse diégétique directe : c'est lui qui les invente. Donne aussi une réponse à "Lien inter-campagnes" (grille morphologique) : tournoi commun, chapeauté par une figure récurrente plutôt que 8 histoires isolées.

**Question ouverte pour la suite :** à quoi ressemble/ce que dégage cet organisateur (entité, machine, présentateur exubérant...) ? Écho possible avec Perturbateur (déjà "gnihihi, je suis pénible") — famille de trublions, ou volontairement sans lien ?

**[Univers #3] L'organisateur = présentateur exubérant, référence Dragon Ball (premier arc / Tenkaichi Budôkai)** (Camil, 2026-08-07)
_Core Loop narratif_ : présentateur haut en couleur, énergie théâtrale et un peu ridicule, ambiance tournoi d'arts martiaux scrappy/attachant plutôt que spectacle corporate léché
_Novelty_ : ancre le ton précisément — comique et chaleureux, pas cynique ; confirme la direction "chaos cartoon" plutôt que "spectacle sérieux façon jeu télévisé"

**Builds validés (Camil, 2026-08-07 : "ça me branche tout à fait, c'est ce que j'avais en tête") :**
- L'organisateur est une **présence récurrente tout du long**, pas un simple reveal final — c'est lui qui introduit le twist de règle des stages à rebondissement (relie l'insight morphologique : les combats intermédiaires peuvent déjà casser une règle, pas seulement le boss).
- Son combat final **pioche dans le kit de chaque personnage du roster** plutôt que d'avoir sa propre arme unique — cohérent avec "c'est lui qui invente toutes les règles/kits du tournoi".

### Phase 3 — Structure & systèmes (Player Agency Moments)

**[Structure #1] Les 8 branches = qualifications pré-tournoi, pas le tournoi lui-même** (construit ensemble suite à une objection de Camil : "pourquoi le joueur choisirait l'ordre, mais pas ses adversaires ?" — résolu, "ça tient la route")
_Core Loop_ : chaque branche retrace le parcours qualificatif d'un perso — adversaires fixes et non négociables à l'intérieur d'une branche (logique de tournoi respectée) ; mais l'**ordre dans lequel le joueur visite les 8 branches** est libre, puisque ce ne sont pas des matchs officiels simultanés, ce sont 8 histoires distinctes qui ont mené au même point
_Novelty_ : résout la tension "tournoi = pas de choix" vs "carte SC4 = choix libre du chemin" en séparant proprement structure narrative (qualifs, libres) de structure compétitive (bracket, fixe) ; les 8 branches convergent ensuite vers un **acte final fixe** : le vrai tournoi, contre l'organisateur
_Bonus optionnel noté :_ le format qualif' bordélique/non-linéaire pourrait lui-même être une excentricité de l'organisateur plutôt qu'une simple facilité de gameplay

**[Structure #2] Déblocages = "trace" de l'adversaire vaincu, façon Mega Man** (idée de Camil, adaptée ensemble — validé "C'est génialissime")
_Core Loop_ : le kit de base du perso joué reste fixe dès le début du match (règle FR9 intacte) — mais battre un adversaire dans sa branche débloque une **variante bonus inspirée de cet adversaire** (pas son arme copiée-collée : une saveur — ex. battre un Lourd débloque une esquive plus "tanky", battre un Zoneur débloque une précision accrue temporaire)
_Novelty_ : tranche définitivement la question "type de déblocage" de la grille morphologique (c'était ouvert entre variantes d'armes / cosmétiques / lore / buffs) — la réponse est "une trace mécanique de l'adversaire vaincu", spécifique à ce combat précis, pas un objet générique pioché dans un pool. Emprunte le fun Mega Man ("j'absorbe un peu de ce que je viens de vaincre") **sans** réduire à une seule histoire/un seul protagoniste — chacune des 8 campagnes garde son intégralité, contrairement à la version Mega Man pure (protagoniste neutre unique) explicitement écartée par Camil car elle réduisait le temps de jeu et cassait le travail sur les 8 fantasmes.

**[Structure #3] Chaque branche perso = mini-arcs à 7 rivaux potentiels, 3-4 requis** (construit ensemble à partir d'une idée de Camil)
_Core Loop_ : dans la campagne de Vif (par ex.), 7 mini-branches possibles existent (une par autre archétype du roster). Chacune est une **mini-arc en 3 temps** : 2 combats contre des "sous-adversaires" (mooks, version mineure de l'archétype rival) → le "vrai" rival de cette mini-branche → un bout de son arme débloqué. Le joueur doit compléter **3-4 des 7 mini-branches** pour se qualifier au tournoi final (pas toutes) — choix libre desquelles.
_Novelty_ : force la rejouabilité de façon organique (Camil : "ça force la rejouabilité") — refaire la campagne de Vif en choisissant d'autres mini-branches donne un Vif transformé différemment. Donne aussi un rôle clair à Exp/Gold (réf SC4) : les sous-adversaires (mooks) rapportent l'Exp/Gold (monnaie d'effort/échauffement), le "vrai" rival de la mini-branche rapporte le déblocage significatif (bout d'arme) — sépare proprement grind et récompense.

## Themes and Patterns

- **Polarité assumée dans le roster** (Lourd/Vif, Contrôleur/Perturbateur) — le tournoi chaotique peut jouer là-dessus en opposant délibérément des styles pendant la progression.
- **Le lore informe potentiellement le mécanique**, pas l'inverse — noté pour plus tard, pas dans le scope de cette session.
- **Narration sans texte expositoire** (Constraint Injection) + **chaos cartoon** se renforcent naturellement : un univers cartoon se raconte très bien par le visuel/l'animation plutôt que par du texte.

## Promising Combinations

_À compléter._
