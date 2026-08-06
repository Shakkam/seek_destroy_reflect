---
title: 'Game Brief - Seek and Destroy and Return the Ball'
status: 'draft'
created: '2026-07-30'
updated: '2026-07-30'
---

# Game Brief : Seek and Destroy and Return the Ball

## Résumé exécutif

Seek and Destroy and Return the Ball est un hybride Pong × Shoot'em Up × Fighting Game en 1v1 : deux vaisseaux s'affrontent sur une arène divisée par une frontière centrale claire, où le mouvement libre en 2D dans sa moitié de terrain crée une tension permanente entre renvoyer une balle façon Pong et éviter les tirs d'un roster de personnages armés façon jeu de combat.

Le jeu part d'un concept prototypé en Flash il y a plus de 20 ans, ravivé aujourd'hui avec l'ambition de le concrétiser. Ce n'est ni un Pong déguisé, ni un fighting game déguisé : c'est la combinaison de deux tensions cognitives qui, séparément, n'existent dans aucun des deux genres — la lecture spatiale/anticipation de Pong, et la connaissance du matchup/réflexe d'un jeu de combat, actives **simultanément et sans interruption possible de l'une pour l'autre**.

C'est un projet personnel, sans deadline, porté par un développeur solo (avec assistance IA) qui n'a plus codé de jeu depuis longtemps mais qui a une vision de design déjà solide et éprouvée par une session de brainstorming complète.

## Vision

**Concept en une phrase** : Un duel de vaisseaux où renvoyer une balle façon Pong et vaincre son adversaire façon fighting game sont deux exigences simultanées, jamais l'une au repos pendant l'autre.

**Fantasme central (mots du créateur)** : *"Le joueur ressent ce besoin d'occuper au mieux son espace, tout en ayant une vision 360° de ce qui se passe autour, et un sentiment de puissance jouissive lorsqu'il bourrine son adversaire."*

Cette puissance jouissive n'est pas univoque : elle peut venir d'un déluge de tirs rapides (façon Hurricane Kick) ou d'un coup unique dévastateur (façon marteau-pilon) — les deux sont également satisfaisants, et le roster asymétrique doit permettre les deux fantasmes.

## Joueurs cibles & marché

**Profil recherché** — défini par tempérament plus que par familiarité de genre : des joueurs qui aiment la compétition, la satisfaction "défouloir" du bourrinage, ET la maîtrise technique, ensemble plutôt que l'un contre l'autre.

**Références d'audience** (pas de gameplay) : joueurs de Street Fighter (compétition, matchup, technique) et joueurs de Brawl Stars (accessibilité, rythme rapide, défouloir) — le jeu vise ce même public, avec un rythme plus intense que Brawl Stars, dont le rythme est jugé trop lent (repoussoir explicite, voir Références & Différenciation).

**Âge** : pas de plafond fixé ; borne basse implicite autour de **12+** — peu d'intérêt anticipé chez les plus jeunes.

**Hypothèse à deux segments (non tranchée)** : le créateur observe deux publics potentiels coexistants plutôt qu'un persona unique — (a) des joueurs plus âgés, nostalgiques des sessions canapé compétitives façon Street Fighter, et (b) des joueurs plus jeunes habitués aux jeux en ligne rapides et accessibles façon Brawl Stars. Cette incertitude assumée renforce plutôt qu'elle ne contredit la décision de proposer à terme le 1v1 **local ET en ligne**.

## Fondamentaux du jeu

**Genre** : Action compétitive 1v1 — hybride Pong / Shoot'em Up / Fighting Game.

**Boucle de gameplay centrale** :
1. La balle approche → le joueur doit se repositionner pour la renvoyer (viser + effets de type lift/spin)
2. Simultanément, l'adversaire armé peut tirer → le joueur doit esquiver sans jamais interrompre sa lecture de la balle
3. Balle ratée → l'adversaire récupère un avantage (power-up et/ou perte de PV pour le joueur fautif)
4. Renvoi réussi → la balle traverse le terrain, peut faire apparaître un bonus, puis défie l'adversaire
5. Les deux joueurs s'arment progressivement via des jauges remplies activement (pas de loot aléatoire), jusqu'à ce qu'un des deux tombe à 0 PV

