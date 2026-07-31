---
title: 'GDD - Seek and Destroy and Reflect the Ball'
game_type: 'fighting'
platforms: ['PC', 'Console']
created: '2026-07-31'
updated: '2026-07-31'
---

# Seek and Destroy and Reflect the Ball - Game Design Document

**Auteur :** Camil
**Type de jeu :** Fighting (avec conventions Shooter en extension — voir Fighting Specific Design)
**Plateforme(s) cible :** PC, Console (mobile envisagé, non tranché)

---

## Résumé exécutif

### Concept central

Seek and Destroy and Reflect the Ball est un hybride Pong × Shoot'em Up × Fighting Game en 1v1. Deux vaisseaux s'affrontent sur une arène divisée par une frontière centrale claire. Le mouvement libre en 2D, rapide et réactif ("un troisième bras", pas un boulet à piloter), crée une tension permanente entre renvoyer une balle façon Pong et éviter les tirs d'un roster de 8 personnages à kits d'armes fixes et asymétriques, façon fighting game.

Ni Pong (lecture spatiale sans enjeu de combat) ni un fighting game pur (matchup sans objet tiers à traquer) n'imposent au joueur de gérer les deux tensions en continu et simultanément. C'est cette **double vigilance permanente** — jamais l'une en pause pour l'autre — qui constitue la proposition unique du jeu.

### Public cible

Joueurs définis par tempérament plutôt que par familiarité de genre : amateurs de compétition, de satisfaction "défouloir", et de maîtrise technique, réunis. Références d'audience : joueurs de Street Fighter (compétition, matchup) et de Brawl Stars (accessibilité, rythme — public visé, pas rythme de jeu repris). Âge : 12+ implicite, pas de plafond. Hypothèse à deux segments non tranchée : joueurs nostalgiques du canapé compétitif (fighting games classiques) et joueurs plus jeunes habitués à l'online rapide — cette incertitude assumée justifie de viser local ET online dans le palier MVP complet.

### Points de différenciation uniques (USP)

1. **Double vigilance simultanée** — gérer un matchup de combat ET une trajectoire de balle en temps réel, sans jamais pouvoir mettre l'un en pause pour l'autre. N'existe dans aucun des deux genres source pris séparément.
2. **Montée en puissance maîtrisée, pas aléatoire** — roster à kits fixes façon coups spéciaux de fighting game, débloqués en match via des jauges remplies activement (pas de loot).
3. **Deux fantasmes de puissance également valides** — le "bourrinage" rapide (mitraillette) et le gros coup unique dévastateur (bazooka/heavy) sont tous deux jouissifs, à la Street Fighter 2 (Hurricane Kick vs. marteau-pilon), et le roster doit refléter cette dualité.
4. **Lisibilité 100% diégétique pour l'état de jeu** — hors PV (HUD explicite requis), l'état des armes/jauges se lit directement sur le vaisseau (usure, transparence, liseré doré), pas sur une interface superposée.

---

## Objectifs et contexte

### Objectifs du projet

- Valider l'hypothèse de fun du core loop via un **prototype 1v1 local** avant tout autre investissement (palier 1).
- Construire ensuite un **MVP marketable** (palier 2) : roster de 8 personnages équilibré, 1v1 local ET online, petite campagne solo.
- Aucune contrainte de deadline — projet personnel, le rythme est dicté par la qualité, pas le calendrier.

### Contexte et rationale

Le concept est né d'un prototype Flash personnel il y a plus de 20 ans (un "Pong" où l'objectif était de détruire le vaisseau adverse plutôt que marquer des points). Ravivé aujourd'hui via une session de brainstorming complète puis un Game Brief, le projet est porté par un développeur solo (avec assistance IA), sans expérience de code de jeu récente mais avec une vision de design mûre et un vrai sens de la satisfaction compétitive/défouloir (référence directe : sessions de fighting games en canapé).

---

## Gameplay central

### Piliers de jeu

1. **Contrôle spatial** (dominant) — gérer sa moitié de terrain, lire l'adversaire, se positionner simultanément pour la balle et pour les tirs. En cas d'arbitrage entre une arène plus grande/stratégique et une arène plus petite/intense, **l'intensité prime** — c'est le tie-breaker de conception pour ce pilier.
2. **Précision de renvoi** — viser et donner de l'effet à la balle (spin/lift) ; le pic d'expression de skill le plus pur, ponctuel plutôt que permanent.
3. **Montée en puissance maîtrisée** — roster à kits fixes et asymétriques, jauges remplies activement (pas de ramassage aléatoire).

