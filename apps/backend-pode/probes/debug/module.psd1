# @author Florent HAZARD <f.hazard@sowapps.com>
@{
    # Declaration du MODULE (D48) : la sante de VIGIE ELLE-MEME.
    Label       = 'Débogage'
    Description = 'L''état de Vigie elle-même : tâches de démarrage, dépendances, journaux.'

    # NAIT ETEINT (D85). C'est un module de DEBOGAGE : il ne parle qu'a qui developpe ou
    # depanne, et n'a rien a faire sur le tableau de bord de tous les jours. L'utilisateur
    # l'allume dans Parametres > Modules quand il en a besoin ; son choix est garde.
    DefautActif = $false

    # THE SELF-WATCH THRESHOLDS (CORE-SELFWATCH): what Vigie may occupy before its own card alerts. On 17/09, 115 copies
    # of a resident held 19 GB; in normal use the server app and its children are four processes and under 500 MB.
    Config = @{
        SelfMaxProcesses = 20
        SelfMaxMemoryMb  = 2048
    }
    Parameters = @(
        @{ Key = 'SelfMaxProcesses'; Label = 'Processus de Vigie au plus'; Type = 'int'; Unit = 'processus'; Min = 5; Max = 200; Step = 5
           Help = 'Au-delà de ce nombre de processus lancés par Vigie, la carte « Processus de Vigie » alerte.' }
        @{ Key = 'SelfMaxMemoryMb'; Label = 'Mémoire de Vigie au plus'; Type = 'int'; Unit = 'Mo'; Min = 256; Max = 16384; Step = 256
           Help = 'Au-delà de cette mémoire occupée par tous les processus de Vigie réunis, la carte « Processus de Vigie » alerte.' }
    )

    # THE ONLY NOTIFICATIONS OF THIS MODULE watch Vigie running away; the other lines describe, they do not alert.
    Notifications = @(
        @{ Key = 'vigie-runaway'; Label = 'Vigie s''emballe'
           Card = 'vigie-self'; Field = 'count'
           Droits = 'tous'; Critique = $false
           Help = 'Vigie a lancé plus de processus que le seuil, ou un résident tourne hors de l''app serveur. La bulle dit lesquels.' }
        @{ Key = 'vigie-memory'; Label = 'Vigie occupe trop de mémoire'
           Card = 'vigie-self'; Field = 'memory'
           Droits = 'tous'; Critique = $false
           Help = 'Les processus de Vigie réunis dépassent le seuil de mémoire. La bulle nomme les plus lourds.' }
    )
}
