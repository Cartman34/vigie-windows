# La porte laissée ouverte pour une mise à jour signée — vérifiée au lieu d'être supposée

**S01** (`CORE-UPDATE-TRUST`) a été arbitré le 05/09 : la vérification de ce qui s'installe viendra dans une version
future. D'ici là, **une seule obligation pèse sur le code d'aujourd'hui** — rester installable par elle. Une archive
qui porterait en plus une empreinte ou une signature doit s'installer sans que rien ne s'en étrangle.

## Pourquoi le revérifier le 07/10

Parce que quelque chose a changé entre-temps, et que personne ne l'avait rapproché de S01 : le **06/10**,
`Copy-InstallFrom` s'est mis à **supprimer tout ce que la source ne porte pas**, à n'importe quelle profondeur
(sujet S18 — une action retirée de la source survivait, installée et appelable). Une suppression récursive dans une
installation où l'on veut justement pouvoir déposer des fichiers nouveaux, c'est exactement ce qui referme une porte
sans qu'on s'en aperçoive.

## Ce qui a été mesuré

Sur des dossiers jetables, jamais sur l'installation réelle. Une source minimale mais complète au sens de
`Test-InstallCopy`, à laquelle on ajoute ce que la chaîne de demain apporterait : une empreinte à la racine, une
signature à la racine, et une signature par fichier dans un sous-dossier qu'aucun code d'aujourd'hui ne connaît.

| Ce qui est éprouvé | Résultat |
|---|---|
| `vigie.sha256` apporté par la source | **présent** après installation |
| `vigie.sig` apporté par la source | **présent** après installation |
| `signatures/apps.sig`, dans un sous-dossier inconnu | **présent** après installation |
| `Test-InstallCopy` face à une installation qui porte ces trois-là | **accepte** |
| Un fichier inconnu **déjà posé** et que la source n'apporte pas | **supprimé** |

## Ce qu'il faut en conclure, et la nuance qui compte

**La porte est ouverte** : l'installation exige des fichiers *présents*, elle ne refuse jamais un fichier qu'elle ne
connaît pas, et elle le transporte même quand il vit dans un dossier dont elle ignore tout.

**La dernière ligne n'est pas une fermeture, c'en est l'inverse.** Un fichier que la source n'apporte pas disparaît,
parce que **la source fait foi** — c'est la règle de S18, et c'est elle qui empêche une pièce retirée de survivre,
installée et appelable, avec ses droits. Une signature ne sera jamais dans ce cas : elle voyage **dans** l'archive,
donc elle est dans la source, donc elle est posée et gardée. Les deux règles ne se contredisent pas ; elles
répondent à deux questions différentes.

Ce qui reste de S01 est entier et inchangé : empreinte publiée, signature, protection de branche et d'étiquettes,
second facteur, retour arrière. Une version future, décidée comme telle. Et il est acquis que les versions
actuelles, non signées, ne seront pas des cibles de mise à jour valides le jour où la vérification existera.
