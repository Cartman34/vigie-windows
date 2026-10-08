# @author Florent HAZARD <f.hazard@sowapps.com>
@{
    # The MODULE's declaration (D48): the health of VIGIE ITSELF. Intent: say what it computes and what it may notify.
    Label       = 'Débogage'
    Description = 'L''état de Vigie elle-même : tâches de démarrage, dépendances, journaux.'

    # IT IS BORN SWITCHED OFF (D85). It is a DEBUGGING module: it speaks only to whoever is developing or
    # troubleshooting, and has no business on the everyday panel. The user switches it on in Settings > Modules
    # when they need it; their choice is kept.
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
        @{ Key = 'watch-stalled'; Label = 'Une tâche de veille est bloquée'
           Card = 'vigie-self'; Field = 'watch'
           Droits = 'tous'; Critique = $false
           Help = 'Un des travaux que Vigie lance d''elle-même toutes les trente secondes dépasse son plafond : les cartes qu''il alimente ne se mettent plus à jour.' }
        @{ Key = 'vigie-runaway'; Label = 'Vigie s''emballe'
           Card = 'vigie-self'; Field = 'count'
           Droits = 'tous'; Critique = $false
           Help = 'Vigie a lancé plus de processus que le seuil, ou un résident tourne hors de l''app serveur. La bulle dit lesquels.' }
        @{ Key = 'vigie-memory'; Label = 'Vigie occupe trop de mémoire'
           Card = 'vigie-self'; Field = 'memory'
           Droits = 'tous'; Critique = $false
           Help = 'Les processus de Vigie réunis dépassent le seuil de mémoire. La bulle nomme les plus lourds.' }
    )

    # SCHEDULED COMPUTATIONS (D124/D125): the server computes this card by itself, so that nothing is ever computed
    # while someone waits. The interval follows what one pass costs, measured, not what one would wish.
    Refresh = @(
        @{ Key = 'self'; Probe = 'self.probe.ps1'; Cards = @('vigie-self')
           Seconds = @{ default = 120; game = 120 }; MaxSeconds = 60 }
        @{ Key = 'vigie'; Probe = 'vigie.probe.ps1'; Cards = @('vigie-debug')
           Seconds = @{ default = 300 }; MaxSeconds = 60 }
    )
}
