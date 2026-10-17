# Le mode `file://` ne peut plus valider le panneau — ce qui a été vérifié

**17/10/2026.** Relevé pris au moment de découper le panneau (**D132**, sujet **S25**), parce que deux points de la
cible — la page rendue par le serveur (**UI-RENDER**) et le script en modules (**UI-MODULES**) — rendent impossible
le chemin de validation que **D06** avait retenu : ouvrir `apps/frontend-web/index.html` en `file://` dans un
navigateur et lire la console.

## Pourquoi ce chemin disparaît

- **Un navigateur refuse les modules ES en `file://`.** Un `import` déclenche une requête soumise à la politique
  d'origine, et une page ouverte depuis le disque n'a pas d'origine : le chargement échoue avant la première ligne.
- **Il n'y a plus de fichier à ouvrir.** La page est devenue `apps/frontend-web/views/index.pode`, un gabarit : ce
  qui est entre `$(` et `)` n'a de sens qu'une fois rendu. Ouvert tel quel, il n'affiche pas le panneau.

## Ce que ça coûte vraiment : rien que nous ayons encore

Trois faits, vérifiés avant de trancher :

1. **D47 l'interdisait déjà.** L'en-tête de la page portait depuis cette décision : « NE PAS ouvrir ce fichier en
   `file://` : sans jeton d'API il n'affiche rien de réel. Toute vérification passe par le serveur. »
2. **Node répond.** Il n'est pas installé sous Windows, mais il l'est dans WSL, et `check-front.ps1` l'utilise à
   chaque validation depuis le 28/09 — c'est l'hypothèse que D06 prenait pour fausse.
3. **Le filet est plus serré qu'avant.** `check-front` ne se contente plus de parser : il parcourt le graphe des
   **24 modules** depuis l'entrée, vérifie que chacun se parse *en tant que module*, que chaque `import` trouve son
   `export`, et que nul ne se sert d'un nom sans l'importer. Cette dernière règle a trouvé **sept ruptures réelles**
   dans le découpage lui-même — des appels écrits dans des gabarits de chaîne, que l'outil de découpe avait lus
   comme du texte.

## Ce qui reste à la charge de l'œil

Ce que ni Node ni le graphe ne voient : l'écran. Un découpage ne change pas ce qui s'affiche, et **cela se
constate en chargeant la page servie**, une fois, sur `http://127.0.0.1:47600`. C'est le seul geste de validation
qui reste manuel, et il n'a jamais été autre chose.
