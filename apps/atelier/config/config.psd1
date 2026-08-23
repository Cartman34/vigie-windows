@{
    # ---------------------------------------------------------------------------
    # Configuration de l'app ATELIER (outil de developpement).
    #
    # L'Atelier est une app A PART, distincte de Vigie : il a donc SA config, et
    # ne lit pas celle du backend. Chaque valeur n'a qu'une seule definition, mais
    # chaque app est maitresse des siennes.
    #
    # Ne jamais confondre avec apps/backend-pode/config/config.psd1, qui configure
    # l'application livree (port 47600, elevee).
    # ---------------------------------------------------------------------------

    # BindAddress vient de config/common.psd1 (racine) : elle est partagee par toutes
    # les apps du depot et n'est donc pas recopiee ici (D15/D33).

    # Port du serveur de l'Atelier. Meme plage locale que Vigie (47600-47699),
    # port DISTINCT pour que les deux apps tournent en meme temps sans se gener.
    Port        = 47610

    # Page ouverte au demarrage, relative a la racine du depot (qui est servie).
    StartPage   = '/apps/atelier/index.html'
}
