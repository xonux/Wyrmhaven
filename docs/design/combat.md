# Système de combat — Wyrmhaven

Doc de référence vivant du combat. Il a deux rôles :

1. **Décrire le combat tel qu'il est dans Studio** (sections 1 à 10),
   rédigé à partir de l'export `studio-export/` du 2026-09-26. Ce n'est pas
   un doc de design idéal.
2. **Lister les changements à apporter et tracer ceux qui sont faits**
   (sections 11 et 12). C'est cette partie qui évolue au fil des
   discussions.

> Source de vérité = les scripts Studio. Si ce doc et un script se
> contredisent, le script a raison : corrige le doc et signale l'écart dans
> le journal (section 12).

---

## 0. Mode d'emploi pour une session Claude locale (MCP `Roblox_Studio`)

Tu as ce doc parce qu'on te demande d'appliquer des changements au combat.
Procédure :

1. **Récupère la dernière version du repo** (`git pull`), puis lis ce doc
   en entier.
2. Dans la section 11, prends les changements au statut **`À appliquer`**,
   dans l'ordre de leur numéro. Ignore ceux au statut `Proposé` (pas encore
   validés par l'utilisateur) et `Appliqué`.
3. Pour chaque changement :
   - relis dans Studio les scripts listés dans "Scripts touchés" avec
     `script_read`, **juste avant d'éditer** : l'état réel peut avoir bougé
     depuis la rédaction ;
   - si le changement est déjà en place, passe-le à `Appliqué` sans rien
     coder et dis-le dans ton résumé ;
   - applique-le avec `multi_edit` / `execute_luau`, en respectant les
     conventions de `CLAUDE.md` : serveur autoritaire, tout le texte visible
     en anglais, ids internes jamais renommés ;
   - fais les tests de la section 10 (validation du catalogue, simulation)
     **et** les "Critères de test" du changement ;
   - **teste en Play** : lance un combat de campagne et joue au moins un
     tour à la main.
4. Une fois testé :
   - passe le changement à `Appliqué (AAAA-MM-JJ)` ;
   - mets à jour les sections 1 à 10 pour qu'elles décrivent le nouvel état ;
   - ajoute une ligne au journal (section 12) ;
   - ré-exporte dans `studio-export/` les scripts modifiés (convention dans
     `studio-export/README.md`) ;
   - commit et push.
5. Si un changement est ambigu, ou entre en conflit avec le code réel,
   **ne l'improvise pas** : laisse-le à `À appliquer`, ajoute une note
   `**Bloqué :** …` sous le changement, et pose la question dans ton résumé.

---

## 1. Vue d'ensemble

- **Tour par tour, 3 dragons contre 3.** L'ordre de jeu suit la vitesse. Les
  équipes peuvent être plus petites : le minimum est 1 dragon de chaque côté.
- **Contenu actuel : la campagne PvE seulement.** C'est une carte de 10
  étapes sur 2 régions, dont 2 boss. Il n'y a pas de PvP.
- **Le serveur fait tout.** Le moteur tourne dans un thread serveur. À chaque
  tour du joueur, il se met en pause pour attendre la réponse du client.
  Le client ne fait qu'afficher et renvoyer « compétence + cible ».
- **Chaque dragon a 3 compétences fixes**, définies par son espèce. Chaque
  compétence porte 1 élément, qui décide si elle fait plus ou moins de
  dégâts selon la cible.
- **Quatre classes** (Attacker, Tank, Support, Control) : elles orientent les
  stats et le style des compétences.
- Seuls les **Adultes** (niveau ≥ 4) qui ne sont pas en reproduction peuvent
  combattre. Le combat ne rapporte **aucune XP aux dragons**. Il rapporte
  des Pièces, de la Nourriture et de l'XP joueur. C'est la Nourriture qui
  fait monter les dragons de niveau.

### Carte des fichiers

