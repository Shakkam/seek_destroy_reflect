---
title: 'Session de Brainstorming Jeu'
date: '2026-07-29'
author: 'Camil'
version: '1.0'
stepsCompleted: [1, 2, 3, 4]
status: 'complete'
---

# Session de Brainstorming Jeu

## Infos Session

- **Date :** 2026-07-29
- **Facilitateur :** Agent Game Designer
- **Participant :** Camil

---

_Les idées sont capturées au fil de la session._

## Approche de Brainstorming

**Mode sélectionné :** Guidé — le facilitateur accompagne le participant à travers les techniques une par une.

**Techniques disponibles :**
- MDA Framework
- Player Fantasy Mining
- Core Loop Design
- Genre Mashup
- Emotion Mapping
- Moment Design
- Flow Analysis
- Constraint Box
- Reference Blending
- What If Scenarios

**Zones de focus :**
- Boucle de gameplay centrale
- Fantasme du joueur
- Mécaniques et dynamiques de jeu
- Expérience esthétique
- Systèmes de progression
- Défi et difficulté
- Fonctionnalités sociales/multijoueur
- Narration et univers
- Direction artistique et feel
- Monétisation (si applicable)

---

## Concept de base (idée germe)

Hybride Pong × shoot'em up, prototypé à l'origine en Flash il y a ~20 ans. Deux vaisseaux spatiaux font office de "raquettes". Objectif : détruire le vaisseau adverse, pas juste marquer des points. Orienter/renvoyer la balle permet de récupérer des power-ups (mitrailleuse, tourelle, etc.) qui permettent de tirer sur l'adversaire pour baisser ses PV. À l'origine, rater la balle donnait un power-up à l'adversaire ou baissait les PV du joueur qui rate (souvenir imprécis, traité comme un espace de conception ouvert).

## Réponses capturées jusqu'ici

1. **Rater la balle** → donne un power-up à l'adversaire, et/ou baisse les PV du joueur qui a raté (les deux restent sur la table).
2. **La balle elle-même ne fait aucun dégât** → elle doit être rattrapée/renvoyée façon Pong ; les dégâts viennent uniquement des armes.
3. **Mouvement** → le mouvement libre en 2D plaît (esprit Windjammer), pas cantonné à un seul axe/couloir.

## Core Loop Design — Direction retenue : Option C — Double objectif

