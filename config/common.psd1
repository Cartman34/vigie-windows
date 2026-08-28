@{
    # ---------------------------------------------------------------------------
    # Configuration COMMUNE a plusieurs apps du depot.
    #
    # N'y mettre QUE ce qui est reellement partage. Tout ce qui est propre a une app
    # vit dans apps/<app>/config/config.psd1 (D33).
    #
    # Chaque app fusionne : ce fichier, PUIS sa config, PUIS sa config locale.
    # La plus specifique gagne.
    # ---------------------------------------------------------------------------

    # Adresse d'ecoute de TOUS les serveurs locaux du projet (Vigie et Atelier).
    # STRICTEMENT locale : aucune app de ce depot ne doit jamais etre exposee.
    # Etait recopiee dans les deux configs : une valeur, une definition (D15).
    BindAddress = '127.0.0.1'

    # Plage de ports reservee au projet. Chaque app choisit LE SIEN dans cette plage,
    # dans sa propre config : Vigie 47600, Atelier 47610.
    PortRangeStart = 47600
    PortRangeEnd   = 47699
}
