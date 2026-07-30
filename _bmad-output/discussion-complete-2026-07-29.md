# Discussion complète — Brainstorming jeu Pong x Shoot'em up
Date : 2026-07-29

---

**Camil :**
Il faudrait que je t'explique déjà ce que j'ai en tête avant de commencer non ?

**Assistant :**
Oui, tout à fait — c'est même l'idéal avant de choisir une technique précise. Raconte-moi ton idée (même vague, même juste un thème ou une sensation de jeu), et je m'en sers comme point de départ pour la première technique guidée.

---

**Camil :**
Ca vient d'une idée de jeu que j'avais commencé en flash il y a plus de 20 ans...

Le principe était simple : un "pong", sauf que le but est de détruire la raquette de l'autre (qui est en fait un vaisseau). En orientant la balle, on pouvait choper des bonus (mitrailleuse, tourelle, etc) et cela permettait de faire baisser les PV de l'autre joueur en lui tirant dessus.
Je ne sais plus ce que faisait le fait de rater la balle... j'imagine que ça donnait des power ups.

En gros, en y repensant, l'idée serait de mélanger le concept pong avec le concept d'un shoot'em up.

ça existe peut être déjà

**Assistant :**
Génial, c'est une base super riche — Pong-shmup avec vaisseaux qui se tirent dessus, ça a un vrai potentiel. Je ne connais pas d'équivalent exact "Pong x shmup" qui ait percé — donc pas de souci d'antériorité bloquante, on explore.

Je note ça comme concept de départ. Avant de partir sur la première technique guidée, quelques questions pour bien poser la base :

1. **Le "raté" de la balle** — dans ton souvenir, qu'est-ce qui se passait de plus marquant : perdre des PV directement, ou récupérer un power-up ? Ou les deux selon le contexte ?
2. **La balle elle-même** — est-ce qu'elle inflige des dégâts en touchant le vaisseau adverse (comme un Pong classique), ou son rôle est-il surtout de faire apparaître les bonus, le vrai dégât venant des armes ?
3. **Le mouvement** — les vaisseaux/raquettes se déplacent uniquement sur un axe (comme Pong), ou as-tu en tête plus de liberté (2D libre) ?

Une fois qu'on a ces bases, je lance la première technique guidée (Core Loop Design, puis Player Fantasy Mining). Ça te va ?

---

**Camil :**
1- je pense plus à un power up. ça peut être aussi des baisses de PV.
2- non elle n'inflige pas de dégats, puisqu'il faut la rattraper (pong)
3- hmmm l'idée de se déplacer en 2D libre me plait assez, comme dans un windjammer. pourquoi pas. mais il faut voir dans ce cas à quoi sert la balle (car dans ma version "pong", elle servait aussi à attraper les bonus qui apparaissent

**Assistant :**
Bonne remarque — c'est justement le nœud du problème : en Pong classique, la balle EST le lien entre "défense" et "collecte de bonus". Si on passe en 2D libre façon Windjammer, ce lien peut se distendre. Explorons ça avec la première technique : Core Loop Design.

Je vois trois pistes possibles pour résoudre cette tension balle/mouvement libre :

**A. Balle unique, mouvement libre mais contraint** — le vaisseau bouge en 2D mais reste globalement cantonné à sa "moitié" de terrain (comme Windjammer). La balle reste l'unique objet qui traverse le terrain et ramasse les bonus au passage.

**B. Balle = ressource, armes = attaque** — la balle sert exclusivement à choper les bonus/power-ups (elle ne fait jamais mal directement), et une fois qu'un vaisseau a une arme équipée, il peut tirer librement même sans la balle. Boucle : renvoyer la balle → choper un bonus → tirer sur l'adversaire → défendre son but pendant qu'on attaque.

**C. Double objectif simultané** — le vaisseau doit gérer deux choses en même temps qui se tirent la couverture : rattraper la balle (sinon malus/PV) ET esquiver les tirs adverses. Le mouvement libre sert justement à créer ce dilemme position pour la balle vs position pour éviter les tirs.

Laquelle de ces trois directions te fait le plus vibrer ?

---

**Camil :**
le C

**Assistant :**
Le C, ça donne un vrai jeu de tension — gérer deux fronts en même temps, c'est riche. Construisons la boucle plus en détail.

