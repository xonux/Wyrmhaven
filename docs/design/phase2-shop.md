# Design — Shop (Phase 2)

> Proposition à valider par l'utilisateur — valeurs numériques et
> mécaniques de décoration non définitives.

## Catégories

| Catégorie | Monnaie | Description |
|---|---|---|
| Habitats supplémentaires | Pièces | Un habitat de plus, par élément débloqué (Feu en Phase 1, puis Eau/Nature/Foudre/Terre — voir `phase2-elements.md`) |
| Décorations | Pièces | Bonus % passif sur le revenu des structures à proximité |
| Dragons exclusifs | Gemmes | Achat direct, hors œuf/reproduction |

Les Gemmes de départ (packs Robux, Game Pass) sont couvertes par
`phase2-monetization.md`, pas ici.

## Habitats supplémentaires

Prix basé sur `HabitatDefs.<Element>.BaseCost` et `CostGrowth` (déjà
présents côté Studio, ex. Feu : `BaseCost = 0` pour le tout premier —
gratuit, offert au join — puis `CostGrowth = 1.6` multiplicatif par
habitat supplémentaire du même élément déjà possédé). Formule proposée
pour le n-ième habitat supplémentaire d'un élément (n ≥ 1, le premier
habitat de l'élément étant gratuit uniquement pour Feu au tout premier
join) :

```
Prix(n) = BaseCostRéel(élément) * CostGrowth ^ (nombre d'habitats déjà
          possédés de cet élément)
```

`BaseCostRéel` doit être défini pour chaque élément (Feu vaut 0 uniquement
pour l'habitat de départ gratuit — un 2ᵉ habitat Feu doit avoir un vrai
coût de base, ex. **200 Pièces**, proposition à valider). Capacité par
habitat reste fixe (`Capacity = 4`, déjà en place) — pas d'agrandissement
de capacité prévu dans cette tâche.

## Décorations

Bonus en % sur le revenu (Pièces et/ou Nourriture) des structures dans un
rayon donné. Proposition :
- Rayon d'effet : **20 studs** autour de la décoration (à comparer à
  `HabitatDefs.PlatformSize = 16x16` et `IslandSpacingStuds = 80` — assez
  pour couvrir un habitat/la Ferme adjacents sans déborder sur l'île
  voisine).
- Bonus par tier de décoration : Petite (+5%), Moyenne (+10%), Grande
  (+15%) — appliqué en multiplicatif sur `IncomeRatePerSecond` (habitats)
  ou le taux d'accumulation de la Ferme, selon la ressource ciblée par la
  décoration (certaines décorations bonifient les Pièces, d'autres la
  Nourriture — à choisir par objet, pas un bonus universel).
- Cumul : les bonus de plusieurs décorations à portée d'une même structure
  s'additionnent (pas de multiplication en chaîne, pour rester lisible),
  **plafonné à +50%** cumulé par structure pour éviter une dérive
  exponentielle si le joueur en aligne beaucoup.
- Prix : Pièces, croissant avec le tier (ex. 300 / 800 / 2000 Pièces —
  proposition simple, pas d'équilibrage poussé).

## Dragons exclusifs

- Entrées `DragonDefs` marquées `Exclusive = true` avec un champ
  `GemPrice`. Achetables uniquement contre Gemmes, jamais obtenables via
  œuf normal ou `BreedingTable` (le service de reproduction doit ignorer
  les entrées `Exclusive` comme résultat possible).
- Spawn direct en tant qu'Adulte (pas d'œuf à faire grandir — c'est
  l'intérêt de payer en argent réel/Gemmes) dans un slot d'habitat libre de
  leur élément ; achat refusé si aucun slot libre (même contrainte que la
  collecte d'œuf de reproduction).
- Peuvent servir de parent dans la Nurserie comme un dragon normal, sauf
  mention contraire sur la définition (`Breedable = false` optionnel pour
  les cas où l'utilisateur voudrait les garder uniques) — à trancher.

## UI envisagée

Un bouton Shop permanent à l'écran (comme le HUD Pièces/Gemmes — pas de
bâtiment/kiosque à visiter vu l'absence de personnage). Ouvre un
`ScreenGui` plein écran avec 3 onglets (Habitats / Décorations / Dragons),
chaque onglet listant des cartes objet (icône/couleur, nom, prix, bouton
Acheter désactivé si solde insuffisant ou déjà possédé pour les objets
uniques).

## Remotes / Services futurs

- `ServerScriptService.Wyrmhaven.Services.ShopService` : logique
  autoritaire d'achat (vérifie solde via `EconomyService`, débite, crée
  l'instance achetée via `HabitatService`/`DragonService`/un futur
  `DecorationService`).
- `ReplicatedStorage.Wyrmhaven.Remotes.RequestBuyHabitat(element)`.
- `ReplicatedStorage.Wyrmhaven.Remotes.RequestBuyDecoration(decorationId,
  targetPosition)`.
- `ReplicatedStorage.Wyrmhaven.Remotes.RequestBuyDragon(dragonDefId)`
  (Gemmes, dragons exclusifs).
- Nouveau module `ReplicatedStorage.Wyrmhaven.Config.DecorationDefs`
  (catalogue décorations : tier, prix, rayon, % bonus, ressource ciblée).

## Dépendances de conception

Référence `phase2-elements.md` (prix de base par élément) et
`phase2-monetization.md` (source des Gemmes dépensées ici).
