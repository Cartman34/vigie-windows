# @author Florent HAZARD <f.hazard@sowapps.com>
@{
    # ---------------------------------------------------------------------------
    # Intent: hold the VERSIONED configuration -- generic, valid on any machine. Every value is defined HERE ONLY;
    # all the rest derives from it (Get-AppUrl, Get-ApiUrl, Get-ToolsPath in lib/common.ps1). Never copy one of
    # these values anywhere else in the code.
    #
    # Usage: for anything specific to YOUR machine, do not modify this file: create
    # apps/backend-pode/config/config.local.psd1 (ignored by git) from config.local.sample.psd1.
    # ---------------------------------------------------------------------------

    # BindAddress comes from config/common.psd1 (at the root): shared by every app, it is not copied here
    # (D15/D33). It listens STRICTLY locally.

    # The listening port. One fixed port per project, inside the local range 47600-47699.
    Port        = 47600

    # The prefix of the REST API's routes (see apps/backend-pode/api/openapi.yaml).
    ApiBase     = '/api/v1'

    # WHICH STAGE runs on this machine.
    #
    #   'prod' : Vigie runs from the shared installation. That is the default: a machine is in production until
    #            somebody says otherwise.
    #   'dev'  : Vigie is deployed from the repository. A development workstation.
    #
    # This setting DECLARES an intention; Vigie then compares it with what is really running and reports the gap.
    # To be laid down in config.local.psd1: it is a choice of machine, like UpdateSource.
    #
    # STAGE (dev | prod): DELIBERATELY ABSENT HERE.
    #
    # The default lives in the code (Get-DeclaredStage returns prod when nothing is said). Laying it down here
    # would make it a DECLARED value, which would mask the one of a more specific layer: that happened on 30/08,
    # a prod stage delivered here winning over the machine's own dev declaration, and the installation announcing
    # Production on a development workstation.
    #
    # To be laid down in config.local.psd1, or in machine.psd1 for the whole computer.
    # The old name Environment is still read.



    # WHERE VIGIE UPDATES ITSELF FROM when the update button is pressed.
    #
    #   'auto'    : the repository is there -> we deploy that repository (a development workstation); otherwise ->
    #               we download the latest published version. That is the default, and it does what one expects in
    #               both cases.
    #   'local'   : ALWAYS the local repository, even if a published version is more recent.
    #   'release' : ALWAYS the latest published version, even on a development workstation -- useful on a dev
    #               server that must behave like a user's machine.
    #   'clone'   : a separate clone, on the reference given by UpdateRef.
    #
    # To be laid down in config.local.psd1: it is a choice of MACHINE, not of the product.
    UpdateSource = 'auto'

    # The branch, tag or commit to deploy when UpdateSource is 'clone'. Empty = the last tag, never a branch:
    # following a branch would amount to installing work in progress (D99).
    UpdateRef    = ''

    # WHERE THE SERVICE'S CLONE SYNCHRONISES FROM (D112). Empty = the public repository (RepositoryUrl). On a
    # development workstation one puts the path of the local repository here: the service then builds what has just
    # been written, without our having to push it -- and without ever working INSIDE the repository, which belongs
    # to a person.
    UpdateRemote = ''

    # OPTIONAL external tooling (administration scripts living outside the repository).
    # Locking Windows Update and auditing it are NATIVE since lib/common.ps1 (Set-UpdateLock, Invoke-UpdateAudit):
    # they no longer need this path. If it is filled in AND holds update-mode.ps1, that script is still preferred
    # -- the historical installations keep their behaviour.
    # Still dependent on this path: the VBS / HVCI switches, and the action that opens the folder.
    # Empty = not configured: those actions then return a clear message instead of failing.
    # An absolute path is specific to a machine: fill it in inside config.local.psd1.
    ToolsPath   = ''

    # --- The history of the measurements ---------------------------------------
    # Series sampled as the probes pass, stored in var/history/ (one JSONL file per measurement). Resolved in
    # layers by Get-HistoryConfig (lib/common.ps1): these global values, then the per-measurement setting below.
    # How long the logs are kept, in days: logs, diagnostic copies and .reg backups (Invoke-LogPurge). 30 days,
    # arbitrated by the owner on 13/09.
    LogRetentionDays = 30
    # A CEILING IN MEGABYTES for everything under var/log, per account: an age bounds nothing by itself, since a
    # busy day writes ten times what a quiet one writes (166 MB measured on 29/09 for thirty days). Past this, the
    # oldest files go, except anything written in the last hour. 0 = no ceiling.
    LogMaxMb = 60

    # --- SCHEDULER (D124): what the server app computes on its own ------------------------------
    # Each module declares its computations and their intervals in its own module.psd1; these
    # values bound the whole.
    Refresh = @{
        # Computations running at once. 0 = no limit. Three by default (owner, 29/09).
        MaxParallel           = 3
        # THE HARD CEILING on everything Vigie starts in the background, scheduler or not. Past this, a launch is
        # REFUSED and logged. It exists because nothing counted on 29/09: 150 processes, and a machine on its knees.
        MaxChildren           = 8
        # Past this, a computation is called TOO LONG: logged, shown on the self-watch card, and it
        # stops holding a place. It is never stopped.
        DefaultMaxSeconds     = 300
        # After a failure, how long before trying again. It DOUBLES at each failure, up to the cap:
        # a broken computation can no longer take the place of the others by being the oldest.
        FailBackoffSeconds    = 60
        FailBackoffMaxSeconds = 3600
    }

    History = @{
        # The master switch. Disabled = no writing at all any more (the files stay).
        Enabled            = $true
        # The DEFAULT retention, in days. It applies to any measurement without a setting of its own.
        RetentionDays      = 90
        # A size guard per measurement file (in lines), on top of the age.
        MaxLinesPerMeasure = 50000
        # PER-MEASUREMENT settings: the key is the catalogue's identifier ($script:MeasureCatalog in
        # lib/common.ps1). Any absent key inherits from the global. IntervalMinutes overrides the catalogue's
        # minimum interval.
        # RetentionDays = 0: stop sampling that measurement (the existing file is not deleted: destroying an
        # archive stays a manual gesture).
        Measures = @{
            'disk.free'   = @{ RetentionDays = 365 }
            'net.latency' = @{ RetentionDays = 30 }
        }
    }
}
