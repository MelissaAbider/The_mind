#!/bin/bash

# Fichier pour stocker les classements
FICHIER_CLASSEMENT="classement.txt"

# Fonction pour mettre à jour le classement après chaque manche réussie
function mettreAJourClassement() {
    NOM_JOUEUR=$1   # Nom du joueur ou ID du robot 
    SCORE_JOUEUR=$2  # Score actuel (nombre de manches réussies)

    if [ ! -f "$FICHIER_CLASSEMENT" ]; then
        touch "$FICHIER_CLASSEMENT"
    fi

    # Ajout ou mise à jour du score dans le fichier classement.txt
    if grep -q "^$NOM_JOUEUR" "$FICHIER_CLASSEMENT"; then
        sed -i "/^$NOM_JOUEUR/c\\$NOM_JOUEUR $SCORE_JOUEUR" "$FICHIER_CLASSEMENT"
    else
        echo "$NOM_JOUEUR $SCORE_JOUEUR" >> "$FICHIER_CLASSEMENT"
    fi
}

# Fonction pour afficher le top 10 à la fin du jeu
function afficherTop10() {
    echo "Classement final :"
    cat classement.txt
    # Trier les scores par ordre décroissant et afficher les 10 meilleurs scores dans top10.txt
    sort -k2 -nr "$FICHIER_CLASSEMENT" | head -n 10 > top10.txt
    
    echo "Top 10 des joueurs :"
    cat top10.txt
}