Le joueur doit gérer simultanément deux exigences concurrentes : renvoyer la balle (sous peine de perte de PV / donner un power-up à l'adversaire) ET esquiver les tirs ennemis une fois que l'adversaire a une arme. Le mouvement libre en 2D crée le dilemme positionnel entre "où dois-je être pour la balle" et "où dois-je être pour éviter les tirs".

**Boucle brouillon :**
1. La balle approche → il faut se repositionner pour la renvoyer
2. Pendant ce temps, l'adversaire armé tire → il faut esquiver
3. Balle ratée → l'adversaire récupère un power-up (ou le joueur perd des PV)
4. Renvoi réussi → la balle traverse le terrain, passe potentiellement par une zone de spawn de bonus, puis défie l'adversaire
5. On recommence, les deux joueurs s'arment de plus en plus au fil du temps

## Questions ouvertes — Réponses obtenues

- **Visée** : OUI — le joueur peut orienter/viser le renvoi de la balle, façon Pong. Idée bonus : donner à la balle des options d'**effet/spin** (par ex. la "lifter") pour courber sa trajectoire — ajoute une couche de skill expression au-delà du simple angle.
- **Interaction balle/tirs** : les tirs ennemis ne détruisent NI ne dévient la balle — balle et tirs sont des couches/préoccupations séparées.
- **Économie d'armes** : munitions limitées (à recharger), et **chaque personnage/vaisseau a des armes différentes** — implique un roster de personnages asymétrique, pas un loadout universel unique.
- **Condition de victoire** : PV à zéro uniquement (K.O. pur façon shmup) ; pas de compteur séparé de "balles ratées".

## Idées mises de côté

- **Mécanique de charge** (garder la balle en jeu plus longtemps → bonus suivant plus gros) : REJETÉE — le rally profite symétriquement aux deux joueurs, donc ne crée aucune tension/avantage significatif pour l'un ou l'autre camp. Pourrait ressurgir plus tard sous une forme asymétrique (par ex. charge liée à la précision/skill individuel de renvoi du joueur plutôt qu'à la durée partagée du rallye), mais pas intéressant à poursuivre tel qu'initialement formulé.

- **Mécanique de bouclier/blocage actif du corps** : MISE DE CÔTÉ — le joueur pourrait bloquer certains tirs, mais cela l'empêcherait temporairement de renvoyer la balle, forçant un choix "je bloque ce tir" vs. "je vais chercher la balle". Pas rejetée d'emblée, juste différée — pourrait être revisitée plus tard.

**Statut de session :** Core Loop Design résolu — visée/effets, séparation balle/tirs, armes asymétriques et condition de victoire sont verrouillés comme directions fortes. Les deux mécaniques différées (charge, bouclier) sont mises de côté. Passage à **Player Fantasy Mining**.

## Player Fantasy Mining

Mélange pondéré confirmé par le participant : **un peu de Duelliste Réactif**, **pas mal de Pilote en Montée en Puissance**, et **beaucoup de Stratège du Positionnement**.

- **Stratège du Positionnement (dominant)** : la majeure partie du temps de jeu est consacrée à la gestion de l'espace sur le terrain — le mouvement libre en 2D compte car lire et contrôler le territoire est la compétence première, pas juste les réflexes.
- **Pilote en Montée en Puissance (secondaire)** : forte sensation de passer de fragile/désarmé à une forteresse volante au fil du match, portée par les power-ups collectés.
- **Duelliste Réactif (accent)** : pics de réflexe aigus spécifiquement au moment de renvoyer la balle — timing de précision sous pression, mais c'est un pic, pas l'état constant.

**Implication de design** : le jeu doit récompenser la *conscience et le contrôle spatial* comme compétence centrale, avec le *réflexe* comme compétence secondaire en pic pendant les échanges de balle, et la *montée en puissance* comme sensation de méta-progression sur la durée d'un match.

**Conception des arènes** : lancement avec un terrain nu/neutre (pas d'obstacles) pour garder la boucle centrale pure et lisible. Extension future : arènes/stages additionnels avec des éléments de terrain (obstacles, zones de couverture, murs destructibles) pour ajouter de la profondeur au jeu de positionnement plus tard — explicitement différé après la version initiale, non bloquant pour la boucle centrale.

## MDA Framework

**Mechanics (règles établies) :** renvoi de balle avec visée + effets de spin, PV par vaisseau, ramassage de bonus/armes via la balle, armes asymétriques à munitions limitées, mouvement libre en 2D, balle/tirs sur des couches séparées sans interaction, défaite = PV à 0.

**Dynamics (réponses capturées) :**

1. **Structure du terrain** : frontière centrale claire, chaque joueur cantonné à sa propre moitié (façon Pong/Windjammer) — PAS d'infiltration sur tout le terrain. Renforce le cadrage "défendre mon territoire" en plus du jeu de positionnement.
2. **Contenir la course à l'armement** : les munitions s'épuisent assez vite et ne font que *recharger/remplir les armes que le joueur possède déjà* plutôt que d'en accorder de nouvelles librement. Système émergent : le **vaisseau a 3-4 armes différentes de puissance variable**, chacune nécessitant une **jauge à remplir via la collecte de bonus** avant de pouvoir être activée — explicitement comparé aux barres de super-jauge de Street Fighter 6 (jauges à paliers, ex. Niv 1/2/3). Les armes plus puissantes sont sous-entendues comme plus rares/plus difficiles à charger. Ceci reformule les "power-ups" d'un ramassage aléatoire vers un **système de gestion de ressources actif** — renforçant le pilier "stratège du positionnement" (on se bat pour les bonus délibérément, pas passivement).
3. **Rythme des matchs** : matchs courts et intenses — Street Fighter / Windjammer / Smash Bros référencés comme modèles de rythme (rounds rapides, pas de longues sessions).

**Vérification Aesthetics** : le système d'armes à jauges soutient directement le ressenti visé (contrôle > chaos) mieux que des ramassages aléatoires — remplir les jauges est en soi un sous-objectif spatial/stratégique (il faut se battre pour les bons bonus), pas juste un coup de chance. Le rythme court des matchs soutient la fantasy "pic de réflexe + montée en puissance" sans transformer le mid-game de contrôle positionnel en fatigue.

**Suivi ouvert — répondu :**

- **Kit fixe par personnage** : chaque vaisseau/personnage a un set FIXE de 3-4 armes connu dès le début du match (pas de déblocages aléatoires en cours de match) — explicitement comparé aux coups spéciaux de Street Fighter. C'est central pour l'identité du roster — tout l'intérêt d'avoir un roster est que les joueurs apprennent et choisissent un personnage pour son kit connu.
- **Structure des jauges (partagée vs par arme)** : PAS décidé — nécessite prototypage/playtests pour trancher. Tendance actuelle : **penche vers une jauge par arme** plutôt qu'une jauge partagée unique, mais contrainte de priorité explicite : **doit rester simple** — pas de système de ressources sur-conçu. À traiter comme une question ouverte de prototypage, pas une décision de design verrouillée.

**Statut de session MDA** : Mechanics/Dynamics/Aesthetics tous capturés et alignés. La granularité des jauges d'armes (partagée vs par arme, nombre de paliers) est signalée comme un élément **à trancher au prototypage** plutôt qu'une décision de brainstorming.

## Genre Mashup

Genres sélectionnés par le participant à injecter dans le mix central Pong × shmup × fighting-game :

1. **Lane MOBA** — le terrain pourrait comporter des tourelles automatiques ou des points de contrôle neutres à capturer, en lien avec l'idée déjà différée d'"arènes futures avec éléments de terrain". Non bloquant pour la boucle centrale ; une fonctionnalité de variante/arène ultérieure.
2. **Sport arcade (façon Rocket League)** — mécaniques de trick-shot sur les renvois de balle : des renvois stylés/risqués récompensent des effets bonus (remplissage de jauge supplémentaire, dégâts bonus, etc.). Renforce la mécanique "spin/visée sur la balle" déjà verrouillée — les trick shots sont essentiellement de la skill expression par-dessus.
3. **Campagne solo — RPG ou "façon ActRaiser"** — le participant a explicitement référencé ActRaiser (SNES) comme modèle tonal/structurel : alterne des séquences d'action-combat avec une méta-couche différente (dans le cas d'ActRaiser, de la gestion de ville/god-sim). Implique que le mode solo ne serait pas juste "des matchs IA en série" mais entrelacerait les duels Pong-shmup avec une couche secondaire distincte (progression RPG, construction de base, narration, ou similaire — le genre de la deuxième couche reste ouvert).

**Implication de design** : le mode versus/compétitif (le concept central) reste épuré et pur ; le mode solo/campagne est là où l'ambition structurelle (éléments MOBA, méta-couche RPG/ActRaiser) est explorée, sans complexifier la boucle centrale en face-à-face.

**Questions ouvertes — répondues :**

1. **Deuxième couche de la campagne** : tendance vers progression par personnage + histoire légère, PAS de construction de base. Concept : **campagne par personnage du roster** (chaque personnage a sa propre histoire), avec **évolution de personnage/vaisseau basée sur des déblocages** (progression/déblocages façon Soulcalibur référencés), une **carte du monde légère** pour naviguer entre les combats, et un **boss final** couronnant la campagne de chaque personnage. Le participant a signalé une faible confiance/forme encore floue — à traiter comme une forte tendance directionnelle, pas une décision verrouillée.
2. **Tourelles/points de contrôle MOBA** : confirmé comme une **variante d'arène du mode versus** (pas exclusif à la campagne), qui pourrait aussi apparaître dans un sous-ensemble de combats de campagne. Explicitement **pas une priorité V1** — différé aux côtés de l'idée précédente d'"arènes futures".

**Statut de session Genre Mashup** : matériel directionnel solide capturé à la fois pour les variantes du mode versus (trick shots, variantes d'arène MOBA) et la forme de la campagne solo (histoire par personnage + déblocages façon Soulcalibur + carte du monde + boss final). Tout est signalé comme post-boucle-centrale / scope ultérieur, gardant la V1 focalisée sur la boucle centrale versus épurée.

## Emotion Mapping

Courbe émotionnelle à travers un match typique, confirmée par le participant comme juste :

1. **Début de match (les deux désarmés)** : tension prudente, tâtonnement mutuel — premiers échanges de balle pour lire le rythme de l'adversaire. Les enjeux ne sont pas encore mortels, mais la pression territoriale est déjà présente.
2. **Premiers ramassages de bonus / début de charge des jauges** : excitation contenue, urgence discrète — "je dois défendre CETTE balle" devient plus important puisque la rater profite à l'adversaire. Début d'une sensation de course.
3. **Milieu de match (les deux ont des armes actives)** : double vigilance et stress — le "double objectif" central (balle + esquive) atteint ici son pic d'intensité de jonglage cognitif.
4. **Un joueur prend l'avantage (armes/PV)** : celui qui mène ressent une montée de puissance/contrôle ; celui qui est mené ressent de l'urgence et une pression "quitte ou double", le poussant vers des jeux plus risqués (ex. trick shots).
5. **Fin de match / coup de grâce** : climax net et lisible — le gagnant doit sentir que c'est gagné par la maîtrise spatiale + le timing, pas par un coup de chance aléatoire.

**Idée différée** : le participant a aimé l'idée de petits retournements/renversements de situation (façon dynamique Smash Bros où un joueur mené peut spectaculairement recoller), mais explicitement signalé comme **pas maintenant** — une mécanique de scope ultérieur à revisiter, pas partie du design central actuel.

## Idée additionnelle — Note de scope long terme

Le participant a signalé que le focus long terme du projet se concentrera probablement sur le **mode versus** en priorité, et a évoqué l'idée de **matchs en double/2v2** comme mode futur à explorer. Marqué "à suivre" — pas développé davantage pour l'instant, purement un repère pour une idéation future (nécessiterait sa propre passe sur comment les règles de balle/territoire/positionnement s'adaptent à un terrain 2v2).

## Constraint Box

Quatre contraintes créatives testées pour stress-tester le concept :

### A. Un seul bouton (+ mouvement)

Réponse : jouable mais pas trivial. Piste retenue : **appui long + direction pour sélectionner une arme parmi le kit, tir rapide/automatique une fois l'arme sélectionnée**. Explicitement signalé comme peu pratique pour les armes de type tourelle — **confirmé : la tourelle se pose librement** (placement libre sur le terrain) plutôt que d'être visée/dirigée activement par le joueur, une fois posée elle agit de façon autonome.

### B. Vue fixe et serrée, pas de scrolling

Réponse : jouable si les **types de tir restent fun mais visuellement peu encombrants** — référence explicite aux armes du jeu **Air Zonk** (PC Engine), citées comme simples et amusantes visuellement, comme direction artistique/gameplay pour les effets de tir. Confirme que la lisibilité en vue serrée dépend surtout du choix de direction artistique des projectiles, pas d'un problème de design fondamental.

### C. Match ultra-court (30s max)

Réponse : implique probablement un **choix d'arme fait avant chaque "set"** plutôt qu'un déblocage dynamique en cours de match — le joueur pré-sélectionne son arme pour le set à venir, ce qui accélère le rythme sans sacrifier le choix stratégique.

### D. Zéro texte, zéro HUD — Système de lisibilité visuelle pure (idée forte)

Réponses détaillées, à retenir comme piste de direction artistique/UI concrète :

- **PV** : communiqués par une **décoloration progressive du vaisseau** et/ou des **marques d'usure/dégâts visibles** sur le modèle — pas de barre de vie affichée.
- **Armes (état "non chargée")** : l'icône/image de l'arme sur le vaisseau devient **progressivement transparente** en fonction de la charge manquante.
- **Armes (état "chargée/disponible")** : l'image de l'arme **redevient colorée**, puis s'entoure d'un **liseré doré** (ou couleur distinctive) quand elle est pleinement disponible pour activation.

**Implication de design** : ce système de lisibilité 100% diégétique/visuel (pas de HUD texte) est cohérent avec le pilier "contrôle spatial" — le joueur doit lire l'état de jeu directement sur les vaisseaux à l'écran, ce qui renforce l'attention portée au terrain plutôt qu'à une interface superposée. Fort candidat à retenir comme direction UI/UX pour le jeu, au-delà du simple exercice de contrainte.

**Statut de session Constraint Box** : les 4 contraintes ont produit des pistes concrètes et exploitables — notamment le système de lisibilité visuelle pure (D) qui pourrait devenir une direction artistique/UX réelle du jeu, pas juste un exercice théorique. Tourelle confirmée : **placement libre sur le terrain**, agit ensuite de façon autonome (pas de visée active par le joueur).

## Reference Blending

Liste de références consolidée, avec ce que chaque jeu apporte précisément au concept :

- **Pong** — le duel de renvoi, la frontière centrale, l'échange balle-pour-balle
- **Windjammer** — mouvement libre en 2D confiné à sa moitié de terrain, sensation arcade rapide en 1v1
- **Street Fighter 6** — roster à kits fixes/identité de personnage, système de jauges à paliers (super meter)
- **Rocket League** — trick-shots stylés sur les renvois, récompense du risque esthétique
- **Smash Bros** — rythme de match ; dynamique de comeback (idée actuellement différée, pas core)
- **Soulcalibur** — structure de déblocage/progression pour le mode campagne
- **ActRaiser** — alternance séquences d'action + méta-couche (histoire/progression) pour la campagne solo
- **Air Zonk** (PC Engine) — direction artistique des tirs : fun, coloré, peu encombrant visuellement
- **R-Type** — référence shmup pour la sensation de tir/esquive épurée et lisible (confirmé ci-dessous)

**Réponses complémentaires :**

1. **Référence shmup pour le tir/esquive** : explicitement PAS Ikaruga ("trop plein de boulettes", trop chargé). Direction voulue : quelque chose de plus **épuré**, façon **Air Zonk** et **R-Type** — lisibilité et clarté des projectiles plutôt que densité de pattern façon danmaku.
2. **Direction artistique globale** : pas encore tranchée. Piste évoquée : **pixel art**, mais avec une exigence forte — "il faut que ce soit beau et que ça pète de partout avec des effets dingues" (effets visuels/particules riches et spectaculaires par-dessus une base pixel art, pas un style minimaliste austère). Traiter comme direction ouverte à explorer avec un artiste/référence visuelle plus tard.
3. **Repoussoirs explicites** :
   - **Ikaruga** — évité pour son côté illisible/surchargé de projectiles
   - **Brawl Stars** — évité pour son rythme perçu comme "lent", qui ne correspond pas à l'énergie recherchée

**Statut de session Reference Blending** : liste de références solidifiée, avec un axe clair "shmup épuré et lisible" (R-Type/Air Zonk) plutôt que "bullet hell dense" (anti-Ikaruga), et une direction artistique encore ouverte mais cadrée par l'exigence "beau + spectaculaire" plutôt que minimaliste.

---

## Résumé de session final

### Concept le plus prometteur

**Hybride Pong × Shoot'em Up × Fighting Game** — deux vaisseaux s'affrontent sur une arène divisée (frontière centrale claire, façon Pong/Windjammer). Le mouvement libre en 2D dans la moitié de chaque joueur crée un dilemme positionnel entre renvoyer la balle et esquiver les tirs ennemis. La balle ne fait jamais de dégâts directement et n'interagit jamais avec les tirs — c'est purement la mécanique de capture de ressource (visée + effets de spin/lift pour la skill expression). Les armes viennent d'un **kit fixe, spécifique au personnage** (identité de roster, à la Street Fighter), débloquées en match via la charge de jauges (jauges façon SF6) alimentées par les renvois de balle réussis — la structure exacte des jauges (partagée vs par arme) est différée au prototypage. Les matchs sont courts et intenses (rythme Street Fighter / Windjammer / Smash Bros). Victoire = PV adverses à zéro.

Direction artistique/UX renforcée par le Constraint Box : un système de **lisibilité 100% visuelle/diégétique** (usure du vaisseau pour les PV, transparence puis liseré doré pour les armes/jauges), et un axe shmup **épuré et lisible** (R-Type/Air Zonk) plutôt que bullet-hell dense.

### Pourquoi ça se démarque

Ça résout la tension de design originale (comment la balle compte-t-elle une fois le mouvement en 2D libre) avec une réponse nette : la balle reste le seul objet de lutte pour la ressource, tandis que les dégâts de combat sont entièrement séparés dans un système d'armes/jauges. Cela produit la fantasy de joueur visée — **stratège du positionnement** dominant, avec des **pics de réflexe** sur les renvois de balle et un **arc de montée en puissance** sur la durée du match — sans que la boucle ne dégénère en chaos de ramassage aléatoire.

### Deuxième choix / couche de scope

**Le mode versus comme focus long terme**, avec des **variantes d'arène** optionnelles (tourelles/points de contrôle façon MOBA, autres types de terrain) superposées à la même boucle centrale — explicitement différé après la V1, non bloquant. Un mode **doubles/2v2** a aussi été évoqué comme piste future à explorer séparément.

### Mention honorable

**Campagne solo, inspirée d'ActRaiser** : arcs narratifs par personnage du roster, progression de déblocage façon Soulcalibur, une carte du monde légère, et un boss final par personnage. La direction est floue/peu certaine mais fortement appréciée — un bon candidat pour une session d'idéation dédiée future.

### Insights clés

- La tension balle/mouvement (mouvement 2D libre vs l'économie à 1 objet inhérente au Pong) est le risque de design central, et a été résolue en séparant nettement "balle = ressource à capturer" de "armes = dégâts", plutôt qu'en essayant de faire faire les deux jobs à la balle.
- Le cadrage fighting-game (kits de roster fixes, jauges) a transformé une idée de "power-up" initialement vague en un système beaucoup plus lisible, ancré dans des comparaisons (les références Street Fighter ont rendu le système abstrait concret rapidement).
- L'exercice Constraint Box a fait émerger une vraie direction UI/UX (lisibilité 100% visuelle, sans HUD texte) qui dépasse le simple exercice théorique et mérite d'être retenue comme piste de design réelle.
- Le Reference Blending a clarifié un axe esthétique clé : shmup épuré et lisible (R-Type, Air Zonk), surtout pas dense/illisible (anti-Ikaruga) ni lent (anti-Brawl Stars).
- Plusieurs mécaniques tentantes ont été délibérément mises de côté plutôt que rejetées d'emblée (bonus de charge de rally, bouclier/blocage actif, retournements de situation, doubles/2v2, points de contrôle MOBA) — un backlog utile pour des passes ultérieures, volontairement hors scope V1 pour protéger la simplicité de la boucle centrale.

### Prochaines étapes recommandées

1. **Prototyper la boucle centrale** — même une version brute (capture de balle + une arme + une jauge) résoudrait le plus vite la question ouverte "jauge partagée vs par arme", puisque le participant a signalé que ce n'était pas testable par la discussion seule.
2. **Explorer la direction artistique** avec des références visuelles concrètes (pixel art + effets spectaculaires) avant de s'engager davantage.
3. Une fois prêt, **passer au Game Brief** (`gds-create-game-brief`) pour formaliser la vision, ou directement au **GDD** (`gds-gdd`) si le concept semble déjà assez solide pour sauter le brief.

---

## Session terminée

**Date :** 2026-07-29
**Participant :** Camil
**Statut :** Complète — 4 étapes de la session de brainstorming réalisées (Initialisation, Contexte, Idéation, Clôture)

**Techniques utilisées :** Core Loop Design, Player Fantasy Mining, MDA Framework, Genre Mashup, Emotion Mapping, Constraint Box, Reference Blending

**Vos idées sont prêtes pour :**
- La création d'un Game Brief
- La validation de concept
- Le prototypage
- La discussion avec un copain/collaborateur

Belle session de brainstorming, Camil !
