# Journal d'apprentissage — IA adverse (Seek and Destroy and Return the Ball) — LÖVE port

Historique des ajustements de l'IA dans le port LÖVE (love_project/). Lu intégralement en début de session par shakkam-ia-seek avant toute modification — ne jamais réinventer une correction déjà tentée (et éventuellement rejetée) précédemment.

Le journal Godot reste à godot_project/nodes/AI_TUNING_LOG.md et couvre l'historique jusqu'au 2026-09-02 — le code IA du port LÖVE est dans screens/match_arena.lua (fonctions ai_helpers.*), avec les constantes regroupées dans AI_TUNING.

---

## 2026-09-27 — L'IA n'utilise jamais les tirs chargés

**Demande utilisateur :** "l'IA n'utilise jamais les tirs chargés" — constat fait en jouant, pas de repro précise.

**Cause identifiée :** `ai_helpers.should_fire()` renvoie `false` dès que `weapon.cooldown > 0`. Or chaque tir normal arme un cooldown (`1.0 / fire_rate`). Tous les cooldowns du roster sont très inférieurs à `NORMAL_FIRE_GRACE = 1.0s` (machine_gun : 0.11s, bazooka : 1.25s — mais le premier tir part immédiatement puis reset). Résultat : `fire_held_duration` se remet à zéro après CHAQUE cycle de tir, avant d'avoir jamais dépassé le seuil de grâce. Le tir chargé n'était donc structurellement pas accessible à l'IA. Le commentaire à la ligne ~1800-1808 ("an AI that stays aligned for a while incidentally charges") était incorrect.

**Changement — fichier `love_project/screens/match_arena.lua` :**

1. **Trois nouvelles constantes dans `AI_TUNING`** :
   - `CHARGE_FIRE_CHANCE = 0.35` — probabilité de tenter une charge quand le dé est lancé
   - `CHARGE_DECIDE_INTERVAL_MIN = 4.0` — secondes minimum entre deux lancers de dé
   - `CHARGE_DECIDE_INTERVAL_MAX = 8.0` — secondes maximum entre deux lancers de dé

2. **Trois nouveaux champs dans `new_player()`** :
   - `ai_charge_timer = 0.0` — quand > 0, force `firing = true` en contournant le gate cooldown de `should_fire()`
   - `ai_charge_releasing = false` — flag one-frame : la frame suivante pose `firing = false` pour déclencher `try_charged_fire()`
   - `ai_charge_decide_timer = 0.0` — cooldown inter-tentative

3. **Nouvelle fonction `ai_helpers.update_charge_attempt(player, dt)`** : machine à états qui arme `ai_charge_timer` à `NORMAL_FIRE_GRACE + charge_fire_duration + 0.05` quand les conditions sont réunies (arme charge-capable, aligné, dé favorable), puis pose `ai_charge_releasing` en fin de hold.

4. **Branche AI de `update_player_input()`** : appel de `update_charge_attempt` avant la lecture de `firing`, puis dispatch : releasing → `firing=false`, hold → `firing=true`, sinon → `ai_helpers.should_fire()` normal.

5. **Commentaire corrigé** à la ligne ~1800-1808 (l'ancien commentaire affirmait à tort que l'IA chargeait "incidentellement").

**Raisonnement :** l'IA avait besoin d'une machine à états dédiée car la mécanique humaine (tenir le bouton) est incompatible avec la structure de `should_fire()` (qui coupe `firing` à chaque cooldown). La solution réutilise EXACTEMENT le chemin `released_charge_attempt → try_charged_fire()` déjà en place — pas de duplication de logique. La fréquence (35%, dé toutes les 4-8s) est délibérément modeste pour qu'un humain n'anticipe pas le pattern ; à ajuster après test réel de Camil.

**Vérification :**
- Syntaxe : `lua -e "loadfile('screens/match_arena.lua')"` → OK
- Suite busted : 73 succès / 0 échecs (inchangée)
- Test comportemental jetable (`scratchpad/test_ai_charge.lua`, 9 assertions) : charge timer armé, valeur correcte, ai_charge_releasing posé à expiration, `fire_held_duration` dépasse bien `charge_fire_duration` en simulation → tous verts
- Boot LÖVE : démarre proprement, pas de crash

**À surveiller :** la fréquence effective (35% * ~1 roll toutes les 4-8s, seulement quand aligné) ne peut être validée que par Camil en vrai jeu. Si l'IA charge trop souvent → baisser `CHARGE_FIRE_CHANCE` ou allonger `CHARGE_DECIDE_INTERVAL_*`. Si jamais → augmenter `CHARGE_FIRE_CHANCE`. Les mooks héritent du même mécanisme (pas de scale dédié pour l'instant) — si un mook chargé semble trop fort pour un combat d'échauffement, ajouter un `MOOK_CHARGE_SCALE` ou simplement zéroiser `CHARGE_FIRE_CHANCE` pour les mooks.
