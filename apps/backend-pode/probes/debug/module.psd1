# @author Florent HAZARD <f.hazard@sowapps.com>
@{
    # Declaration du MODULE (D48) : la sante de VIGIE ELLE-MEME.
    Label       = 'Débogage'
    Description = 'L''état de Vigie elle-même : tâches de démarrage, dépendances, journaux.'

    # NAIT ETEINT (D85). C'est un module de DEBOGAGE : il ne parle qu'a qui developpe ou
    # depanne, et n'a rien a faire sur le tableau de bord de tous les jours. L'utilisateur
    # l'allume dans Parametres > Modules quand il en a besoin ; son choix est garde.
    DefautActif = $false

    # Ce module DECRIT ; il ne surveille rien en continu. Ses lignes disent l'etat de
    # l'application, elles ne se degradent pas toutes seules.
    Notifications = @()
}