**Piliers de gameplay** (2-4, chacun un engagement de design structurant) :

1. **Contrôle spatial** — gérer sa moitié de terrain, lire l'adversaire, se positionner simultanément pour la balle et pour les tirs. C'est la compétence dominante du jeu.
2. **Précision de renvoi** — viser et donner de l'effet à la balle (spin/lift) ; le pic d'expression de skill le plus pur, ponctuel plutôt que permanent.
3. **Montée en puissance maîtrisée** — un roster à kits fixes et asymétriques (façon coups spéciaux de fighting game), débloqués en match via des jauges à remplir activement plutôt que par ramassage aléatoire.

**Mécanique de risque signature** : même dans un jeu qui autorise le bourrinage, le joueur doit attendre de vraies ouvertures — tirer au mauvais moment expose à rater la balle, et inversement. Cette **double vigilance permanente** (matchup de combat + trajectoire de balle, jamais l'une en pause pour l'autre) est le cœur de l'expérience et n'existe ni dans Pong ni dans un fighting game pur.

**Expérience joueur visée par phase de match** (issue de la session de brainstorming, Emotion Mapping) : tension prudente en début de match → excitation contenue à mesure que les jauges se remplissent → double vigilance à son pic en milieu de match → sensation de puissance ou d'urgence selon qui mène → climax net où la victoire se sent méritée par la maîtrise spatiale et le timing, jamais par la chance.

## Références & Différenciation

| Jeu | Ce qu'on prend | Ce qu'on ne prend PAS |
|---|---|---|
| **Pong** | Le duel de renvoi, la frontière centrale, l'échange balle contre balle | La simplicité totale (pas d'armes, pas de PV) |
| **Windjammer** | Mouvement libre en 2D confiné à sa moitié de terrain, sensation arcade 1v1 rapide | — |
| **Street Fighter 6** | Roster à kits fixes/identité de personnage, système de jauges à paliers (super meter) | Les combos d'inputs complexes (pas l'objectif ici) |
| **Rocket League** | Trick-shots stylés sur les renvois, récompense du risque esthétique | La physique 3D/véhicules |
| **Smash Bros** | Rythme de match court et intense | Sa dynamique de comeback (différée, pas core V1) |
| **Soulcalibur** | Structure de déblocage/progression pour le mode campagne | — |
| **ActRaiser** | Alternance séquences d'action + méta-couche de progression pour la campagne solo | La gestion de ville/god-sim elle-même |
| **R-Type / Air Zonk** | Tir shmup épuré, lisible, coloré, peu encombrant visuellement | — |

**Repoussoirs explicites** :
- **Ikaruga** — évité pour son côté surchargé/illisible en densité de projectiles (bullet hell)
- **Brawl Stars** — évité pour son rythme perçu comme trop lent, malgré son public cible pertinent (voir Joueurs cibles)

**Différenciateur clé** : ni Pong (lecture spatiale/anticipation sans enjeu de combat direct) ni un fighting game pur (connaissance du matchup sans objet tiers à traquer) n'imposent au joueur de gérer les deux tensions **en continu et simultanément**. C'est cette double vigilance — jamais l'une en pause pour l'autre — qui constitue la proposition unique du jeu.

## Scope & MVP

**Plateformes cibles** : PC et console confirmées ; mobile envisagé mais non tranché.

**Équipe** : développeur solo (avec assistance IA), pas d'équipe constituée.

**Compétences techniques / moteur** : non tranché — le créateur n'a pas codé de jeu depuis longtemps et préfère ne pas fausser ce choix par une préférence artificielle. Un moteur 2D adapté à un solo dev (Godot, Unity, ou autre) reste à valider séparément de ce brief, avec conseil technique dédié.

**Timeline / budget** : aucune deadline, projet personnel sans pression de temps. Le netcode, l'équilibrage et le contenu de campagne peuvent prendre le temps nécessaire.

**Structure de scope à deux paliers** (distinction volontaire, à ne pas confondre) :