| Rôle | Script Studio | Export |
|---|---|---|
| Moteur (résolution, règles) | `ServerScriptService.Wyrmhaven.Services.CombatEngine` | `studio-export/ServerScriptService/Wyrmhaven/Services/CombatEngine.luau` |
| IA adverse | `…Services.CombatAI` | `…/Services/CombatAI.luau` |
| Campagne, session de combat, récompenses | `…Services.PveService` | `…/Services/PveService.luau` |
| RemoteEvents + branchements | `ServerScriptService.Wyrmhaven.Server` | `…/Server.server.luau` |
| Sauvegarde (`Pve.cleared`) | `…Services.SaveService` | `…/Services/SaveService.luau` |
| Constantes (stats de base, éléments, bonus d'équipe) | `ReplicatedStorage.Wyrmhaven.Config.GameConstants` | `…/Config/GameConstants.luau` |
| Classes | `…Config.DragonClasses` | `…/Config/DragonClasses.luau` |
| Stats, classe, éléments d'une espèce | `…Config.DragonRules` | `…/Config/DragonRules.luau` |
| Espèces (classe + 3 compétences) | `…Config.DragonDefs` | `…/Config/DragonDefs.luau` |
| Niveaux (Adulte = 4, max 10) | `…Config.DragonLevels` | `…/Config/DragonLevels.luau` |
| Table des éléments | `…Config.ElementChart` | `…/Config/ElementChart.luau` |
| Catalogue des 108 compétences | `…Config.SkillDefs` | `…/Config/SkillDefs.luau` |
| Statuts (brûlures, buffs, boucliers…) | `…Config.StatusDefs` | `…/Config/StatusDefs.luau` |
| Lecture/description/validation des compétences | `…Config.SkillRules` | `…/Config/SkillRules.luau` |
| Étapes de la campagne + récompenses | `…Config.PveMap` | `…/Config/PveMap.luau` |
| Client : branchements réseau | `StarterPlayer…Wyrmhaven.Controllers.PveController` | `…/Controllers/PveController.luau` |
| Client : écran de combat | `…Wyrmhaven.UI.BattleScreen` | `…/UI/BattleScreen.luau` |
| Client : carte + choix d'équipe | `…Wyrmhaven.UI.PveMapScreen` | `…/UI/PveMapScreen.luau` |

---

## 2. Déroulé d'un combat (`CombatEngine`)

**Au départ** (`Battle.new`) :

1. Chaque dragon est créé avec ses stats de niveau (section 3). Pour un
   boss, les stats sont déjà multipliées (section 8).
2. **Bonus d'équipe** (`applyTeamBonus`) : chaque équipe reçoit
   `+8 %` d'Attack et de Health **par classe distincte au-delà de la
   première**. 1 classe donne +0 %, 2 classes +8 %, 3 classes +16 %.
   L'idée est de rendre rentable un Tank ou un Support face à trois
   Attackers.
3. Tout le monde commence avec sa Health max.

**Un round** : chaque dragon vivant joue une fois, **le plus rapide
d'abord**. La Speed effective est relue à chaque round, donc les Slow et
Haste changent l'ordre. En cas d'égalité, l'équipe A (le joueur) passe
d'abord, puis le slot le plus bas.

**Un tour de dragon** (`takeTurn`) :

1. `startTurn` : il subit ses **dégâts sur la durée** (Dot), puis ses
   **cooldowns baissent de 1**. S'il meurt de la brûlure, son tour s'arrête là.
2. S'il est **étourdi** (`stunTurns > 0`), il perd son tour :
   `stunTurns - 1`, puis `endTurn`.
3. Sinon il **choisit une compétence et une cible**. Ce choix vient de
   `options.choose` : le joueur, l'IA adverse, ou l'IA « Normal » si le
   joueur ne répond pas. À défaut, c'est `defaultChoice`. S'il n'a rien de
   prêt, il **passe**.
4. **Résolution** :
   - la compétence part en cooldown pour `Cooldown + 1` tours. Le +1
     compense la baisse au début de son prochain tour, donc le temps
     d'attente réel est bien `Cooldown` tours ;
   - pour **chaque cible** : dégâts = `Attack effective × Power × facteur
     d'élément`, puis application de chaque statut de `Effects` ;
   - puis les `SelfEffects`, une seule fois sur le lanceur, quel que soit
     le nombre de cibles touchées.
5. `endTurn` : tous les statuts **portés par ce dragon** perdent 1 tour. Ceux
   qui arrivent à 0 disparaissent, et un bonus de Health est rendu à ce
   moment-là. Le bouclier perd 1 tour aussi, et tombe à 0 quand son compteur
   expire.

**Ciblage** (`targetsFor`) :

- `Self` = le lanceur. `AllEnemies` / `AllAllies` = tous les vivants du camp.
- `Ally` : la cible choisie si elle est valide. Sinon, l'allié qui a **le
  plus petit % de Health**. `WeakestAlly` choisit toujours ce dernier.
- `Enemy` : **si un ennemi a Taunt, il prend le coup, quelle que soit la
  cible demandée.** Sinon, la cible choisie si elle est valide. Sinon,
  l'ennemi qui a le plus petit % de Health.

**Dégâts** (`damage`) : le bouclier absorbe d'abord, puis la Health baisse.
Un dragon à 0 meurt : ses statuts, son bouclier et son étourdissement
sont effacés.

**Fin du combat** :

- dès qu'une équipe est éliminée ;
- sinon au bout de **30 rounds** (`MaxRounds`). L'équipe qui garde le plus
  grand **% de Health totale** gagne. `Draw` si l'écart fait moins de 1 %.
  En campagne, un `Draw` compte comme une défaite.

**Déterminisme** : tout l'aléatoire passe par un `Random` initialisé avec
`seed`. À noter : le moteur lui-même n'utilise aucun aléatoire (pas de
coup critique, pas d'esquive, pas de précision). Seules les IA en
utilisent : Easy choisit au hasard, Normal ajoute du bruit.

**Résultat** (`Resolve`) : `{ winner = "A"|"B"|"Draw", rounds, timedOut,
fighters = {...état final}, log = {...} }`. Le log est une liste
d'événements `t = "teamBonus" | "round" | "skill" | "damage" | "heal" |
"shield" | "status" | "burn" | "cleanse" | "stunned" | "pass" | "death" |
"end"`. `CombatEngine.FormatLog(result)` le transforme en texte lisible.

---

## 3. Stats

`DragonRules.Stats(speciesId, level)` = `DragonBaseStats × poids de classe ×
1.25^(paliers de rareté) × (1 + 0.1 × (niveau − 1))`, arrondi.

- Base (`GameConstants.DragonBaseStats`) : **Attack 60, Health 130, Speed 100**.
- Rareté : Common ×1, Rare ×1.25, Epic ×1.5625, Legendary ×1.95. Pour
  l'instant, seules des espèces Common et Rare existent.
- Niveau : +10 % de la base par niveau (le niveau 10 donne ×1.9).
- Poids de classe (`DragonClasses.Weights`) :

| Classe | Attack | Health | Speed | Rôle |
|---|---|---|---|---|
| Attacker | 1.1 | 0.9 | 1 | Frappe fort, encaisse mal |
| Tank | 1 | 1.5 | 0.85 | Encaisse, tient la ligne |
| Support | 0.95 | 1 | 1.2 | Soigne et buffe, tôt |
| Control | 0.95 | 0.95 | 1.2 | Débuffe et perturbe avant l'ennemi |

Valeurs obtenues (Attack / Health / Speed, **avant** bonus d'équipe) :

| | Attacker | Tank | Support | Control |
|---|---|---|---|---|
| Common niv. 4 | 86 / 152 / 130 | 78 / 254 / 110 | 74 / 169 / 156 | 74 / 161 / 156 |
| Common niv. 10 | 125 / 222 / 190 | 114 / 370 / 162 | 108 / 247 / 228 | 108 / 235 / 228 |
| Rare niv. 4 | 107 / 190 / 162 | 98 / 317 / 138 | 93 / 211 / 195 | 93 / 201 / 195 |
| Rare niv. 10 | 157 / 278 / 238 | 142 / 463 / 202 | 135 / 309 / 285 | 135 / 293 / 285 |

Cible de rythme (commentaire de `GameConstants`) : un rapport Attack/Health
de 60/130 donne environ **7 rounds, soit environ 27 tours** par combat.

**Modificateurs en combat** : les buffs et debuffs d'une même stat
**s'additionnent**. Le multiplicateur final ne descend jamais sous **0.2**
(`MIN_STAT_MULTIPLIER`). Attack et Speed sont des multiplicateurs de la
base. Health fonctionne autrement : le statut ajoute ou retire de la Health
**max**, et cette différence est rendue quand le statut expire.

---

## 4. Éléments (`ElementChart`)

Cycle de 8 éléments, où chacun bat le suivant :

**Fire → Nature → Metal → Light → Dark → Earth → Electric → Water → Fire**

- Une compétence contre l'élément qu'elle bat : **×1.5**
  (`ElementAdvantageMultiplier`), affiché « Strong ».
- Une compétence contre **son propre élément** : **×0.5**
  (`ElementSameMultiplier`), affiché « Resisted ».
- Tout le reste fait ×1. **Le sens inverse n'est pas pénalisé** : Fire sur
  Water fait ×1, pas ×0.5. C'est un choix de l'utilisateur, pour ne pas
  punir deux fois un mauvais matchup.
- Contre un **hybride**, on multiplie les facteurs de ses deux éléments. Le
  résultat reste entre ×0.5 et ×1.5, car un élément n'en bat qu'un seul.
- Le facteur s'applique **aux dégâts directs seulement**, jamais aux
  statuts. Une brûlure fait donc les mêmes dégâts quel que soit l'élément.

---

## 5. Compétences (`SkillDefs` + `SkillRules`)

**108 compétences**, 3 par espèce, **aucune partagée** entre espèces. Les 36
espèces sont les 8 Commons et les 28 hybrides Rare. Le catalogue complet
est en annexe B.

Champs d'une compétence :

| Champ | Sens |
|---|---|
| `DisplayName` | nom affiché (anglais) |
| `Element` | un des 8 éléments |
| `Class` | classe pour laquelle elle a été pensée. Info seulement : une espèce peut avoir une compétence d'une autre classe |
| `Target` | `Enemy`, `AllEnemies`, `Self`, `Ally`, `AllAllies`, `WeakestAlly` |
| `Power` | dégâts = part de l'Attack du lanceur (`nil` = aucun dégât) |
| `Cooldown` | tours d'attente avant réutilisation (0 = à chaque tour) |
| `Effects` | statuts posés sur chaque cible touchée |
| `SelfEffects` | statuts posés sur le lanceur (uniquement des statuts `Good`) |

**Règles du catalogue** (vérifiées par `SkillRules.Validate()`, voir
section 10) :

- chaque espèce a exactement 3 compétences, sans doublon ;
- les compétences d'une espèce sont **de ses propres éléments**. Un Common a
  3 compétences de son élément. Un hybride en a 2 d'un de ses éléments et
  1 de l'autre ;
- **deux espèces ne partagent jamais une compétence**. Un seul partage donne
  un avertissement, deux partages ou plus une erreur ;
- **deux compétences ne peuvent pas faire le même travail**. Si elles ont
  la même cible, les mêmes statuts (cible + soi) et le même cooldown, c'est
  une erreur, même si leur `Power` ou leur élément diffère. Règle de
  l'utilisateur du 2026-09-26 : on n'aurait aucune raison de choisir la
  plus faible des deux.

Le texte de description d'une compétence est **généré** à partir de ses
chiffres (`SkillRules.Describe`). Il ne faut jamais l'écrire à la main.

---

## 6. Statuts (`StatusDefs`)

Chaque statut a **des chiffres fixes**. Une compétence dit seulement quel
statut elle pose, jamais sa force. Les parts de Health se calculent sur le
dragon **qui reçoit** le statut. Seul Drain fait exception : il se calcule
sur la Health max du lanceur.

| Id | Type | Stat | Valeur | Durée | Bon ? |
|---|---|---|---|---|---|
| Singe | Dot | — | 4 % de la Health max par tour | 2 | non |
| Burn | Dot | — | 10 % / tour | 2 | non |
| Poison | Dot | — | 5 % / tour | 4 | non |
| Bleed | Dot | — | 18 % / tour | 1 | non |
| Weaken | Debuff | Attack | −15 % | 2 | non |
| Cripple | Debuff | Attack | −30 % | 2 | non |
| Slow | Debuff | Speed | −20 % | 2 | non |
| Root | Debuff | Speed | −40 % | 2 | non |
| Wither | Debuff | Health | −15 % de la Health max | 3 | non |
| Stun | Stun | — | saute son prochain tour | 1 | non |
| Focus | Buff | Attack | +15 % | 2 | oui |
| Rage | Buff | Attack | +35 % | 2 | oui |
| Quicken | Buff | Speed | +20 % | 2 | oui |
| Haste | Buff | Speed | +40 % | 2 | oui |
| Taunt | Taunt | — | attire toutes les attaques mono-cible | 2 | oui |
| Guard | Shield | — | absorbe 15 % de la Health max | 2 | oui |
| Barrier | Shield | — | 35 % | 2 | oui |
| Bulwark | Shield | — | 60 % | 2 | oui |
| Mend | Heal | — | +20 % de la Health max | instantané | oui |
| Renewal | Heal | — | +40 % | instantané | oui |
| Drain | Drain | — | le lanceur récupère 12 % de **sa** Health max | instantané | oui |
| Cleanse | Cleanse | — | retire tous les Debuff, Dot et Stun | instantané | oui |

Règles d'empilement :

- **Même statut, même lanceur** : il est **rafraîchi**. On garde la plus
  grande durée et la plus grande valeur, sans cumul.
- **Même statut, lanceurs différents** : ils se cumulent. Pour Attack et
  Speed, les valeurs s'additionnent, avec toujours le plancher de 0.2.
- **Dot** : les dégâts sont calculés une fois, quand le statut est posé, à
  partir de la Health max de la victime.
- **Bouclier** : **un seul à la fois**. Un dragon qui en porte encore un ne
  peut pas en recevoir un nouveau (l'effet est ignoré). Cette règle a été
  ajoutée après un blocage : deux dragons Earth se reprotégeaient à chaque
  tour et le combat allait jusqu'à la limite de rounds.
- **Stun** : `stunTurns = max(actuel, durée)`. Un Stun posé sur un dragon
  qui a déjà joué ce round lui fait sauter son tour du round suivant.
- **Buff Health** : seul un statut *nouveau* augmente la Health max. Le
  relancer ne fait que rafraîchir sa durée, donc on ne peut pas gonfler la
  Health à l'infini.

---

## 7. IA (`CombatAI`)

`CombatAI.Policy(difficulty, seed)` renvoie une fonction `choose(fighter,
battle) → skillId, targetKey`. Au lieu d'une liste de règles, elle
**chiffre chaque compétence prête en « équivalent dégâts »** et joue la
plus chère :

- dégâts : `Attack de base × Power × facteur d'élément`, plafonnés à la
  Health restante. Pour une compétence mono-cible, l'IA vise l'ennemi qui
  donne la meilleure valeur ;
- soin : points de Health réellement rendus (0 si la cible est pleine) ;
- bouclier : `Health max × valeur × 0.8`, et 0 si la cible a déjà un
  bouclier ;
- Dot : `min(Health max × valeur × durée, Health restante) × 0.9` ;
- buff/debuff d'Attack : `Attack cumulée × valeur × durée × 0.45`. Un buff
  déjà actif vaut 0 ;
- buff/debuff de Speed : `Attack × valeur × durée × 0.12` ;
- Stun : `Attack de la victime × durée`. L'IA vise l'ennemi non étourdi
  qui a la plus forte Attack ;
- Taunt : `Attack ennemie cumulée × durée × 0.55`, seulement si le lanceur
  a des alliés plus fragiles et assez de Health pour encaisser ;
- Cleanse : `nombre d'effets retirables × Health max × 0.25`.

| Difficulté | Comportement |
|---|---|
| Easy | compétence prête au hasard (cible laissée au moteur) |
| Normal | chiffrage, mais ignore les boucliers, pas de bonus pour un kill, ±15 % de bruit |
| Hard | chiffrage exact : voit les boucliers, bonus de kill (`Attack de la victime × 1.5`), pas de bruit |

La politique `Normal` sert aussi à **jouer à la place du joueur** s'il ne
répond pas dans les 45 s.

---

## 8. Campagne PvE (`PveMap` + `PveService`)

**Progression linéaire** : l'étape N s'ouvre quand l'étape N−1 est gagnée.
Une étape déjà gagnée peut être **rejouée** pour une part de sa récompense :
35 % des Pièces et de la Nourriture, 20 % de l'XP (arrondi vers le bas,
avec un minimum de 1).

