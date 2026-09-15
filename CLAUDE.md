# Wyrmhaven

Jeu Roblox solo-persistant d'élevage de dragons (genre "élevage de
créatures" façon collection/gestion d'île) : le joueur gère une île avec
des habitats, des dragons (Œuf → Bébé → Adulte, revenu passif en Pièces),
une Ferme (Nourriture), un Shop et une Nurserie à venir. Nom de travail
choisi pour éviter toute référence à un titre existant du genre — ne
jamais utiliser d'autre nom dans le code/l'UI.

## Si on te demande de "faire la to do list" / "traiter la todo"

Va directement dans `todo/`, lis `todo/README.md` (protocole complet), et
traite une ou plusieurs tâches disponibles (voir la section "État" en bas
de ce README pour ce qui est prêt sans dépendance bloquante). Pas besoin de
redemander confirmation pour démarrer — c'est une demande explicite de
traiter le dossier. Résumé attendu à la fin : quelles tâches traitées,
lesquelles supprimées (faites ou déjà obsolètes), lesquelles laissées de
côté et pourquoi.

## Architecture

**Le code du jeu vit dans Roblox Studio, pas dans ce repo.** Pas de Rojo
(choix explicite de l'utilisateur) — tout se construit via le MCP
`Roblox_Studio` (`execute_luau`, `multi_edit`, `script_read`,
`search_game_tree`, etc.) directement sur la place Studio ouverte
("TestingPlace" au moment de la rédaction — confirme via
`list_roblox_studios` si plusieurs instances sont listées, et demande
avant de modifier si ce n'est pas évident lequel cibler).

Structure Studio actuelle :
- `ReplicatedStorage.Wyrmhaven.Config.*` — définitions partagées
  (`GameConstants`, `DragonDefs`, `HabitatDefs`, `BreedingTable`)
- `ReplicatedStorage.Wyrmhaven.Remotes.*` — RemoteEvents
- `ServerScriptService.Wyrmhaven.Services.*` — logique autoritaire
  (`HabitatService`, `DragonService`, et ce qu'ajoutent les tâches en
  cours dans `todo/`)
- `ServerScriptService.Wyrmhaven.Server` — bootstrap serveur (crée l'île,
  l'habitat et l'œuf de départ au join)
- `StarterPlayer.StarterPlayerScripts.Wyrmhaven.Client` +
  `Controllers.*` — caméra scriptable top-down façon Dragon Mania Legends
  (glisser pour déplacer, angle et distance **jamais** modifiés) +
  interactions clic/tap par raycast (**pas de personnage** —
  `Players.CharacterAutoLoads = false`, tout le placement/l'interaction se
  fait caméra + clic, jamais via un avatar qui se déplace)

Toute la logique de progression/monnaie/sauvegarde est **côté serveur
uniquement** (autoritaire) — le client envoie des requêtes via
RemoteEvents, ne modifie jamais l'état directement.

`Workspace.StreamingEnabled` doit rester à `false` : sans personnage, rien
ne sert de point de repère pour le streaming, donc du contenu resterait
invisible côté client si c'était activé (bug déjà rencontré une fois).
C'est un réglage d'édition (un Script en jeu n'a pas la capacité de
l'écrire) — si jamais il revient à `true`, corrige-le depuis le MCP en
mode `Edit`, pas depuis un Script.

## Autres conventions du projet

- `style-guide.md` (racine) : référence obligatoire avant de générer un
  modèle 3D (skill `roblox-3d-builder`) — palette, proportions, matériaux
  par élément.
- `todo/` : tâches en attente, voir `todo/README.md` pour le protocole
  complet (vérifier avant de coder si déjà fait, supprimer le fichier une
  fois la tâche terminée ET testée en Play — pas juste écrite).
- `docs/design/` : docs de design Phase 2 produits par les tâches
  `todo/design-doc-*.md` (Shop, Reproduction, Éléments, Monétisation).
- `studio-export/` : export en `.luau` du code Studio (miroir de la
  hiérarchie, généré via le MCP `search_game_tree`/`script_read` — pas de
  Rojo, pas de sync automatique). Voir `studio-export/README.md` pour la
  convention ; à régénérer (fichiers concernés seulement) après une session
  de travail notable sur des scripts Studio.
