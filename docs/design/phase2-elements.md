# Design — Éléments supplémentaires (Phase 2)

> Proposition à valider par l'utilisateur, rien n'est définitif ici — ni la
> liste d'éléments, ni les valeurs numériques, ni les couleurs.

## Contexte

Phase 1 ne gère que l'élément **Feu**. Cette page propose les éléments
suivants et leurs valeurs de configuration (`DragonDefs`/`HabitatDefs`),
construites pour rester équilibrées avec Feu (mêmes seuils, même revenu)
sauf mention contraire.

## Éléments proposés

Quatre éléments, choisis pour offrir une bonne diversité visuelle et de
gameplay sans exploser la portée : **Eau**, **Nature**, **Foudre**,
**Terre**. (Proposition — l'utilisateur peut vouloir en retirer, renommer,
ou en ajouter d'autres, ex. Glace, Ombre.)

## Palette par élément

Même structure de slots que `style-guide.md` (main / shadow / belly-pale /
horn-dark / accent-dark / iris). Le Feu utilise une iris chaude (ambre)
assortie au corps — convention volontairement exceptionnelle documentée
dans le style guide. Les éléments ci-dessous suivent la convention par
défaut : iris **froide et contrastante** pour les corps chauds/neutres, et
inversement une iris **chaude et contrastante** pour un corps déjà froid
(Eau), pour garder un point focal lisible sur chaque créature.

### Eau
- Main (dos/flancs) : `#2E86D9`
- Shadow (queue, base de crête, sourcil) : `#1B5A9E`
- Belly-pale (ventre, mâchoire, membrane d'aile, griffes) : `#C9EFFF`
- Horn-dark / Accent-dark (narines, ligne de bouche, pupille) : `#0A1A22`
- Iris (contrastante, chaude) : ambre clair `#F5C24D`

### Nature
- Main : `#4CAF50`
- Shadow : `#2E7D32`
- Belly-pale : `#E8F5C0`
- Horn-dark / Accent-dark : `#1B2E12`
- Iris (contrastante, froide) : cyan `#4DD0E1`

### Foudre
- Main : `#8E5FD1`
- Shadow : `#5A2E9E`
- Belly-pale : `#F5E9FF`
- Horn-dark / Accent-dark : `#1A0F2E`
- Accent crête (équivalent des pointes flamme du Feu) : jaune électrique
  `#F5E642`
- Iris (contrastante) : jaune électrique `#F5E642` (même couleur que
  l'accent crête, cohérent avec le thème "énergie")

### Terre
- Main : `#8A6A4A`
- Shadow : `#5C4530`
- Belly-pale : `#E8D9B8`
- Horn-dark / Accent-dark : `#2E2013`
- Iris (contrastante, froide) : vert mousse `#7CB342`

## Valeurs `DragonDefs` / `HabitatDefs`

Proposition : **identiques à Feu** pour les quatre nouveaux éléments, afin
de ne pas créer de méta "élément le plus rentable" dès leur introduction.
Seuls `DisplayName`, `StageColors` (palette ci-dessus) et
`HabitatDefs.<Element>.PlatformColor` changent.

```
EggGrowthRequired = 100
BabyGrowthRequired = 150
IncomeRatePerSecond = 1
IncomeCap = 100
Attack/Defense/Health = mêmes valeurs par défaut que Feu, voir
  dragon-combat-stats.md pour la convention (orientation par élément à
  définir : Eau plutôt Defense, Nature plutôt Health, Foudre plutôt
  Attack, Terre plutôt Defense — propositions, pas tranché).

HabitatDefs.<Element>.Capacity = 4
HabitatDefs.<Element>.BaseCost = valeur Shop (voir phase2-shop.md),
  pas 0 comme Feu (Feu est gratuit car c'est l'habitat de départ)
HabitatDefs.<Element>.CostGrowth = 1.6 (identique à Feu)
HabitatDefs.<Element>.PlatformSize = Vector3.new(16, 1, 16) (identique)
```

## Remplissage de `BreedingTable`

Voir `phase2-breeding.md` pour le format complet. Proposition de
combinaisons pour ces quatre éléments (toutes symétriques : A+B == B+A) —
**pas de nouvel élément hybride en Phase 2**, chaque combinaison produit un
élément existant parmi les cinq (cohérent avec la contrainte "pas de
génération aléatoire, table fixe") :

| A × B    | Résultat |
|----------|----------|
| Feu + Eau       | Eau (l'eau "éteint" le feu — élément dominant) |
| Feu + Nature    | Feu |
| Feu + Foudre    | Foudre |
| Feu + Terre     | Terre |
| Eau + Nature    | Nature |
| Eau + Foudre    | Eau |
| Eau + Terre     | Terre |
| Nature + Foudre | Nature |
| Nature + Terre  | Nature |
| Foudre + Terre  | Terre |
| X + X (même élément) | X |

Logique proposée : chaque paire a un "élément dominant" fixe, pas de règle
générale déductible (table à main levée, éditable librement) — c'est
volontairement arbitraire/thématique plutôt qu'un système de forces/
faiblesses à apprendre par le joueur. À valider ou réviser avec
l'utilisateur, en particulier si des éléments hybrides (Vapeur, Boue,
Cristal...) sont souhaités pour une Phase 3.

## Dépendances de conception

Cohérent avec `phase2-breeding.md` (remplissage de `BreedingTable`) et
`phase2-shop.md` (prix `BaseCost` des nouveaux habitats).