**Boss** : c'est une espèce normale, avec **Attack ×1.2 et Health ×1.3**,
dessinée ×1.5. Ces multiplicateurs sont modestes exprès : +40 %/+50 %
faisait tomber le taux de victoire de 47 % à 13 %.

| # | Nom | Région | IA | Niv. conseillé | Ennemis (espèce niv.) | Pièces / Nourriture / XP (1re fois) |
|---|---|---|---|---|---|---|
| 1 | Scorched Sands | Ember Coast | Easy | 4 | Fire 2, Earth 2, Nature 2 | 120 / 8 / 40 |
| 2 | Ashen Trail | Ember Coast | Easy | 4 | Fire 3, Water 3, Nature 3 | 180 / 12 / 60 |
| 3 | Cinder Ridge | Ember Coast | Normal | 5 | Fire 5, Metal 5, Nature 5 | 260 / 16 / 85 |
| 4 | Emberfall Pass | Ember Coast | Normal | 6 | Electric 5, Earth 5, Light 5 | 360 / 20 / 110 |
| 5 | **Magma Tyrant** (boss) | Ember Coast | Normal | 6 | **Fire 6 (boss)**, Earth 5, Water 5 | 700 / 40 / 220 |
| 6 | Windswept Cliffs | Storm Reach | Normal | 6 | Electric 7, Metal 7, Water 7 | 520 / 26 / 150 |
| 7 | Thunder Hollow | Storm Reach | Normal | 7 | WaterElectric 7, Metal 7, Nature 7 | 680 / 32 / 190 |
| 8 | Iron Bluffs | Storm Reach | Hard | 8 | EarthMetal 8, ElectricMetal 8, Light 8 | 880 / 38 / 240 |
| 9 | Nightfall Crag | Storm Reach | Hard | 9 | ElectricDark 9, NatureDark 9, EarthLight 9 | 1100 / 44 / 300 |
| 10 | **Blade Tyrant** (boss) | Storm Reach | Hard | 10 | **MetalDark 10 (boss)**, FireDark 8, EarthDark 8 | 2200 / 90 / 600 |

