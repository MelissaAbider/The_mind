#!/bin/bash

# Fichier pour stocker les classements
CLASSEMENT_FILE="classement.txt"

# Fonction pour mettre à jour le classement après chaque manche réussie
function updateClassement() {
    PLAYER_NAME=$1   # Nom du joueur ou ID du robot (on peut utiliser l'ID comme nom)
    PLAYER_SCORE=$2  # Score actuel (nombre de manches réussies)

    if [ ! -f "$CLASSEMENT_FILE" ]; then
        touch "$CLASSEMENT_FILE"
    fi

    # Ajout ou mise à jour du score dans le fichier classement.txt
    if grep -q "^$PLAYER_NAME" "$CLASSEMENT_FILE"; then
        sed -i "/^$PLAYER_NAME/c\\$PLAYER_NAME $PLAYER_SCORE" "$CLASSEMENT_FILE"
    else
        echo "$PLAYER_NAME $PLAYER_SCORE" >> "$CLASSEMENT_FILE"
    fi
}

# Fonction pour afficher le top 10 à la fin du jeu
function displayTop10() {
    echo "Classement final :"
    cat classement.txt
    # Trier les scores par ordre décroissant et afficher les 10 meilleurs scores dans top10.txt
    sort -k2 -nr "$CLASSEMENT_FILE" | head -n 10 > top10.txt
    
    echo "Top 10 des joueurs :"
    cat top10.txt
}

