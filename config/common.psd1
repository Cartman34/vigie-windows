# @author Florent HAZARD <f.hazard@sowapps.com>
@{
    # ---------------------------------------------------------------------------
    # The configuration SHARED by several apps of the repository.
    #
    # Intent: hold ONLY what is really shared. Anything specific to one app lives in
    # apps/<app>/config/config.psd1 (D33).
    #
    # Usage: each app merges this file, THEN its own config, THEN its local config. The most specific wins.
    # ---------------------------------------------------------------------------

    # The listening address of ALL the project's local servers (Vigie and the Atelier).
    # STRICTLY local: no app of this repository must ever be exposed.
    # It used to be copied into both configs: one value, one definition (D15).
    BindAddress = '127.0.0.1'

    # The range of ports reserved to the project. Each app picks ITS OWN inside that range, in its own config:
    # Vigie 47600, the Atelier 47610.
    PortRangeStart = 47600
    PortRangeEnd   = 47699

    # The public repository: where the updates come from, and what an ordinary machine compares itself with in
    # order to know whether it is up to date. The address used to be written in vigie-fetch AND in the card's
    # computation: one value, one definition (D15).
    Repository    = 'Cartman34/vigie-windows'
    RepositoryUrl = 'https://github.com/Cartman34/vigie-windows.git'
}