Total pour une première victoire sur toute la carte : **7 000 Pièces,
326 Nourriture, 1 995 XP**. 326 Nourriture permet d'élever environ un
dragon du niveau 1 au niveau 10 (il en faut 270). Le raisonnement complet
est dans `REWARD NOTES` en bas de `PveMap.luau`.

**Équipe du joueur** :

- **Roster** : les dragons de niveau ≥ 4 (`DragonAdultLevel`) qui ne sont
  pas en reproduction. Ils sont triés par niveau décroissant, puis par
  `Attack × Health`.
- Le joueur choisit jusqu'à 3 dragons sur la carte (`RequestPveTeam`).
  Sans choix, ce sont les **3 premiers du roster**.
- L'équipe **n'est pas sauvegardée**. Les ids de dragon ne vivent que le
  temps de la session, donc il faut la refaire à chaque connexion.
- **Sauvegarde** : seul `Pve = { cleared = <plus haute étape gagnée> }` est
  gardé, dans `SaveService`.

**Refus possibles de `PveService.Fight`**, traduits côté client dans
`PveController.FIGHT_ERRORS` : `NotReady`, `Busy` (un combat est déjà en
cours), `NoSuchStage`, `Locked`, `TooFast` (moins de 3 s depuis le dernier
combat), `NoTeam` (aucun Adulte disponible). `Failed` signale une erreur
Lua pendant le combat.

---

## 9. Flux réseau et écran de combat

### RemoteEvents

Ils sont créés au démarrage par `Server` via `getOrCreateRemoteEvent` et ne
sont pas enregistrés dans la place.

| Remote | Sens | Contenu |
|---|---|---|
| `RequestPveInfo` | C→S | ouvre la carte (réponse : `PveStatusUpdated` avec `openRequest = true`) |
| `RequestPveTeam` | C→S | `{dragonId, ...}` : l'équipe choisie |
| `RequestPveFight` | C→S | `levelId` |
| `RequestPveAction` | C→S | `token, skillId, targetKey` : la réponse du joueur pour son tour |
| `PveStatusUpdated` | S→C | état de la carte : étapes, roster, équipe, `fightError` éventuel |
| `PveBattleStarted` | S→C | `levelId, name, boss, difficulty, fighters` (identité), `fighterState` (état), `events` |
| `PveBattleUpdate` | S→C | un envoi par tour : `token, round, actorKey, yourTurn, actions, upcoming, events, fighters, secondsLeft` |
| `PveBattleResult` | S→C | `won, firstClear, rewards, rounds, timedOut, fighters, fighterState` final, `events` restants |

### Déroulé réseau d'un combat

1. `PveService.Fight` vérifie la demande, puis lance `CombatEngine.Resolve`
   dans un `task.spawn`. Le joueur est l'équipe **A**, l'ennemi l'équipe **B**.
2. Au premier appel de `choose`, le serveur envoie `PveBattleStarted`.
3. **Tour ennemi** : le serveur envoie un `PveBattleUpdate` sans actions,
   attend 0.35 s, puis appelle l'IA de l'étape.
4. **Tour du joueur** : le serveur incrémente `token`, envoie les
   `actions` (sortie de `Battle:availableActions`, avec pour chaque cible
   possible un aperçu des dégâts et soins et le libellé Strong/Resisted),
   puis attend la réponse (vérifiée toutes les 0.1 s, **45 s au maximum**).
   `SubmitAction` rejette un token périmé, une compétence que le dragon n'a
   pas ou une compétence en cooldown. Si le temps expire, ou si le joueur
   part, l'IA `Normal` joue ce tour.
