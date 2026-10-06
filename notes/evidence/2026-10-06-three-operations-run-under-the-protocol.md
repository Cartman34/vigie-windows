# Trois opérations éprouvées sous protocole — et ce que l'épreuve a montré

Sujet **S14** : au 30/09, `vigie-update` était la **seule** opération éprouvée en production. Les autres étaient
écrites, relues, jamais exécutées par ce chemin. Relevé de l'épreuve du 06/10.

## Ce qui a tourné

| Opération | Carte | Durée | Code | Marque vue pendant | Résultat écrit |
|---|---|---|---|---|---|
| `pkg-check-updates` (Chocolatey) | `pkg-choco` | 4 s | 0 | — trop courte | oui |
| `pkg-check-updates` (pip) | `pkg-pip` | 6 s | 0 | — trop courte | oui |
| `disk-analyze` | `storage` | **613 s** | 0 | **oui** | oui |
| `vigie-update` | `deployment` | 138 s | 0 | oui | oui |

`disk-analyze` : `C:\ — 374 316 dossiers, 1 614 018 fichiers, 613 s`. C'est la première fois qu'elle passe par le
protocole en vrai ; elle y était déclarée depuis le 13/09.

**Reste non éprouvée** : l'installation Windows Update. Je n'installe pas de mise à jour, c'est une consigne.

## Ce que l'épreuve a montré, et qui n'était pas prévu

### `/operations` ne donne pas le numéro de processus

Le protocole dit que la marque **porte le numéro du processus qui fait le travail**, et qu'un processus disparu sans
résultat est un échec. La marque le porte bien — `Set-ModuleBusyMark` écrit `pid`. Mais `Get-RunningOperations`, qui
sert la route, ne le recopie pas :

```
module | label | action | resources | at        <- ce que la route donne
label  | pid   | action | resources | button | log | at   <- ce que la marque porte
```

Or le protocole désigne `/operations` comme **le seul endroit** où se lit l'état d'une opération. Personne ne peut
donc, par la porte prévue, distinguer une opération vivante d'une opération morte : le contrôle existe, mais il lit
la marque en direct, ailleurs.

### Les deux défauts d'interface trouvés pendant l'épreuve

Ils ont leur propre relevé — [une carte occupée ne disait pas par quoi, et ne se déplaçait
plus](2026-10-06-a-busy-card-said-nothing-and-could-not-be-moved.md) — et leur arbitrage, **D130**. Ils n'auraient
pas été vus sans une opération assez longue pour qu'on la regarde : 613 secondes.

## Ce qui reste à faire pour S14

- Exposer le numéro de processus sur `/operations`, puisque c'est la porte que le protocole désigne.
- Éprouver l'installation Windows Update — geste du propriétaire.
- Trancher si les passes internes rejoignent `/operations` (question ouverte depuis le 30/09).