1. **Palier prototype — validation du core loop** : 1v1 local uniquement, roster potentiellement déséquilibré. C'est le véritable test de l'hypothèse "est-ce fun ?" avant tout autre investissement.
2. **Palier MVP complet / "marketable"** — défini explicitement par le créateur comme nécessitant **les trois éléments suivants ensemble** :
   - Un roster de base équilibré (8 personnages, clin d'œil à Street Fighter 2)
   - Le 1v1 en local ET en ligne
   - Une petite campagne solo (combats séquentiels par personnage avec déblocages d'armes/bonus façon Soulcalibur)

**Note de scope** : ce palier 2 combine trois chantiers significatifs pour un solo dev (roster équilibré, netcode, campagne) — voir Risques & Questions ouvertes pour la mitigation (séquencement strict).

## Contenu & Direction

**Univers/cadre** : vaisseaux spatiaux en duel — pas de narration approfondie exigée pour le mode versus ; la campagne solo pourra porter une légère narration par personnage.

**Mode Campagne (post-prototype)** : une campagne par personnage du roster, avec évolution/déblocages façon Soulcalibur, une carte du monde légère pour naviguer entre les combats, et un boss final par personnage. Direction encore floue mais fortement désirée — bon candidat pour une session d'idéation dédiée au moment du GDD.

**Direction artistique** : non tranchée définitivement, mais cadrée par une exigence forte — piste pixel art envisagée, avec des **effets visuels et particules spectaculaires** ("que ça pète de partout"), à l'opposé d'un style minimaliste ou austère.

**Direction UI/lisibilité** :
- **PV** : HUD explicite requis (jauge de vie) — lisibilité compétitive à l'œil, non négociable en 1v1.
- **Armes/jauges** : traitement diégétique — usure/décoloration du vaisseau, transparence progressive de l'icône d'arme selon la charge manquante, puis liseré doré quand pleinement disponible.

**Tir/esquive** : direction shmup épurée et lisible (R-Type, Air Zonk) — explicitement PAS un style bullet-hell dense (anti-Ikaruga).

**Contrôles (contrainte input minimal envisagée)** : appui long + direction pour sélectionner une arme parmi le kit, tir rapide/automatique une fois sélectionnée ; les tourelles se posent librement sur le terrain et agissent ensuite de façon autonome (pas de visée active).

## Risques & Questions ouvertes

**Risques identifiés honnêtement** :

- **Risque de scope** : le palier MVP complet (roster équilibré + netcode + campagne) est ambitieux pour un solo dev, même sans deadline — chacun des trois chantiers est en soi un projet consistant. Mitigation : séquencement strict — prototype 1v1 local d'abord, les deux autres chantiers ne démarrent qu'après validation du core loop.
- **Risque technique** : le netcode compétitif temps réel pour un jeu de réflexes/positionnement est le chantier le plus incertain techniquement, et le moteur n'est pas encore choisi. À traiter en amont via consultation technique dédiée, hors scope de ce brief.
- **Risque de granularité des jauges** : la structure exacte du système de jauges d'armes (partagée vs par arme, nombre de paliers) n'est pas tranchée par la discussion seule — signalée depuis le brainstorming comme un élément à décider au prototypage/playtest, pas en amont.
- **Risque d'audience** : l'hypothèse d'audience à deux segments (nostalgiques compétitifs vs jeunes joueurs online) n'est pas validée par des données de marché — c'est une intuition du créateur, pas une étude.

**Idées volontairement mises de côté (backlog post-MVP)**, à ne pas réintroduire sans revalidation : mécanique de charge de balle symétrique (rejetée), bouclier/blocage actif, retournements de situation façon Smash Bros, mode doubles/2v2, variantes d'arène façon MOBA (tourelles/points de contrôle).

**Questions ouvertes pour le GDD** :
- Structure définitive des jauges d'armes (partagée vs par arme)
- Choix du moteur de développement
- Forme exacte de la deuxième couche de la campagne (juste combats + déblocages, ou aussi narration/dialogue plus développée)
- Faisabilité et approche technique du online (rollback netcode ou autre)
