# Epics de développement — Seek and Destroy and Return the Ball

## Epic 1 — Prototype du Core Loop (Palier Prototype)

**Objectif :** valider l'hypothèse "est-ce fun ?" avant tout autre investissement.

**Contenu :**
- Mouvement 2D libre, confiné à sa moitié de terrain, sensation "troisième bras" (sans inertie par défaut, à valider en jeu)
- Physique de balle : visée dirigeable, effets de spin/lift, vitesse croissante par échange
- Une arme basique fonctionnelle (ex. mitraillette) avec jauge simple, sélection via bouton dédié
- Pénalité de balle ratée : remplissage de jauge adverse (pas de dégâts directs)
- PV = 100, best of 3 rounds, 90-120s/round
- 1v1 local uniquement, roster minimal (2 personnages suffisent pour tester la boucle), pas d'équilibrage poussé requis
- Arène nue/neutre unique

**Critère de sortie :** le core loop est jugé fun en interne (tests répétés volontaires) avant de passer à l'Epic 2.

---

## Epic 2 — Roster & Système d'armes (Palier MVP complet)

**Objectif :** un roster de 8 personnages viable et distinct.

**Contenu :**
- 8 personnages avec kits fixes de 3-4 armes chacun
- Couverture des archétypes : Lourd, Contrôleur, Mitrailleur, Vif (+ 4 autres à définir)
- Complexité variable par personnage (référence Zangief : certains difficiles à prendre en main, plafond de skill élevé)
- Système de jauges finalisé (structure partagée vs. par arme tranchée par prototypage)
- Fenêtres de vulnérabilité par arme définies (recovery-style)
- Synergies de combo limitées pour certains personnages (ex. stun de setup)
- Équilibrage : méthodologie de tests IA (agent-vs-agent) + playtest humain

**Dépendance :** Epic 1 validé.

---

## Epic 3 — Multijoueur en ligne (Palier MVP complet)

**Objectif :** 1v1 online fonctionnel.

**Contenu :**
- Quick-match 1v1 sans ranked/MMR (ranked = post-launch conditionnel)
- Choix et implémentation du netcode (rollback recommandé par convention de genre — décision à `gds-game-architecture`)
- Infrastructure de matchmaking basique

**Dépendance :** Epic 1 validé ; peut avancer en parallèle de l'Epic 2 selon les compétences/l'aide disponibles.

---

## Epic 4 — Mode Campagne (Palier MVP complet → cible aspirationnelle)

**Objectif :** offrir une progression solo par personnage.

**Contenu (engagement MVP) :**
- Combats séquentiels par personnage avec déblocages d'armes/bonus (façon Soulcalibur)
- Carte du monde légère pour naviguer entre les combats
- Boss final par personnage

**Contenu (cible aspirationnelle, au-delà du MVP) :**
- Scaling vers ~10 combats par personnage avec embranchements pour la rejouabilité

**Dépendance :** Epic 2 (roster) largement avancé, pour avoir des déblocages/armes à distribuer.

---

## Epic 5 — Direction artistique & Audio (Transversal)

**Objectif :** habiller le jeu avec l'identité visuelle et sonore visée.

**Contenu :**
- Pixel art avec effets visuels/particules spectaculaires
- Direction shmup épurée et lisible pour les tirs (référence R-Type/Air Zonk)
- Système de lisibilité diégétique (usure/décoloration, transparence + liseré doré pour les jauges d'armes)
- Composition musicale metal/électro (compétence interne du créateur)
- Sound design (à définir)

**Dépendance :** peut démarrer en parallèle dès l'Epic 1 pour les premiers tests de feel, s'intensifie avec l'Epic 2 (roster) pour l'identité visuelle par personnage.
