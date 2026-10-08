# @author Florent HAZARD <f.hazard@sowapps.com>
@{
    # ---------------------------------------------------------------------------
    # A TEMPLATE for the LOCAL configuration. Copy this file as 'config.local.psd1' (same folder) and adapt it: it
    # is ignored by git and never leaves your machine.
    #
    # Intent: hold what cannot be generic -- that is, what depends on the machine. Any key present here overrides
    # the one in config.psd1; any key absent keeps config.psd1's value.
    #
    # NEVER put a secret here: the API token lives in var/secrets/.



    # ---------------------------------------------------------------------------

    # A folder of external administration scripts. OPTIONAL.
    # Locking Windows Update and auditing it are native: they work WITHOUT this key. It now serves only the VBS /
    # HVCI switches and the action that opens the folder, which use the PARENT folder as the administration root.
    # If the folder holds update-mode.ps1, that script is still preferred for the lock.
    # ToolsPath = 'C:\chemin\vers\LocalAgentAdmin\tools'

    # Uncomment this only if the default port is already taken on this machine.
    # Port = 47601

    # The history of the measurements: an OPTIONAL override of config.psd1's History section.
    # BEWARE: a top-level key replaces the WHOLE table -- if you lay History down here, the sub-keys that are
    # absent fall back on the internal defaults (enabled, 90 days, 50 000 lines, an empty Measures), NOT on
    # config.psd1's values. So copy everything you want to keep.

    # History = @{
    #     Enabled            = $true       # $false = plus aucune ecriture (fichiers conserves)
    #     RetentionDays      = 180
    #     MaxLinesPerMeasure = 50000
    #     Measures = @{
    #         'disk.free'   = @{ RetentionDays = 365 }
    #         # IntervalMinutes overrides the catalogue's minimum interval;
    #         # RetentionDays = 0 stops sampling that measurement.
    #         'net.latency' = @{ RetentionDays = 30 }
    #     }
    # }
}