### Boucle de gameplay centrale

1. La balle approche → le joueur se repositionne pour la renvoyer (viser + effet de spin/lift)
2. Simultanément, l'adversaire armé peut tirer → le joueur esquive uniquement via son mouvement (pas d'esquive dédiée en V1), sans jamais interrompre sa lecture de la balle
3. Renvoi réussi → remplit la jauge de l'arme sélectionnée (charge standard ≈ 5-10 tirs de mitraillette-équivalent) ; un renvoi stylé/trick shot ajoute un bonus de remplissage affiché à l'écran (ex. "+100%")
4. Balle ratée → remplit la jauge d'arme de l'**adversaire** en quantité significative (≈ une charge complète d'arme légère) — jamais de dégât direct depuis la balle elle-même
5. Le joueur sélectionne une arme via un bouton dédié (jamais en bloquant le mouvement), puis tire — chaque arme a ses propres dégâts fixes, cadence, et fenêtre de vulnérabilité pendant le tir
6. Répéter jusqu'à ce qu'un joueur atteigne 0 PV (fin du round)

### Conditions de victoire/défaite

- **PV par personnage :** 100, en jauge (pas de pourcentage abstrait), pour un tuning fin par arme.
- **Format de match :** Best of 3 rounds. Budget total ≤ 5 minutes → chaque round vise **90-120 secondes**, pour une montée de tension à la Smash Bros plutôt que l'intensité immédiate d'un Street Fighter.
- **Défaite** = PV à 0. Pas de condition de victoire liée aux balles ratées (uniquement un vecteur d'avantage, jamais une fin de partie directe).

---

## Mécaniques de jeu

### Mécaniques principales

**Mouvement**
- Vitesse : relativement rapide, réactif ("troisième bras", pas un boulet). `[NOTE FOR DESIGNER]` Inertie (accélération/freinage) explicitement écartée par défaut, mais à valider au prototype — décision non verrouillée.
- Confinement : chaque joueur reste dans sa moitié de terrain (frontière centrale claire, façon Pong/Windjammer) ; pas d'infiltration côté adverse.

**Balle**
- Ne fait jamais de dégâts directs — c'est un objet de ressource, pas une arme.
- Vitesse : augmente légèrement à chaque échange du rallye, pour intensifier la fin d'un échange.
- Renvoi : visée dirigeable + effets de spin/lift disponibles pour courber la trajectoire (skill expression).
- Ball/tirs : sur des couches séparées, aucune interaction (les tirs ne détruisent/dévient jamais la balle).

**Armes et jauges**
- Chaque personnage a un kit fixe de 3-4 armes, connu dès le début du match (pas de déblocage aléatoire en cours de partie).
- Sélection d'arme : bouton dédié, jamais lié à un appui long qui bloquerait le mouvement.
- Dégâts fixes par arme (exemples d'ancrage) : mitraillette ≈ 2 dégâts/tir à 4-6 tirs/seconde ; bazooka ≈ 10 dégâts/tir ; arme "super"/lourde ≈ 20-30 dégâts pour un tir unique à fort engagement.
- Fenêtre de vulnérabilité : les armes lourdes créent une exposition accrue (mobilité réduite) pendant l'animation de tir, façon recovery frames de fighting game — valeurs exactes à définir par arme.
- Structure des jauges (partagée vs. par arme, nombre de paliers) : **non tranchée**, à valider au prototypage/playtest ; tendance vers une jauge par arme, avec contrainte explicite de rester simple.
- Synergie limitée entre armes (pas de système de combo universel) : certains personnages peuvent avoir un outil de stun/setup (ex. un "flash paralysant" ~1 seconde) ouvrant une fenêtre pour un gros coup — à documenter par personnage.
- Certaines armes peuvent accorder un boost de mobilité temporaire (ex. type "tornade") comme outil défensif indirect, en complément de l'absence d'esquive dédiée.
- Tourelles : placement libre sur le terrain, agissent ensuite de façon autonome (pas de visée active par le joueur).

**Esquive** — `[NOTE FOR DESIGNER]` Explicitement écartée de la V1 (pas une mécanique dédiée type dash/roulade/i-frames). Raison : charge cognitive déjà élevée (balle + tirs adverses + gestion de ses propres armes + occupation de l'espace). Réévaluable après le prototype.

### Contrôles et input

- Déplacement : libre en 2D, dans sa moitié de terrain.
- Sélection d'arme : bouton dédié séparé du mouvement (le mouvement n'est jamais bloqué par la sélection).
- Tir : bouton dédié, déclenche l'arme actuellement sélectionnée.
- Visée/effet de balle : contrôle directionnel + option de spin/lift au moment du renvoi.

---

## Fighting Game Specific Design

### Roster de personnages

Roster de lancement : **8 personnages**, clin d'œil explicite à Street Fighter 2.

**Archétypes confirmés (au moins ces 4 profils représentés) :**
- **Lourd** — gros dégâts par tir, lent, forte fenêtre de vulnérabilité
- **Contrôleur** — style zone control / tourelles à placement libre
- **Mitrailleur** — arme à cadence élevée (4-6 tirs/s), dégâts unitaires faibles
- **Vif/Agile** — mobilité élevée, probablement dégâts par tir plus faibles en contrepartie

Composition exacte des 8 (répartition précise des archétypes, personnages restants) : à détailler dans une passe de design dédiée post-GDD.

**Philosophie d'équilibrage :** roster **entièrement viable** visé (pas de tier list acceptée comme design final), dans l'esprit SF6 plutôt qu'un système de tiers assumé. Méthodologie prévue : tests d'équilibrage assistés par IA (simulations agent-vs-agent) en complément du playtest humain — relève de la phase test/production (`gds-test-design`), pas d'une décision de game design en soi.

**Complexité :** volontairement variable sur le roster — référence explicite à Zangief (Street Fighter) comme modèle : difficile à prendre en main, plafond de compétence élevé, très gratifiant bien maîtrisé. Pas de complexité uniforme sur les 8 personnages.

**Référence directe pour la variété d'armes** (liste fournie par le créateur, issue d'Air Zonk — PC Engine), à utiliser comme matière première pour le design d'armes, non encore mappée aux archétypes/personnages :

| Arme (Air Zonk) | Description |
|---|---|
| Gants de boxe | Propulse des gants fonçant droit devant ou en rebondissant |
| Boomerangs | Reviennent au joueur ou quittent l'écran avant d'être relançables |
| Dents d'alligator | Mâchoire qui croque tout sur son passage |
| Cartes à jouer | Projections dispersées vers l'avant |
| Laser | Puissant mais portée limitée |
| Missiles guidés | Projectiles autoguidés ciblant l'adversaire |
| Mini-Zonk | Réduit drastiquement la taille/hitbox tout en gardant la pleine puissance de feu et le tir 4 directions |

Pistes de correspondance précoces (non verrouillées) : Laser → archétype précision ; Missiles guidés → archétype Contrôleur ; Mini-Zonk → bon candidat de mécanique risque/récompense spécifique à un personnage plutôt qu'arme universelle.

### Move Lists et données de frame

Pas de système d'inputs traditionnel (quart de cercle, chaînes de coups). L'équivalent fonctionnel :

- **Activation d'arme :** sélection via bouton dédié → tir via bouton dédié, sans délai de blocage du mouvement.
- **Cadence :** mitraillette 4-6 tirs/seconde ; autres armes à cadence propre, à définir par personnage.
- **Fenêtre de vulnérabilité par tir :** les armes lourdes exposent davantage le joueur pendant l'animation (mobilité réduite), façon recovery frames — valeurs précises non définies, `[NOTE FOR DESIGNER]` à établir par arme durant le prototypage.
- **Dégâts fixes ancrés :** mitraillette ≈2, bazooka ≈10, super/lourd ≈20-30 (voir Mécaniques de jeu).

### Système de combos

Pas de combos par chaîne d'inputs universelle. Système indirect, spécifique à certains personnages : un outil de stun/setup (ex. "flash paralysant" ~1s) peut ouvrir une fenêtre pour un gros coup. À documenter précisément par personnage lors du design détaillé du roster.

### Mécaniques défensives

- Pas de blocage.
- Pas d'esquive dédiée en V1 (voir Mécaniques de jeu) — évasion uniquement via le mouvement libre.
- Certaines armes peuvent accorder un boost de mobilité temporaire (ex. "tornade") comme outil défensif indirect propre à un personnage.

### Conception des arènes

- Terrain nu/neutre pour la V1 (pas d'obstacles), pour garder la boucle centrale lisible.
- Frontière centrale claire, chaque joueur confiné à sa moitié.
- **Tie-breaker de taille :** en cas de doute, privilégier une arène **plus petite/intense** plutôt que plus grande/stratégique (voir pilier Contrôle spatial).
- Extension future (hors V1) : arènes avec éléments de terrain (obstacles, zones de couverture, murs destructibles) et variantes façon MOBA (tourelles/points de contrôle) — non bloquant, différé.

### Modes solo

- **Cible aspirationnelle (pas un engagement V1 acté) :** campagne par personnage avec ~10 combats et embranchements pour la rejouabilité, façon Soulcalibur (déblocages progressifs d'armes/bonus), une carte du monde légère, et un boss final par personnage.
- **Engagement réel du palier MVP complet :** une "petite campagne" — combats séquentiels par personnage avec déblocages, sans préciser le nombre exact de combats à ce stade. Le chiffre de 10 avec embranchements reste la direction à viser en scalant au-delà du MVP.

### Fonctionnalités compétitives

- **Local :** 1v1 en canapé, disponible dès le palier prototype.
- **Online :** 1v1 rapide (quick-match) pour le lancement, **sans ranked/MMR** — le classement est une considération **post-launch**, conditionnée au succès du jeu, pas un engagement du MVP complet.
- **Netcode :** modèle non tranché (rollback vs. delay-based) — décision technique déléguée à `gds-game-architecture`. Convention de genre notée pour context : un 1v1 compétitif temps réel favorise fortement le rollback netcode.
- **Mode entraînement** — `[NOTE FOR DESIGNER]` non discuté en session ; c'est une convention standard des fighting games (tester ses armes/timings hors match). Non explicitement demandé, mais fortement recommandé pour le palier MVP complet vu la complexité de certains personnages (référence Zangief) — à trancher lors d'une prochaine passe plutôt que supposé inclus ou exclu silencieusement.

---

## Progression et équilibrage

### Progression du joueur

- **En match :** montée en puissance via jauges d'armes remplies activement (renvois de balle réussis, avec bonus pour les trick shots).
- **Méta-progression (campagne, palier post-MVP) :** déblocages d'armes/bonus façon Soulcalibur au fil des combats de la campagne par personnage.

### Courbe de difficulté

Non détaillée à ce stade pour le mode versus (symétrique par nature — les deux joueurs partent égaux). Pour la campagne solo, la courbe de difficulté par personnage reste à concevoir lors d'une passe dédiée (post-GDD, avec la conception précise du roster).

### Économie et ressources

- **Ressource centrale :** les jauges d'armes, alimentées uniquement par les renvois de balle réussis (jamais par un ramassage passif).
- **Munitions :** limitées par charge de jauge, se rechargent via de nouveaux renvois.
- Pas de monnaie/économie meta-jeu définie à ce stade (pas de boutique, pas de progression cosmétique évoquée).

---

## Level Design Framework

### Types de niveaux

- **Arène versus :** terrain nu/neutre unique pour le lancement V1, avec extension future vers des variantes (obstacles, points de contrôle façon MOBA).
- **Combats de campagne :** structure de combats séquentiels par personnage, potentiellement sur les mêmes arènes versus ou des variantes dédiées (non tranché).

### Progression des niveaux

- Mode versus : pas de progression de niveau, structure de match autonome (best of 3).
- Campagne : progression linéaire à embranchements par personnage, culminant en un boss final (cible aspirationnelle ~10 combats avec branches).

---

## Direction artistique et audio

### Style artistique

Piste **pixel art**, avec exigence forte de **spectacle visuel** — effets et particules riches ("que ça pète de partout"), à l'opposé d'un minimalisme austère. Direction shmup **épurée et lisible** pour les tirs (référence R-Type, Air Zonk), explicitement PAS un style bullet-hell dense (repoussoir : Ikaruga).

**Lisibilité d'état (diégétique) :**
- **PV :** HUD explicite requis (jauge de vie) — lisibilité compétitive non négociable en 1v1.
- **Armes/jauges :** décoloration/usure du vaisseau pour l'état général, transparence progressive de l'icône d'arme selon la charge manquante, puis liseré doré quand pleinement disponible.

### Audio et musique

Direction : **metal avec une touche électronique**. Le créateur est lui-même musicien — la composition musicale est une **compétence interne**, pas un poste à externaliser/budgétiser comme le serait typiquement le cas pour un développeur solo.

---

## Spécifications techniques

### Exigences de performance

- **Framerate cible : 30 FPS verrouillés/stables** (choix délibéré plutôt qu'un framerate variable plus élevé) — la stabilité du timing prime sur le chiffre brut, pertinent pour un jeu où les fenêtres de vulnérabilité et le timing de riposte sont du gameplay.
- Cible de référence : "tourne bien sur le PC du créateur" comme barre V1 — pas d'ambition de jeu 3D lourd.

### Détails spécifiques à la plateforme

- **Moteur de développement : non tranché.** Le créateur n'a pas de préférence actuelle (n'a pas codé de jeu depuis longtemps) — décision explicitement déférée à une consultation technique séparée, hors scope de ce GDD.
- Plateformes cibles : PC et console confirmées ; mobile envisagé mais non tranché.

### Exigences d'assets

Non détaillées à ce stade (dépend du choix de moteur et de la conception précise du roster de 8 personnages) — à affiner lors de `gds-game-architecture` et de la conception détaillée des personnages.

---

## Epics de développement

Voir `epics.md` pour le détail complet. Résumé :

| # | Epic | Palier | Description courte |
|---|---|---|---|
| 1 | Prototype du Core Loop | Prototype | Mouvement, physique de balle/renvoi, une arme basique, 1v1 local, roster minimal non-équilibré |
| 2 | Roster & Système d'armes | MVP complet | 8 personnages, jauges, archétypes, équilibrage (incl. tests IA) |
| 3 | Multijoueur en ligne | MVP complet | Quick-match 1v1 online, netcode |
| 4 | Mode Campagne | MVP complet (petite) → cible aspirationnelle (10 combats/perso) | Combats séquentiels par personnage, déblocages, carte du monde, boss |
| 5 | Direction artistique & Audio | Transversal | Pixel art + effets spectaculaires, composition metal/électro |

---

## Métriques de succès

### Métriques techniques

- Framerate stable à 30 FPS sur la configuration de référence du créateur, mesuré sur une session de combat complète.
- Netcode online : latence perçue acceptable en 1v1 (seuil précis à définir avec `gds-game-architecture`).

### Métriques de gameplay

- Le prototype (palier 1) valide l'hypothèse de fun si les sessions de test (créateur + entourage) génèrent des matchs répétés volontairement (signal qualitatif, pas de métrique chiffrée formelle à ce stade).
- Équilibrage du roster : aucun personnage significativement dominant/inutilisable en tests IA + playtest humain (seuils précis à définir en phase test).

---

## Hors scope

- **Esquive dédiée** (dash/roulade/i-frames) — écartée pour V1, réévaluable post-prototype.
- **Mécanique de charge de balle symétrique** — rejetée (profite également aux deux joueurs, pas de tension).
- **Bouclier/blocage actif du corps** — mise de côté, pas rejetée, réévaluable plus tard.
- **Retournements de situation façon Smash Bros** (comeback mechanics) — différé, pas dans le design central actuel.
- **Mode doubles/2v2** — évoqué comme piste future, non développé.
- **Variantes d'arène façon MOBA** (tourelles/points de contrôle en versus) — différé post-V1.
- **Ranked/MMR online** — post-launch, conditionné au succès du jeu.
- **Campagne à 10 combats/personnage avec embranchements** — cible aspirationnelle, pas un engagement du MVP complet (voir Modes solo).

---

## Hypothèses et dépendances

- **[ASSUMPTION]** Le moteur de développement (Godot/Unity/autre) n'étant pas tranché, toute estimation de faisabilité technique (netcode, performance) reste provisoire jusqu'à consultation technique dédiée.
- **[ASSUMPTION]** La structure exacte des jauges d'armes (partagée vs. par arme, nombre de paliers) est une hypothèse de conception à valider par le prototypage, pas une donnée figée.
- **[NOTE FOR DESIGNER]** L'inertie de mouvement (accélération/freinage) est explicitement écartée par défaut mais non verrouillée — à trancher après sensation en prototype.
- **[NOTE FOR DESIGNER]** Les fenêtres de vulnérabilité par arme (frame-data-équivalent) ne sont pas chiffrées précisément — nécessitent une passe de design dédiée par personnage.
- **Dépendance :** l'équilibrage du roster dépend d'une méthodologie de test (tests IA + playtest humain) qui reste à mettre en place — relève de `gds-test-design`/`gds-test-automate`, pas de ce GDD.
- **Dépendance :** le choix du netcode (rollback vs. delay-based) et du moteur sont des décisions de `gds-game-architecture`, pas de ce document.
