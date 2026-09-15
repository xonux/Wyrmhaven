# Dossier to-do — Wyrmhaven

Chaque fichier `.md` de ce dossier est une tâche indépendante. Convention à suivre,
humain ou agent :

1. **Avant de commencer** : vérifie l'état réel du projet dans Roblox Studio (MCP
   `Roblox_Studio`, place "TestingPlace" — utilise `list_roblox_studios` pour
   confirmer l'instance si plusieurs sont listées un jour, et demande confirmation
   à l'utilisateur avant de modifier si ce n'est pas évident). Si la tâche est déjà
   faite, ou rendue inutile par un changement depuis sa rédaction, **supprime le
   fichier sans rien coder** et dis-le dans ton résumé.

2. **Une fois la tâche terminée et testée en Play** (pas juste écrite — voir
   les fichiers de tâche pour ce que "testé" veut dire), supprime le fichier
   (`git rm todo/<fichier>.md` ou suppression + commit). C'est le signal "fait".
   L'historique du travail vit dans les commits git et dans les scripts Studio
   eux-mêmes, pas dans ce dossier : un fichier restant = travail restant, dossier
   vide = tout est fait.

3. Si tu bosses en parallèle d'autres agents, prends un fichier différent des
   leurs. Pas de verrou automatique : si tu veux signaler que tu es dessus,
   ajoute une ligne `**EN COURS (agent X)**` en haut du fichier avant de
   commencer, et retire-la si tu abandonnes sans finir.

   **Vérifie la course (race condition) après avoir posé ton marqueur** :
   relis le fichier juste après ton édition. S'il ne montre que ton propre
   marqueur, tu es bon. Si un marqueur d'un autre agent apparaît aussi
   (ça arrive : deux agents peuvent lire le fichier "libre" avant que l'un
   des deux n'ait fini d'écrire son marqueur), c'est que vous vous êtes pris
   de vitesse — retire ta propre édition (remets le fichier avec seulement
   le marqueur de l'autre agent, celui qui semble être arrivé en premier)
   et laisse cette tâche tranquille, prends-en une autre. Ne travaille
   jamais sur un fichier qui porte le marqueur de quelqu'un d'autre, même
   découvert après coup.

4. Tout le code du jeu vit dans la place Roblox Studio via le MCP
   `Roblox_Studio` — pas de fichiers `.lua` dans ce repo (voir
   `git-versioning-strategy.md` pour le sujet non résolu de la sauvegarde de ce
   code). Structure actuelle :
   - `ReplicatedStorage.Wyrmhaven.Config.*` — définitions partagées
     (GameConstants, DragonDefs, HabitatDefs, BreedingTable)
   - `ReplicatedStorage.Wyrmhaven.Remotes.*` — RemoteEvents
   - `ServerScriptService.Wyrmhaven.Services.*` — logique autoritaire
     (HabitatService, DragonService)
   - `ServerScriptService.Wyrmhaven.Server` — bootstrap serveur
   - `StarterPlayer.StarterPlayerScripts.Wyrmhaven.Client` +
     `Controllers.*` — caméra top-down (pan seul, angle fixe) + interactions
     clic/tap (pas de personnage, `Players.CharacterAutoLoads = false`)

5. Si une tâche dépend d'une autre encore présente dans ce dossier, dis-le et
   laisse-la de côté plutôt que de bricoler une solution incompatible — voir
   la section "Dépendances" de chaque fichier.

6. Les tâches de doc pure produisent des fichiers dans `docs/design/`
   (repo, markdown normal) — ce sont les seules tâches de ce dossier qui
   ne touchent pas à Roblox Studio.

7. **Studio n'a pas de branches.** Si deux agents travaillent en parallèle
   sur des tâches qui touchent le même script (voir "Attention conflit
   d'édition" / "Coordonne" dans les fichiers concernés), relis le script
   avec `script_read` juste avant d'éditer plutôt que de te fier à l'état
   décrit dans le fichier de tâche — il a pu changer entre-temps. Utilise
   `multi_edit` avec des `old_string` qui correspondent à l'état réel du
   script au moment où tu édites.

8. **Fichiers très partagés en Phase 2** — quasiment toutes les tâches
   Phase 2 touchent un sous-ensemble de : `SaveService`,
   `ServerScriptService.Wyrmhaven.Server` (bootstrap), `DragonService`,
   `HabitatService`, `GameConstants`, `DragonDefs`, `HabitatDefs`,
   `BreedingTable`, et un éventuel `ShopService` partagé entre les 3
   tâches Shop. Relis systématiquement ces fichiers juste avant d'éditer,
   plus encore qu'en Phase 1 — plusieurs tâches Phase 2 se recoupent
   volontairement dessus (voir "Dépendances"/"Coordonne" de chaque tâche).

## État au 2026-09-15 (fin de journée)

Phase 1 entièrement faite et vérifiée en Play (île, habitat, ferme, cycle
de vie, Pièces/Gemmes/Nourriture, sauvegarde DataStore round-trip, caméra,
HUD). Les 4 docs de design Phase 2 (`docs/design/`) et la décision de
versioning (`studio-export/`) sont faits.

**Phase 2 : dossier vide, tout est fait et testé en Play** —
`shop-habitats.md`, `shop-decorations.md`, `shop-exclusive-dragons.md`,
`nursery-breeding.md`, `elements-expansion.md`, `monetization-robux.md`,
`shop-ui.md`, `breeding-exclusive-dragon-softlock.md` (dernier fermé le
2026-09-15 : `Breedable = false` sur `DragonDefs.FireExclusive`, refus
vérifié côté `BreedingService.StartBreeding` + filtré côté liste de
sélection, régression Feu+Feu normal confirmée par suite de tests
automatisée).

**Point ouvert non bloquant** : `MonetizationService` est codé mais utilise
des `productId`/`gamePassId` placeholder — aucun vrai Developer
Product/Game Pass n'a été créé sur la page Roblox, et les prix proposés
dans `docs/design/phase2-monetization.md` n'ont pas été confirmés par
l'utilisateur (argent réel, volontairement laissé en attente).

`ServerScriptService.Wyrmhaven.Services` contient maintenant :
`HabitatService`, `DragonService`, `EconomyService`, `FarmService`,
`SaveService`, `HudService`, `ShopService`, `MonetizationService`,
`BreedingService`, `DecorationService`. Plusieurs habitats par élément sont
supportés (`HabitatService.GetPlayerHabitats`/`FindFreeSlotForElement`,
`DragonService` records portent un `habitatId`) — `SaveService` sauvegarde/
recharge cette structure multi-habitats.

Note perf : sous forte charge concurrente (plusieurs agents + Play actif),
`script_read` peut échouer de façon transitoire ("Script not found" /
"Target is not reachable") même quand `search_game_tree` confirme que le
script existe — retentez avant de conclure à un vrai problème. Studio bascule
aussi souvent en mode Play pendant que d'autres sessions testent — les
outils `Edit` (dont `multi_edit`) échouent alors ; attends que
`get_studio_state` remontre "Edit" avant de réessayer.