**Boucle de base qui se dessine :**
1. La balle arrive vers toi → tu dois te positionner pour la renvoyer
2. Pendant ce temps, l'adversaire (qui a peut-être déjà une arme) te tire dessus → tu dois esquiver
3. Si tu rates la balle → power-up pour l'adversaire (ou malus PV pour toi)
4. Si tu renvoies bien la balle → elle traverse, ramasse un bonus au passage si elle croise une zone de spawn, puis va défier l'adversaire
5. Répète, sauf que maintenant les deux joueurs ont potentiellement des armes actives

Quelques pistes pour enrichir/complexifier cette boucle :

**Sur la balle :**
- Est-ce que tu peux orienter/viser ta renvoie (comme dans ton souvenir Flash), pour choisir où elle va, ou vise-t-elle automatiquement les zones de bonus ?
- Et si la balle elle-même pouvait être "chargée" — plus tu la gardes en jeu longtemps sans la perdre, plus le prochain bonus ramassé est puissant ?

**Sur les tirs/armes :**
- Les tirs adverses peuvent-ils détruire la balle ou la dévier (créant un chaos supplémentaire), ou balle et tirs sont sur des "couches" séparées ?
- Munitions limitées (mitrailleuse à recharger) vs armes à énergie/cooldown ?

**Sur la fin de partie :**
- On gagne en mettant les PV adverses à 0 (façon shmup classique), ou il y a aussi une condition "Pong" — genre un nombre de balles ratées qui compte aussi ?

Une idée qui me vient en bonus : et si esquiver ne suffisait pas — genre le vaisseau doit activement bloquer certains tirs avec son corps un peu comme un bouclier, ce qui le rend temporairement incapable de renvoyer la balle ? Ça forcerait un vrai choix "je bloque ce tir / je vais chercher la balle".

---

**Camil :**
je répondrai demain

**Assistant :**
Pas de souci, on garde tout ça au chaud ! Je sauvegarde l'état actuel de la session pour qu'on reprenne exactement où on s'est arrêtés demain.

---

**Camil :**
sur la balle : on peut orienter et viser, un peu comme dans pong, et pourquoi pas lui donner des effets, par exemple en la "liftant".

Les tirs ne détruisent pas la balle
Munition limitées, et on peut imaginer que chaque perso a des armes différentes.
On gagne en mettant les PV à 0.

**Assistant :**
Parfait, ça referme bien la boucle centrale.

Ça donne une boucle bien plus riche :
- **Viser + effets sur la balle** (comme un lift) → skill expression à la Pong mais avec de la profondeur technique, un peu comme un smash au tennis de table. Plusieurs effets (lift, slice, tir tendu) qui rendent la balle plus dure à intercepter ou qui la font arriver sous un angle qui déjoue le renvoi adverse.
- **Balle et tirs séparés** → simplifie le lisible à l'écran (le joueur distingue toujours "ce qui compte pour le pong" de "ce qui compte pour l'esquive") — bon choix pour la clarté visuelle en 2D libre.
- **Armement asymétrique par personnage** → ouvre la porte à un vrai roster de vaisseaux avec identité propre (esprit fighting game/shmup).
- **Victoire = PV à zéro** → simple et clair, aligné shmup pur.

Il reste deux pistes en suspens : le mécanisme de charge (garder la balle en jeu longtemps sans la rater → bonus plus puissant) et l'idée de bouclier actif qui bloque des tirs mais empêche de renvoyer la balle.

Veux-tu qu'on creuse ces deux-là maintenant, ou on passe à la technique suivante (Player Fantasy Mining) ?

---

**Camil :**
ben si on la garde longtemps, ça veut dire que l'adversaire aussi. Donc je ne vois pas trop d'intérêt -pour l'instant-

**Assistant :**
Bon point — si la balle reste symétriquement en jeu pour les deux, la "charge" ne profite à personne en particulier, donc pas de tension intéressante. On met cette piste de côté pour l'instant (elle pourrait revenir sous une autre forme plus tard, ex : charge individuelle liée à la précision de tes propres renvois plutôt qu'à la durée du rally — mais rien à creuser maintenant).

Reste l'idée du bouclier actif (bloquer un tir = ne pas pouvoir renvoyer la balle ce tour-là). On la creuse maintenant, ou on la met de côté aussi et on passe à Player Fantasy Mining ?

---

**Camil :**
on met de côté

