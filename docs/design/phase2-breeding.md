# Design — Reproduction / Nurserie (Phase 2)

> Proposition à valider par l'utilisateur — contraintes et valeurs
> numériques non définitives.

## Contexte

Une Nurserie (nouvelle structure posée sur l'île, comme un Habitat ou la
Ferme) permet de faire se reproduire deux dragons Adultes. Résultat
déterminé par `ReplicatedStorage.Wyrmhaven.Config.BreedingTable`, une table
fixe (pas de génération aléatoire). Le stub existe déjà côté Studio
(`return {}`).

## Flow complet

1. Le joueur clique sur la Nurserie (même mécanique de raycast clic que
   Habitat/Ferme/Dragon — `InteractionController`).
2. Le client ouvre une UI de sélection listant les dragons Adultes du
   joueur (pas de personnage à faire déplacer, tout se pilote depuis cette
   liste — données transmises par le serveur, pas lues directement côté
   client).
3. Le joueur choisit 2 dragons Adultes → `RequestStartBreeding(dragonIdA,
   dragonIdB)`.
4. Le serveur valide : les deux dragons appartiennent au joueur, sont
   Adultes, ne sont pas déjà en cours de reproduction (nouveau flag
   `IsBreeding` par dragon), et la Nurserie n'a pas déjà atteint sa
   capacité de paires simultanées (voir Contraintes).
5. Si valide : démarre un minuteur (`BreedingDurationSeconds`, nouvelle
   constante `GameConstants`), les deux dragons passent `IsBreeding = true`
   (ne peuvent plus être nourris/récoltés/re-sélectionnés pendant ce temps
   — comportement à confirmer, alternative : ils restent productifs mais
   juste indisponibles pour une autre reproduction).
6. À la fin du minuteur, l'œuf est "prêt à collecter" (pas auto-spawné —
   évite qu'un slot d'habitat soit bloqué si le joueur est absent).
7. Le joueur re-clique la Nurserie → `RequestCollectEgg(pairingId)` → le
   serveur détermine l'élément résultat via `BreedingTable[elemA][elemB]`,
   cherche un slot libre dans un habitat de cet élément appartenant au
   joueur, et y crée l'œuf via `DragonService` (même fonction que l'œuf de
   départ). Si aucun slot libre : l'œuf reste "en attente de collecte",
   message client "aucune place disponible", le joueur doit libérer un
   slot (vendre/faire grandir un dragon) avant de pouvoir collecter.
8. Les deux parents repassent `IsBreeding = false` et redeviennent
   utilisables normalement (nourrissage, récolte, nouvelle reproduction).

## Structure `BreedingTable`

```lua
BreedingTable = {
	[elementA] = {
		[elementB] = resultElement,
		...
	},
	...
}
```

Table **symétrique en usage** (le service doit tester les deux ordres,
`BreedingTable[A][B]` puis `BreedingTable[B][A]`, ou la remplir dans les
deux sens directement pour simplifier le lookup côté service — plus sûr,
évite un bug d'ordre d'arguments). Tant que seul Feu existe (Phase 1), la
table reste soit vide soit avec juste `Fire.Fire = "Fire"` (dégénéré —
Feu+Feu ne peut de toute façon produire que Feu, un lookup absent devrait
donc **fallback sur le même élément que les deux parents si A == B**,
plutôt que d'exiger une entrée explicite pour ce cas trivial). Voir
`phase2-elements.md` pour une proposition de remplissage complet une fois
Eau/Nature/Foudre/Terre ajoutés.

## Contraintes

- Les deux dragons doivent être sur l'île **du même joueur** — trivialement
  toujours vrai vu que le jeu est solo-persistant (une île par joueur,
  pas d'îles partagées), donc pas de vérification cross-joueur à écrire,
  juste vérifier que les deux `dragonId` appartiennent bien au joueur qui
  fait la requête (anti-triche basique côté serveur).
- Les deux dragons doivent être **Adultes** (pas Œuf/Bébé).
- Capacité de la Nurserie : proposition **1 paire simultanée** en Phase 2
  (simple, évite la question de plusieurs minuteurs à afficher en UI) —
  extensible plus tard via achat Shop (voir `phase2-shop.md`) si souhaité.
- Cooldown après collecte : proposition **aucun cooldown supplémentaire**
  au-delà du temps de reproduction lui-même — les parents redeviennent
  immédiatement disponibles pour une nouvelle paire. À revoir si ça permet
  de spammer des œufs trop vite une fois plusieurs habitats possédés.
- `BreedingDurationSeconds` : proposition **300s (5 min)** en Phase 2 pour
  rester testable, à ajuster pour l'équilibrage réel plus tard.

## Remotes / Services futurs

- `ServerScriptService.Wyrmhaven.Services.BreedingService` : logique
  autoritaire (validation, minuteur, résolution `BreedingTable`, création
  de l'œuf via `DragonService`).
- `ReplicatedStorage.Wyrmhaven.Remotes.RequestStartBreeding(dragonIdA,
  dragonIdB)`.
- `ReplicatedStorage.Wyrmhaven.Remotes.RequestCollectEgg(pairingId)`.
- `ReplicatedStorage.Wyrmhaven.Remotes.BreedingStatusUpdated` (serveur→
  client, pousse l'état de la paire en cours — temps restant, prête à
  collecter — pour piloter l'UI de la Nurserie sans polling).

## Dépendances de conception

Cohérent avec `phase2-elements.md` (remplissage concret de
`BreedingTable`). Dépend techniquement de `save-service.md` pour persister
`IsBreeding`/le minuteur en cours si un joueur se déconnecte pendant une
reproduction (sinon l'état de paire en cours est perdu au redémarrage
serveur — acceptable en Phase 1/2 tant que non résolu, mais à noter comme
lacune connue).
