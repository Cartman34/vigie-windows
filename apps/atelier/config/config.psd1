# @author Florent HAZARD <f.hazard@sowapps.com>
@{
    # ---------------------------------------------------------------------------
    # Intent: configure the ATELIER app (a development tool).
    #
    # The Atelier is a SEPARATE app, distinct from Vigie: so it has ITS OWN config, and does not read the server
    # app's. Every value has one single definition, but each app is master of its own.
    #
    # Usage: never confuse this with apps/backend-pode/config/config.psd1, which configures the delivered
    # application (port 47600, elevated).
    # ---------------------------------------------------------------------------

    # BindAddress comes from config/common.psd1 (at the root): it is shared by every app of the repository and so
    # is not copied here (D15/D33).

    # The port of the Atelier's server. The same local range as Vigie (47600-47699), a DISTINCT port so that both
    # apps can run at the same time without getting in each other's way.
    Port        = 47610

    # The page opened at startup, relative to the root of the repository (which is what is served).
    StartPage   = '/apps/atelier/index.html'
}