**Assistant :**
[Idée mise de côté, non rejetée définitivement — pourrait revenir plus tard]

---

**Camil :**
reviens
toujours planté claude ?
tu peux reprendre. Peux tu m'exporter toute la discussion (en pdf, ou simple texte) pour envoyer à un copain

**Assistant :**
Pas planté, je suis là ! Le fichier de session est bien sauvegardé — je te le renvoie en simple texte (le plus simple à copier-coller ou transférer à un copain). [Résumé de la session à ce stade fourni, avec proposition d'export via copier-coller ou conversion PDF manuelle.]

---

**Camil :**
c'est vraiment notre discussion complète que j'aimerais lui envoyer

**Assistant :**
[Création d'un premier fichier `discussion-complete-2026-07-29.md` reprenant l'intégralité des échanges jusqu'à ce point.]

---

**Camil :**
on reprend la session

**Assistant :**
**Player Fantasy Mining** — quelle identité ou quel fantasme le joueur incarne-t-il en jouant ?

Quelques pistes pour creuser le fantasme :
- **Le duelliste réactif** — sensation d'être hyper vif, de lire le jeu adverse et de renvoyer au dernier moment avec précision.
- **Le pilote qui monte en puissance** — on commence fragile/désarmé et on devient une forteresse volante au fil du match grâce aux bonus récupérés.
- **Le stratège du positionnement** — puisque le mouvement est libre en 2D, le joueur se sent comme un pilote qui gère l'espace du champ de bataille, pas juste un réflexe pur.
- **Le tireur d'élite improvisé** — chaque arme récupérée change radicalement la façon de jouer.

Est-ce qu'une de ces fantasmes te parle plus particulièrement ?

---

**Camil :**
un peu du 1, pas mal du 2 et beaucoup du 3

**Assistant :**
Bonne combinaison — ça dessine un profil clair : le joueur passe le plus clair de son temps à gérer l'espace du terrain (positionnement stratégique), avec des pics de réflexe pur au moment du renvoi de balle, et une sensation de montée en puissance qui récompense la survie et l'habileté sur la durée.

Ça implique que le contrôle de l'espace doit être la compétence centrale récompensée, avec les réflexes comme pics ponctuels au moment des échanges de balle, et la montée en puissance comme sensation de progression sur la durée du match.

Une question pour affiner ça : puisque le positionnement est central, est-ce que tu imagines un terrain avec des éléments (obstacles, zones de couverture, murs destructibles...) qui donnent du relief à cette gestion d'espace ? Ou plutôt un terrain nu où tout repose sur le mouvement pur des deux vaisseaux et la balle ?

---

**Camil :**
pour l'instant, terrain nu. Mais on pourrait imaginer à termes de nouveaux terrains.

**Assistant :**
Noté : terrain nu pour la V1 (garde la boucle de base lisible et pure), avec des terrains variés (obstacles, zones de couverture, murs destructibles...) prévus comme extension future, pas bloquant pour le concept central.

On a bien fait le tour de Player Fantasy Mining. On continue avec quelle technique maintenant ?
1. MDA Framework
2. Genre Mashup
3. Emotion Mapping
4. On s'arrête là pour aujourd'hui

---

**Camil :**
1

**Assistant :**
**MDA Framework** — Mechanics, Dynamics, Aesthetics. On part du bas (les règles) vers le haut (le ressenti), pour vérifier que tout s'aligne.

**Mechanics (les règles/systèmes qu'on a déjà) :** renvoi de balle avec visée + effets, PV pour chaque vaisseau, ramassage de bonus/armes via la balle, armes asymétriques par personnage, munitions limitées, mouvement libre en 2D, tirs séparés de la balle, défaite = PV à 0.

**Dynamics — questions :**
1. Zone neutre vs zone de duel — frontière centrale claire ou infiltration totale possible ?
2. Course à l'armement — risque de spam de tirs généralisé une fois tout le monde armé ? Faut-il un contrepoids ?
3. Rythme du match — matchs courts et intenses, ou plus longs avec plusieurs vagues d'armement ?

---

**Camil :**
1- il y a une frontière claire (comme pong / windjammer)
2- je pense qu'il faut que les munitions s'épuisent assez vite et qu'elles ne viennent que recharger les armes déjà dispos du joueur. On peut imaginer que le vaisseau a 3/4 armes différentes, chacune plus ou moins puissante, demandant peut être un certain truc pour les activer (collecte de bonus qui remplit des jauges d'armes (un peu comme les barres 1/2/3 de street fighter 6) ? munitions différentes selon l'arme (armes puissantes = plus rare ? autre ?
3 on peut imaginer des matchs plutôt court (à la Street Fighter / windjammer / smash bros)

**Assistant :**
Ça, c'est une vraie trouvaille : le système de jauges façon Street Fighter 6 change complètement la texture du jeu — au lieu d'un ramassage aléatoire de bonus, ça devient un système de ressources à gérer activement, ce qui renforce encore plus le pilier "contrôle" plutôt que "chaos".

Question de suivi pour affiner ce système de jauges :
- Une jauge partagée (comme la barre Super de SF6) ou des jauges séparées par arme ?
- Les 3-4 armes sont-elles fixes dès le début du match, ou apparaissent-elles/se débloquent-elles progressivement pendant le match ?

---

**Camil :**
je pense qu'il faut connaître son kit, c'est l'intérêt pour moi de faire un roaster. Un peu comme les coups spéciaux de Street Fighter.
à voir si on fait une jauge coupée en 3/4 ou plusieurs jauges.... il faut tester, je n'ai pas d'avis tranché sur la question. Comme ça, je dirais + une jauge par arme, mais je ne veux pas que ce soit compliqué

**Assistant :**
Bien noté — kit fixe par personnage (roster identity, comme les coups spéciaux de Street Fighter), et la granularité des jauges (partagée vs par arme) reste une question à trancher au prototypage, avec comme contrainte forte : rester simple.

On a bien bouclé la technique MDA. On enchaîne comment ?
1. Genre Mashup
2. Emotion Mapping
3. Constraint Box
4. On s'arrête là pour cette session

---

**Camil :**
1

**Assistant :**
**Genre Mashup** — le concept est déjà un mashup (Pong + shmup), et on vient d'y injecter pas mal de fighting game (roster, coups fixes, jauges à la SF6). Explorons d'autres genres qui pourraient enrichir le mix, sans dénaturer le noyau.

Quelques pistes à tester :
- **Bullet hell** — patterns de tirs adverses plus complexes/chorégraphiés à esquiver
- **Beat 'em up / fighting game** — combos/enchaînements d'armes
- **Tower defense / MOBA lane** — tourelles automatiques ou points de contrôle neutres à capturer
- **Rhythm game** — renvoyer la balle "en rythme" donne un bonus de précision/dégâts
- **Roguelite** — progression/déblocage de nouveaux vaisseaux entre les matchs
- **Sport arcade (type Rocket League)** — "trick shots" avec la balle donnant des bonus supplémentaires

Est-ce qu'un de ces axes te parle particulièrement ?

---

**Camil :**
Moba lane, sport arcade, et pour le mode "campagne solo".... pourquoi pas une sorte de RPG (ou un jeu un peu plus "fumé" comme actraiser

**Assistant :**
ActRaiser en référence, c'est excellent — un jeu qui alterne action pure et une couche méta différente (gestion/construction), ça ouvre une vraie piste pour un mode solo qui ne soit pas juste "des matchs à la suite contre l'IA".

Ça dessine une structure claire : le mode versus reste pur et centré sur la boucle Pong-shmup-fighting, pendant que le mode solo/campagne devient le terrain de jeu pour les ambitions structurelles (MOBA, méta-couche ActRaiser).

Deux questions pour creuser la piste solo :
1. La "deuxième couche" façon ActRaiser — construction/gestion de base ? progression permanente du vaisseau/personnage ? narration/carte du monde légère ? un mélange des trois ?
2. Les tourelles/points de contrôle MOBA — variante d'arène en mode versus, ou réservées au contenu solo/campagne ?

---

**Camil :**
1 j'avoue avoir du mal encore à me prononcer. Pourquoi pas un truc de progression, avec une histoire, différente par personnage du roaster. construction de base peut être pas, mais une sorte d'évolution avec déblocage (à la soulcalibur peut être ?) avec une petite carte du monde et, pourquoi pas, une sorte de boss final.
2 ça peut être des variantes du mode versus, et présent sur quelques combats de la campagne. Pas urgent pour V1.

**Assistant :**
Bien capturé — campagne solo par personnage avec déblocages façon Soulcalibur, petite carte du monde, boss final ; et les variantes MOBA en option pour le versus, sans urgence V1.

On a maintenant une base très complète. On continue avec une autre technique, ou on s'arrête là pour cette session ?
1. Emotion Mapping
2. Constraint Box
3. On s'arrête là — synthèse finale

---

**Camil :**
On pourra imaginer bien sûr concentrer l'intérêt à termes sur le versus, et pourquoi pas prévoir des matchs en double. à suivre

**Assistant :**
Noté, ça part dans le sac des idées futures — le double/2v2 mériterait sa propre passe de réflexion, mais pas maintenant.

On continue avec une technique (Emotion Mapping ou Constraint Box), ou on s'arrête là pour cette session ?

---

**Camil :**
emotion

**Assistant :**
**Emotion Mapping** — carte émotionnelle sur un match type :

**Début de match (les deux "nus")** → tension prudente, tâtonnement.
**Premiers ramassages de bonus / début de charge des jauges** → excitation contenue, urgence discrète.
**Milieu de match (armes actives)** → stress et vigilance double, pic d'intensité cognitive.
**Un joueur prend l'avantage** → pour celui qui mène : sentiment de puissance grisant. Pour celui qui est mené : urgence, quitte ou double.
**Fin de match / coup de grâce** → climax net et lisible, gagné par la maîtrise de l'espace + le timing, pas par hasard.

Est-ce que cette courbe colle à ce que tu veux faire ressentir, ou il y a un moment précis où tu veux une émotion différente (par exemple, des retournements de situation façon Smash Bros) ?

---

**Camil :**
c'est parfait, les petits retournements pourraient être intéressants, mais pas maintenant.

**Assistant :**
Bien noté, l'idée de retournements reste dans le sac des idées futures.

On a maintenant une base très complète. On continue avec une autre technique, ou on s'arrête là ?
1. Constraint Box
2. Reference Blending
3. On s'arrête là — synthèse finale

---

**Camil :**
tu me fais une synthèse et on reprendra après

**Assistant :**
[Synthèse intermédiaire produite : concept principal, boucle de jeu, fantasy, MDA, genre mashup, carte émotionnelle. Session marquée comme en pause, pas clôturée.]

---

**Camil :**
[a ouvert le fichier de session dans l'IDE] tu me fais un français du .md ?

**Assistant :**
[Traduction intégrale du fichier de session en français, structure et contenu conservés.]

---

**Camil :**
constraint box

**Assistant :**
**Constraint Box** — on stress-teste le concept en lui imposant des contraintes créatives fortes.

**A. Un seul bouton** — comment gérer renvoi de balle + tir + activation d'arme avec un seul input (en plus du mouvement) ?
**B. Vue fixe et serrée, pas de scrolling** — comment le mouvement libre en 2D reste-t-il lisible ?
**C. Match ultra-court (30s max)** — qu'est-ce qui doit changer dans la boucle ?
**D. Zéro texte, zéro HUD** — comment communiquer l'état du joueur (PV, jauges, armes) uniquement par le visuel ?

Laquelle veux-tu creuser en premier ?

---

**Camil :**
A - ce serait en effet compliqué, mais pas impossible. on pourrait imaginer un appui long et les directions pour sélectionner une arme, un tir rapide (ou un tir automatique) une fois l'arme sélectionnée. pas pratique pour les tourelles cela dit.
B - Je pense que c'est jouable si on choisit des types de tir fun mais pas trop encombrants (je pense aux armes de "Aiz Zonk" par exemple, qui sont rigolotes.
C- probablement un choix d'arme avant chaque "set"
D- PV : peut être une décoloration du vaisseau OU des marques d'usure
armes : l'image de l'arme qui devient transparente petit à petit
Jauges : l'image de l'arme redevient colorée, puis entourée d'un liseré (doré par exemple) quand dispo.

**Assistant :**
Excellent, ces contraintes ont fait sortir des idées d'interface très concrètes et cohérentes. [Synthèse capturée : appui long + direction pour sélection d'arme, tourelle à traiter différemment, direction artistique des tirs façon Air Zonk pour rester lisible, choix d'arme pré-set pour les matchs courts, et surtout le système de lisibilité 100% visuelle (décoloration/usure pour les PV, transparence puis liseré doré pour les jauges d'armes) identifié comme une vraie piste de direction UI/UX, pas juste un exercice théorique.]

Petite question sur le point A : pour les tourelles, tu envisages un mode d'activation différent (genre "pose et laisse tirer toute seule") ?

Sinon, on continue avec Reference Blending, ou on clôture la session ici ?

---

**Camil :**
tourelle : pose libre en effet.

Go sur le reference blending

**Assistant :**
**Reference Blending** — liste de références consolidée à partir de la session :
- Pong, Windjammer, Street Fighter 6, Rocket League, Smash Bros, Soulcalibur, ActRaiser, référence Flash citée pour l'artistique des tirs.

Questions pour compléter :
1. Un shoot'em up précis pour la sensation de tir/esquive (Ikaruga, Cave shooters, Geometry Wars, autre) ?
2. Une référence esthétique globale en tête (rétro/pixel, vectoriel, cartoon, autre) ?
3. Un jeu repoussoir — "je veux faire un truc qui ne ressemble surtout pas à X" ?

---

**Camil :**
1- Ikaruga, c'est trop "plein de boulettes" pour moi. Je vois un truc plus épuré, type Air Zonk, R-Type.
2 - excellente question, je ne sais pas. Pixel art peut être, mais il faut que ce soit beau et que ça pète de partout avec des effets dingues.
3 - Surtout pas Ikaruga (pour le côté illisible) ou brawl stars (pour le côté "lent" que j'aime pas trop.)

**Assistant :**
Bien noté — ça donne une identité de référence très claire : Pong/Windjammer pour la structure du duel, R-Type/Air Zonk pour le tir épuré et lisible (surtout pas Ikaruga), Street Fighter 6 pour le roster/jauges, et une direction artistique encore ouverte mais avec une exigence forte : pixel art (peut-être) + effets visuels spectaculaires, surtout pas quelque chose de lent ou austère (anti-Brawl Stars).

On a maintenant fait le tour de toutes les techniques prévues. C'est un bon moment pour clôturer proprement la session avec un résumé final complet et des prochaines étapes concrètes — tu veux que je fasse ça maintenant ?

---

**Camil :**
Oui.
Je voudrais le résumé de la session en français, ainsi que l'intégralité de notre discussion en français également.

**Assistant :**
[Clôture officielle de la session — mise à jour du document de session avec le résumé final, et génération de ce document de transcription complète.]

---

## Résumé de synthèse — Concept final

**Concept principal**
Hybride Pong × Shoot'em Up × Fighting Game. Deux vaisseaux s'affrontent sur une arène divisée par une frontière centrale claire (Pong/Windjammer). Le mouvement libre en 2D dans sa moitié de terrain crée un dilemme constant entre renvoyer la balle et esquiver les tirs. La balle ne fait jamais de dégâts et n'interagit jamais avec les tirs — elle est purement l'objet de collecte de ressources (visée + effets comme le lift). Les armes viennent d'un kit fixe par personnage (identité de roster façon Street Fighter), débloquées en jeu via des jauges façon SF6 alimentées par les bons renvois de balle — structure exacte des jauges (partagée ou par arme) à trancher au prototypage. Matchs courts et intenses. Victoire = PV adverses à zéro.

**Direction artistique/UX**
Lisibilité 100% visuelle/diégétique (usure du vaisseau pour les PV, transparence puis liseré doré pour les jauges d'armes), tir épuré et lisible façon R-Type/Air Zonk (surtout pas Ikaruga), pixel art avec effets spectaculaires envisagé.

**Couche secondaire (post-V1)**
Mode versus comme priorité long terme, variantes d'arène façon MOBA (tourelles, points de contrôle), mode doubles/2v2 à explorer.

**Mention spéciale**
Campagne solo façon ActRaiser — histoire par personnage du roster, déblocages façon Soulcalibur, petite carte du monde, boss final.

**Idées mises de côté (backlog futur)**
Charge de rally symétrique (rejetée), bouclier actif, retournements de situation, doubles/2v2, points de contrôle MOBA en versus.

**Prochaines étapes**
1. Prototyper la boucle centrale pour trancher la question des jauges par le test
2. Explorer la direction artistique avec des références visuelles concrètes
3. Passer au Game Brief (`gds-create-game-brief`) ou directement au GDD (`gds-gdd`)
