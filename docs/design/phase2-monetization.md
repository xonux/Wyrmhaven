# Design — Monétisation Robux (Phase 2)

> **Argent réel en jeu.** Tous les prix/contenus ci-dessous sont des
> propositions de travail, à valider explicitement par l'utilisateur avant
> toute implémentation `MarketplaceService` réelle — ne pas coder
> l'intégration tant que ce document n'a pas été relu et confirmé.

## Packs de Gemmes (Developer Products)

| Pack | Gemmes | Prix Robux | Bonus vs. taux de base |
|---|---|---|---|
| Petit | 100 | 99 R$ | — (taux de référence) |
| Moyen | 550 | 499 R$ | +10% |
| Grand | 1200 | 999 R$ | +20% |
| Méga | 2600 | 1999 R$ | +30% |

Taux de référence ≈ 1 Robux/Gemme sur le pack Petit ; les paliers
supérieurs donnent plus de Gemmes par Robux pour inciter à l'achat groupé
— schéma classique, valeurs à ajuster par l'utilisateur selon son propre
positionnement prix.

## Game Pass — "Pack de démarrage"

Contenu proposé (achat unique, une fois par joueur) :
- 500 Gemmes (crédité immédiatement à l'achat).
- 1 décoration offerte au choix parmi les décorations Petites du Shop (voir
  `phase2-shop.md`) — évite d'imposer un objet, laisse un choix simple en
  UI.
- Boost Ferme : proposition **x2 sur le taux d'accumulation de Nourriture,
  permanent** (plutôt qu'un boost temporaire 24h, pour que l'achat garde
  sa valeur perçue sur le long terme — un Game Pass est un achat unique,
  pas un consommable).
- Prix proposé : **149 Robux**.

## Ce que chaque produit débloque (côté implémentation)

- **Packs de Gemmes** (Developer Products) : `ProcessReceipt` appelle
  `EconomyService.AddGems(player, montant)`.
- **Game Pass démarrage** : au moment de l'achat (callback
  `PromptGamePassPurchaseFinished`) ou détecté au `PlayerAdded` via
  `UserOwnsGamePassAsync` :
  - `EconomyService.AddGems(player, 500)` (une seule fois — voir
    idempotence ci-dessous).
  - Enregistre la décoration choisie comme possédée (nouveau champ dans le
    futur schéma `SaveService`, ou service dédié `DecorationService` si
    `phase2-shop.md` est implémenté d'ici là).
  - Pose un flag `FarmFoodRateMultiplier = 2` lu par `FarmService` dans son
    calcul d'accumulation.

## Plan d'implémentation technique (haut niveau)

- **Developer Products** : `MarketplaceService.ProcessReceipt` — mapper
  chaque `productId` connu vers une fonction de crédit (`AddGems` avec le
  bon montant), retourner `Enum.ProductPurchaseDecision.PurchaseGranted`
  uniquement après succès du crédit. Point critique : Roblox peut rejouer
  un reçu si le serveur ne répond pas à temps — il faut un moyen de savoir
  qu'un `PurchaseId` a déjà été traité (table en mémoire ne suffit pas
  après un redémarrage serveur ; dépend de `save-service.md` pour
  persister les `PurchaseId` traités par joueur, sans quoi un joueur
  pourrait être re-crédité ou, pire, jamais crédité si le process crash
  juste après le paiement).
- **Game Pass** : `MarketplacePlayerOwnsAssetIdRejected`... plus
  simplement `MarketplaceService:UserOwnsGamePassAsync(userId, gamePassId)`
  vérifié au `PlayerAdded` (avec retry/pcall — l'appel peut échouer), plus
  écoute de `PromptGamePassPurchaseFinished` pour créditer immédiatement
  si acheté en cours de session sans attendre le prochain join. Idempotence
  ici plus simple qu'un Developer Product : un Game Pass est binaire
  (possédé ou non), donc un flag `StarterPackGranted` sauvegardé (via
  `save-service.md`) suffit à éviter un double crédit.

## Rappel

Les montants Gemmes/Robux et le contenu du Game Pass ci-dessus sont des
**propositions**, pas des décisions prises — à faire valider explicitement
par l'utilisateur (impact argent réel) avant toute création réelle de
Developer Products/Game Pass sur la page Roblox et avant tout code
`MarketplaceService`.

## Dépendances de conception

Référence `phase2-shop.md` (les packs de Gemmes vivront dans le même Shop
UI) et `save-service.md` (idempotence des achats, persistance du flag
Game Pass).