5. À la fin : récompenses versées si victoire, puis `PveBattleResult`,
   mise à jour du HUD et `RefreshStatus` (l'étape suivante est ouverte). Si
   le joueur a quitté la partie, il ne reçoit rien.

### Écran (`BattleScreen`)

- L'arène est construite à `(0, 0, -32000)`, loin des îles, avec la caméra
  du monde empruntée via `CameraController.Hold`. Les couleurs viennent de
  l'habitat Nature et les décorations sont celles de l'île.
- Chaque équipe se place **en triangle** : le joueur à gauche, l'ennemi en
  miroir à droite. La mise en page reprend celle du PvP de Monster Legends.
- **Tour en deux étapes** : 1) **SELECT SKILL** (3 boutons : élément +
  nom) ; 2) **SELECT TARGET** (la description s'affiche, les dragons hors
  d'atteinte deviennent transparents, le joueur touche une cible). Une
  flèche permet de revenir à l'étape 1. Même une compétence de zone doit
  être confirmée de cette façon.
- Barres de Health avec **aperçu en jaune** de ce que la compétence
  enlèverait ou rendrait (sans compter les brûlures). Bouclier affiché en
  bleu, statuts affichés en texte : nom + tours restants. Les icônes sont
  prévues, il reste le champ `Icon` à remplir dans `StatusDefs`.
- Bandeau en haut avec les 4 prochains à jouer, cerclés de vert pour les
  alliés et de rouge pour les ennemis. Anneau au sol sous le dragon actif,
  petit élan vers l'avant quand il agit, chiffres flottants.
- Carte de résultat avec bouton **Continue**, qui renvoie à la carte.
- Pas de bouton fuir, de mode auto ni d'accélération.

---

## 10. Tester

À lancer avec `execute_luau` en mode Edit (ou dans la console serveur en
Play).

**Validation du catalogue**. Elle n'est appelée par aucun script : il faut
la lancer à la main **après chaque changement** de `SkillDefs`,
`StatusDefs` ou `DragonDefs` :

```lua
local SkillRules = require(game.ReplicatedStorage.Wyrmhaven.Config.SkillRules)
local r = SkillRules.Validate()
print(r.ok, r.covered .. "/" .. r.total)
for _, p in r.problems do warn(p) end
for _, w in r.warnings do print("warn:", w) end
```

Attendu : `true 36/36`, aucun problème.

**Simulation de combat** (équilibrage, sans UI) :

```lua
local S = game.ServerScriptService.Wyrmhaven.Services
local CE, AI = require(S.CombatEngine), require(S.CombatAI)
local wins, N = 0, 200
for i = 1, N do
	local a = { CE.Fighter("Fire", 6), CE.Fighter("Earth", 6), CE.Fighter("Water", 6) }
	local b = { CE.Fighter("Metal", 6), CE.Fighter("Nature", 6), CE.Fighter("Light", 6) }
	local r = CE.Resolve(a, b, { seed = i, choose = AI.Policy("Normal", i) })
	if r.winner == "A" then wins += 1 end
end
print("A gagne", wins, "/", N)
-- Un combat lisible : print(CE.FormatLog(CE.Resolve(a, b, { seed = 1 })))
```

Attention : `choose` s'applique **aux deux équipes**. Pour opposer deux IA
différentes, passe une fonction qui regarde `fighter.team`.

**Test en Play** (obligatoire avant de passer un changement à
`Appliqué`) : `/give egg <espèce>` et `/give food <n>` pour obtenir des
Adultes, bouton **Adventure**, puis choisir l'équipe, lancer une étape et
jouer au moins un tour à la main jusqu'à l'écran de résultat.

---

## 11. Changements demandés

Statuts : `Proposé` (en discussion, **ne pas appliquer**), `À appliquer`
(validé par l'utilisateur), `Appliqué (date)`, `Abandonné`.

Modèle d'une entrée :

```markdown
### C-00X — Titre court
**Statut :** Proposé
**Pourquoi :** …
**Ce qui change :** règles précises, chiffres, textes UI en anglais.
**Scripts touchés :** CombatEngine, …
**Critères de test :** ce qui doit être vrai en simulation et en Play.
```

*Aucun changement pour l'instant : cette section se remplira au fil des
discussions.*

### Observations relevées à la lecture du code (pas des demandes)

Ces points ne sont pas à corriger d'office. Ils servent de base de
discussion, et on en fera éventuellement des changements numérotés :

- **O-1** — L'IA chiffre les dégâts sur `baseAttack`, donc **sans ses
  buffs et debuffs** d'Attack. Elle sous-estime ses coups sous Rage et les
  surestime sous Cripple.
- **O-2** — L'aperçu de la barre (`previewOn`) ne montre ni le soin d'un
  Drain sur le lanceur, ni les boucliers posés par la compétence.
- **O-3** — Le client gère un événement `miss` (« resisted ») que le moteur
  n'émet jamais : c'est du code mort, ou le reste d'une mécanique de
  précision abandonnée.
- **O-4** — Les statuts s'affichent encore en texte (« +15% Attack »),
  alors que `StatusDefs` prévoit des icônes (`Icon` pas encore rempli).
- **O-5** — L'équipe choisie n'est pas sauvegardée : il faut la refaire à
  chaque connexion.
- **O-6** — Aucun aléatoire dans le moteur (ni critique, ni esquive). Un
  même choix donne toujours le même résultat. C'est peut-être voulu.
- **O-7** — Un `Draw` au bout de 30 rounds compte comme une défaite, sans
  message dédié à l'écran de résultat (`timedOut` est bien envoyé).
- **O-8** — `SkillRules.Validate()` n'est lancé automatiquement nulle part.
- **O-9** — Les dragons ne gagnent rien en combattant eux-mêmes : pas d'XP
  de dragon. Seul le joueur gagne de l'XP.

---

## 12. Journal des changements

| Date | Qui | Changement |
|---|---|---|
| 2026-09-26 | Claude (session cloud) | Création du doc à partir de l'export complet `studio-export/` du 2026-09-26. Décrit l'état existant, aucun changement de code. |

---

## Annexe A — Espèces, classes et compétences

Généré à partir de `DragonDefs` et `SkillDefs` (export du 2026-09-26).

| Espèce (id) | Nom | Rareté | Classe | Compétences |
|---|---|---|---|---|
| `Fire` | Fire Dragon | Common | Attacker | `EmberBite`, `FlameBurst`, `SearingMark` |
| `Water` | Water Dragon | Common | Support | `WaterJet`, `HealingTide`, `SoothingCurrent` |
| `Nature` | Nature Dragon | Common | Control | `VineLash`, `Entangle`, `SporeCloud` |
| `Electric` | Electric Dragon | Common | Attacker | `ArcStrike`, `ChainLightning`, `OverchargeCoil` |
| `Earth` | Earth Dragon | Common | Tank | `StoneSlam`, `BedrockGuard`, `Tremor` |
| `Light` | Light Dragon | Common | Support | `RadiantBeam`, `DawnBlessing`, `GuidingLight` |
| `Dark` | Dark Dragon | Common | Control | `ShadowRake`, `CurseOfNight`, `SoulDrain` |
| `Metal` | Metal Dragon | Common | Tank | `IronCharge`, `PlatedHide`, `MagnetPull` |
| `FireWater` | Smoke Dragon | Rare | Control | `CinderSpit`, `SmokeScreen`, `ChokingHaze` |
| `FireNature` | Ash Dragon | Rare | Attacker | `AshClaw`, `EmberStorm`, `BrambleSnare` |
| `FireEarth` | Lava Dragon | Rare | Attacker | `MoltenFang`, `LavaFlow`, `EruptionCore` |
| `FireElectric` | Plasma Dragon | Rare | Attacker | `PlasmaLance`, `IonBlast`, `StaticField` |
| `FireMetal` | Forge Dragon | Rare | Tank | `AnvilStrike`, `MoltenPlating`, `ForgeHeat` |
| `FireDark` | Inferno Dragon | Rare | Attacker | `HellfireBite`, `InfernalRoar`, `SoulEmber` |
| `FireLight` | Solar Dragon | Rare | Support | `SunRay`, `SolarFlare`, `Sunbath` |
| `WaterNature` | Swamp Dragon | Rare | Control | `MireSpit`, `QuagmireGrip`, `BlightCloud` |
| `WaterEarth` | Ice Dragon | Rare | Control | `FrostFang`, `Permafrost`, `StoneTomb` |
| `WaterElectric` | Storm Dragon | Rare | Attacker | `SquallStrike`, `ThunderSurge`, `Downpour` |
| `WaterMetal` | Rust Dragon | Rare | Tank | `CorrodedClaw`, `RustArmor`, `OxideCloud` |
| `WaterDark` | Abyss Dragon | Rare | Control | `AbyssalPull`, `CrushingDepths`, `DrowningGrasp` |
| `WaterLight` | Rainbow Dragon | Rare | Support | `PrismJet`, `PrismaticVeil`, `TideMend` |
| `NatureEarth` | Forest Dragon | Rare | Tank | `RootSmash`, `Ironbark`, `Landslide` |
| `NatureElectric` | Pollen Dragon | Rare | Support | `PollenDart`, `BloomingAura`, `StaticBloom` |
| `NatureMetal` | Thorn Dragon | Rare | Tank | `BarbedLash`, `SpikedShell`, `ThornVolley` |
| `NatureDark` | Poison Dragon | Rare | Control | `VenomBite`, `ToxicBloom`, `Neurotoxin` |
| `NatureLight` | Blossom Dragon | Rare | Support | `PetalSlash`, `SpringBloom`, `SunlitGift` |
| `EarthElectric` | Magnet Dragon | Rare | Control | `MagneticJolt`, `PolarityShift`, `GravityGrip` |
| `EarthMetal` | Bronze Dragon | Rare | Tank | `BronzeBash`, `AegisStance`, `GuardianCall` |
| `EarthDark` | Fossil Dragon | Rare | Tank | `FossilCrush`, `AncientCarapace`, `BoneShards` |
| `EarthLight` | Crystal Dragon | Rare | Support | `CrystalShard`, `RefractiveWard`, `CrystalSong` |
| `ElectricMetal` | Circuit Dragon | Rare | Attacker | `CircuitStrike`, `OverloadSurge`, `SystemPurge` |
| `ElectricDark` | Thunder Dragon | Rare | Attacker | `ThunderFang`, `BlackBolt`, `StormCurse` |
| `ElectricLight` | Aurora Dragon | Rare | Support | `AuroraBeam`, `PolarLights`, `DazzlingFlash` |
| `MetalDark` | Blade Dragon | Rare | Attacker | `BladeDance`, `ShadowCut`, `EdgeSharpening` |
| `MetalLight` | Silver Dragon | Rare | Tank | `SilverStrike`, `MirrorPlating`, `PurifyingGleam` |
| `DarkLight` | Eclipse Dragon | Rare | Control | `EclipseSlash`, `TotalDarkness`, `EquinoxGrace` |

## Annexe B — Catalogue des 108 compétences

Power = part de l'Attack du lanceur ; CD = cooldown en tours. Les effets sont détaillés en section 6.

| Espèce | Id | Nom | Élément | Classe | Cible | Power | CD | Effets (cible) | Effets (soi) |
|---|---|---|---|---|---|---|---|---|---|
| Fire | `EmberBite` | Ember Bite | Fire | Attacker | 1 ennemi | 1 | 0 | Singe | — |
| Fire | `FlameBurst` | Flame Burst | Fire | Attacker | tous ennemis | 0.7 | 3 | Burn | — |
| Fire | `SearingMark` | Searing Mark | Fire | Attacker | 1 ennemi | 0.9 | 2 | Burn, Weaken | — |
| Water | `WaterJet` | Water Jet | Water | Support | 1 ennemi | 0.85 | 0 | Slow | — |
| Water | `HealingTide` | Healing Tide | Water | Support | tous alliés | — | 4 | Mend | — |
| Water | `SoothingCurrent` | Soothing Current | Water | Support | allié le + blessé | — | 2 | Renewal, Cleanse | — |
| Nature | `VineLash` | Vine Lash | Nature | Control | 1 ennemi | 0.85 | 0 | Poison | — |
| Nature | `Entangle` | Entangle | Nature | Control | 1 ennemi | — | 3 | Stun, Root | — |
| Nature | `SporeCloud` | Spore Cloud | Nature | Control | tous ennemis | 0.4 | 3 | Poison, Weaken | — |
| Electric | `ArcStrike` | Arc Strike | Electric | Attacker | 1 ennemi | 1 | 0 | — | Quicken |
| Electric | `ChainLightning` | Chain Lightning | Electric | Attacker | tous ennemis | 0.75 | 3 | — | — |
| Electric | `OverchargeCoil` | Overcharge Coil | Electric | Support | soi | — | 3 | Haste, Rage | — |
| Earth | `StoneSlam` | Stone Slam | Earth | Tank | 1 ennemi | 0.8 | 0 | — | Guard |
| Earth | `BedrockGuard` | Bedrock Guard | Earth | Tank | soi | — | 3 | Bulwark, Taunt | — |
| Earth | `Tremor` | Tremor | Earth | Tank | tous ennemis | 0.5 | 3 | Slow | — |
| Light | `RadiantBeam` | Radiant Beam | Light | Support | 1 ennemi | 0.85 | 0 | — | Focus |
| Light | `DawnBlessing` | Dawn Blessing | Light | Support | tous alliés | — | 4 | Mend, Rage | — |
| Light | `GuidingLight` | Guiding Light | Light | Support | 1 allié | — | 2 | Renewal, Cleanse | — |
| Dark | `ShadowRake` | Shadow Rake | Dark | Control | 1 ennemi | 0.85 | 0 | Drain | — |
| Dark | `CurseOfNight` | Curse of Night | Dark | Control | tous ennemis | 0.35 | 3 | Cripple | — |
| Dark | `SoulDrain` | Soul Drain | Dark | Support | 1 ennemi | 0.9 | 2 | Drain, Weaken | — |
| Metal | `IronCharge` | Iron Charge | Metal | Tank | 1 ennemi | 0.8 | 0 | Weaken | — |
| Metal | `PlatedHide` | Plated Hide | Metal | Tank | soi | — | 3 | Barrier, Taunt | — |
| Metal | `MagnetPull` | Magnet Pull | Metal | Control | 1 ennemi | 0.4 | 2 | Root | — |
| FireWater | `CinderSpit` | Cinder Spit | Fire | Control | 1 ennemi | 0.85 | 0 | Singe, Slow | — |
| FireWater | `SmokeScreen` | Smoke Screen | Fire | Control | tous ennemis | 0.3 | 3 | Cripple, Slow | — |
| FireWater | `ChokingHaze` | Choking Haze | Water | Control | 1 ennemi | — | 3 | Stun, Poison | — |
| FireNature | `AshClaw` | Ash Claw | Fire | Attacker | 1 ennemi | 1 | 0 | Singe, Weaken | — |
| FireNature | `EmberStorm` | Ember Storm | Fire | Attacker | tous ennemis | 0.7 | 3 | Singe | — |
| FireNature | `BrambleSnare` | Bramble Snare | Nature | Attacker | 1 ennemi | 1.45 | 3 | Root | — |
| FireEarth | `MoltenFang` | Molten Fang | Fire | Attacker | 1 ennemi | 1 | 0 | Singe, Wither | — |
| FireEarth | `LavaFlow` | Lava Flow | Fire | Attacker | tous ennemis | 0.6 | 3 | Burn, Slow | — |
| FireEarth | `EruptionCore` | Eruption Core | Earth | Support | soi | — | 3 | Rage | — |
| FireElectric | `PlasmaLance` | Plasma Lance | Fire | Attacker | 1 ennemi | 1.05 | 0 | Singe | Quicken |
| FireElectric | `IonBlast` | Ion Blast | Electric | Attacker | 1 ennemi | 1.55 | 3 | Cripple | — |
| FireElectric | `StaticField` | Static Field | Electric | Control | tous ennemis | 0.4 | 3 | Slow, Weaken | — |
| FireMetal | `AnvilStrike` | Anvil Strike | Metal | Tank | 1 ennemi | 0.8 | 0 | Singe | Guard |
| FireMetal | `MoltenPlating` | Molten Plating | Metal | Tank | soi | — | 3 | Barrier, Taunt, Rage | — |
| FireMetal | `ForgeHeat` | Forge Heat | Fire | Tank | tous ennemis | 0.5 | 2 | Singe | — |
| FireDark | `HellfireBite` | Hellfire Bite | Fire | Attacker | 1 ennemi | 1.05 | 0 | Singe, Drain | — |
| FireDark | `InfernalRoar` | Infernal Roar | Fire | Attacker | tous ennemis | 0.8 | 4 | Weaken | — |
| FireDark | `SoulEmber` | Soul Ember | Dark | Attacker | 1 ennemi | 1.2 | 3 | Drain, Poison | — |
| FireLight | `SunRay` | Sun Ray | Light | Support | 1 ennemi | 0.85 | 0 | Singe | Cleanse |
| FireLight | `SolarFlare` | Solar Flare | Fire | Control | tous ennemis | 0.6 | 3 | Burn, Weaken | — |
| FireLight | `Sunbath` | Sunbath | Light | Support | tous alliés | — | 4 | Renewal, Rage | — |
| WaterNature | `MireSpit` | Mire Spit | Water | Control | 1 ennemi | 0.85 | 0 | Slow, Weaken | — |
| WaterNature | `QuagmireGrip` | Quagmire Grip | Water | Control | 1 ennemi | — | 3 | Stun, Slow | — |
| WaterNature | `BlightCloud` | Blight Cloud | Nature | Control | tous ennemis | 0.4 | 3 | Poison | — |
| WaterEarth | `FrostFang` | Frost Fang | Water | Control | 1 ennemi | 0.85 | 0 | Slow, Wither | — |
| WaterEarth | `Permafrost` | Permafrost | Water | Control | tous ennemis | 0.45 | 3 | Root | — |
| WaterEarth | `StoneTomb` | Stone Tomb | Earth | Control | 1 ennemi | — | 4 | Stun, Wither | — |
| WaterElectric | `SquallStrike` | Squall Strike | Water | Attacker | 1 ennemi | 1 | 0 | Bleed | — |
| WaterElectric | `ThunderSurge` | Thunder Surge | Electric | Attacker | tous ennemis | 0.65 | 3 | Weaken | — |
| WaterElectric | `Downpour` | Downpour | Water | Support | tous alliés | — | 4 | Renewal | — |
| WaterMetal | `CorrodedClaw` | Corroded Claw | Metal | Tank | 1 ennemi | 0.8 | 0 | Wither, Weaken | — |
| WaterMetal | `RustArmor` | Rust Armor | Metal | Tank | soi | — | 2 | Barrier | — |
| WaterMetal | `OxideCloud` | Oxide Cloud | Water | Control | tous ennemis | — | 4 | Cripple, Wither | — |
| WaterDark | `AbyssalPull` | Abyssal Pull | Dark | Control | 1 ennemi | 0.85 | 0 | Slow, Drain | — |
| WaterDark | `CrushingDepths` | Crushing Depths | Water | Control | 1 ennemi | — | 3 | Cripple, Root | — |
| WaterDark | `DrowningGrasp` | Drowning Grasp | Water | Control | 1 ennemi | 0.9 | 3 | Stun | — |
| WaterLight | `PrismJet` | Prism Jet | Light | Support | 1 ennemi | 0.85 | 0 | — | Cleanse |
| WaterLight | `PrismaticVeil` | Prismatic Veil | Light | Support | tous alliés | — | 3 | Barrier | — |
| WaterLight | `TideMend` | Tide Mend | Water | Support | allié le + blessé | — | 2 | Renewal, Rage | — |
| NatureEarth | `RootSmash` | Root Smash | Nature | Tank | 1 ennemi | 0.8 | 0 | Poison, Slow | — |
| NatureEarth | `Ironbark` | Ironbark | Nature | Tank | soi | — | 3 | Barrier, Mend | — |
| NatureEarth | `Landslide` | Landslide | Earth | Control | tous ennemis | 0.55 | 3 | Wither | — |
| NatureElectric | `PollenDart` | Pollen Dart | Nature | Support | 1 ennemi | 0.85 | 0 | Poison | Quicken |
| NatureElectric | `BloomingAura` | Blooming Aura | Nature | Support | tous alliés | — | 4 | Mend, Haste | — |
| NatureElectric | `StaticBloom` | Static Bloom | Electric | Control | 1 ennemi | — | 3 | Stun, Weaken | — |
| NatureMetal | `BarbedLash` | Barbed Lash | Nature | Tank | 1 ennemi | 0.8 | 0 | Bleed, Slow | — |
| NatureMetal | `SpikedShell` | Spiked Shell | Metal | Tank | soi | — | 3 | Barrier, Quicken | — |
| NatureMetal | `ThornVolley` | Thorn Volley | Nature | Tank | tous ennemis | 0.5 | 3 | Bleed | — |
| NatureDark | `VenomBite` | Venom Bite | Nature | Control | 1 ennemi | 0.85 | 0 | Poison, Wither | — |
| NatureDark | `ToxicBloom` | Toxic Bloom | Nature | Control | tous ennemis | 0.4 | 3 | Poison, Wither | — |
| NatureDark | `Neurotoxin` | Neurotoxin | Dark | Control | 1 ennemi | — | 4 | Stun, Poison | — |
| NatureLight | `PetalSlash` | Petal Slash | Nature | Support | 1 ennemi | 0.85 | 0 | Poison | Focus |
| NatureLight | `SpringBloom` | Spring Bloom | Nature | Support | tous alliés | — | 4 | Renewal, Cleanse | — |
| NatureLight | `SunlitGift` | Sunlit Gift | Light | Support | 1 allié | — | 2 | Rage, Cleanse | — |
| EarthElectric | `MagneticJolt` | Magnetic Jolt | Electric | Control | 1 ennemi | 0.85 | 0 | Wither | — |
| EarthElectric | `PolarityShift` | Polarity Shift | Electric | Control | tous ennemis | 0.3 | 3 | Slow, Wither | — |
| EarthElectric | `GravityGrip` | Gravity Grip | Earth | Control | 1 ennemi | — | 3 | Stun, Cripple | — |
| EarthMetal | `BronzeBash` | Bronze Bash | Metal | Tank | 1 ennemi | 0.8 | 0 | — | Guard, Focus |
| EarthMetal | `AegisStance` | Aegis Stance | Metal | Tank | soi | — | 4 | Bulwark, Taunt | — |
| EarthMetal | `GuardianCall` | Guardian Call | Earth | Support | tous alliés | — | 4 | Barrier | — |
| EarthDark | `FossilCrush` | Fossil Crush | Earth | Tank | 1 ennemi | 0.8 | 0 | Wither | Guard |
| EarthDark | `AncientCarapace` | Ancient Carapace | Earth | Tank | soi | — | 3 | Bulwark, Taunt, Mend | — |
| EarthDark | `BoneShards` | Bone Shards | Dark | Tank | tous ennemis | 0.5 | 3 | Bleed, Weaken | — |
| EarthLight | `CrystalShard` | Crystal Shard | Earth | Support | 1 ennemi | 0.85 | 0 | Weaken | Guard |
| EarthLight | `RefractiveWard` | Refractive Ward | Light | Support | tous alliés | — | 4 | Bulwark | — |
| EarthLight | `CrystalSong` | Crystal Song | Earth | Support | allié le + blessé | — | 2 | Renewal, Haste | — |
| ElectricMetal | `CircuitStrike` | Circuit Strike | Electric | Attacker | 1 ennemi | 1 | 0 | Weaken | Quicken |
| ElectricMetal | `OverloadSurge` | Overload Surge | Electric | Attacker | tous ennemis | 0.7 | 4 | Stun | — |
| ElectricMetal | `SystemPurge` | System Purge | Metal | Support | soi | — | 3 | Cleanse, Haste | — |
| ElectricDark | `ThunderFang` | Thunder Fang | Electric | Attacker | 1 ennemi | 1.05 | 0 | Slow | Focus |
| ElectricDark | `BlackBolt` | Black Bolt | Dark | Attacker | 1 ennemi | 1.6 | 4 | Burn | — |
| ElectricDark | `StormCurse` | Storm Curse | Electric | Control | tous ennemis | 0.35 | 3 | Cripple, Wither | — |
| ElectricLight | `AuroraBeam` | Aurora Beam | Electric | Support | 1 ennemi | 0.85 | 0 | Slow | Quicken |
| ElectricLight | `PolarLights` | Polar Lights | Light | Support | tous alliés | — | 3 | Mend, Haste | — |
| ElectricLight | `DazzlingFlash` | Dazzling Flash | Light | Control | tous ennemis | — | 4 | Stun, Weaken | — |
| MetalDark | `BladeDance` | Blade Dance | Metal | Attacker | 1 ennemi | 1.05 | 0 | Bleed | Focus |
| MetalDark | `ShadowCut` | Shadow Cut | Dark | Attacker | 1 ennemi | 1.45 | 3 | Drain, Bleed | — |
| MetalDark | `EdgeSharpening` | Edge Sharpening | Metal | Attacker | soi | — | 2 | Rage | — |
| MetalLight | `SilverStrike` | Silver Strike | Metal | Tank | 1 ennemi | 0.8 | 0 | Bleed | Guard |
| MetalLight | `MirrorPlating` | Mirror Plating | Metal | Tank | soi | — | 3 | Barrier, Taunt, Cleanse | — |
| MetalLight | `PurifyingGleam` | Purifying Gleam | Light | Support | tous alliés | — | 4 | Mend, Cleanse | — |
| DarkLight | `EclipseSlash` | Eclipse Slash | Dark | Control | 1 ennemi | 0.9 | 0 | Drain, Wither | — |
| DarkLight | `TotalDarkness` | Total Darkness | Dark | Control | tous ennemis | — | 4 | Cripple, Stun | — |
| DarkLight | `EquinoxGrace` | Equinox Grace | Light | Support | tous alliés | — | 4 | Renewal, Haste | — |
