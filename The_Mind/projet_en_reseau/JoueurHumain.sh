#!/bin/bash

ID_JOUEUR=$1
MODE_RESEAU=${2:-false}
CARTES_COURANTES=() # Contient les cartes du joueur
declare -i NB_CARTES=0 # On déclare un integer. Il décrit le nombre de cartes en main

#Sauvegarder les cartes courantes du joueur dans un fichier temporaire
function definirCartes() {
    # Parcourir toutes les cartes dans le tableau 
    for carte in "${CARTES_COURANTES[@]}"; do
        # Ajouter chaque carte au fichier temporaire
        echo "$carte"
    done > "${ID_JOUEUR}_CARTES_COURANTES.tmp"
    # Mettre à jour NB_CARTES pour refléter le nombre de cartes restantes dans CARTES_COURANTES
    NB_CARTES=${#CARTES_COURANTES[@]}
}

#Charger les cartes courantes du joueur depuis son fichier temporaire
function obtenirCartes() {
    # Initialise le tableau CARTES_COURANTES pour stocker les cartes du joueur courant
    CARTES_COURANTES=()
    # Lire chaque ligne du fichier temporaire associé au joueur et l'ajoute au tableau
    while IFS= read -r carte; do
        CARTES_COURANTES+=("$carte")
    done < "${ID_JOUEUR}_CARTES_COURANTES.tmp"
    # Mettre à jour le compteur NB_CARTES pour refléter le nombre de cartes courantes
    NB_CARTES=${#CARTES_COURANTES[@]}
}

#Fonction pour lire entrée utilisateur
function commandeQuitter() {
    read -p "Entrez votre carte (ou 'q' pour quitter) : " CARTE_A_JOUER
    if [[ "$CARTE_A_JOUER" == "q" || "$CARTE_A_JOUER" == "QUIT" ]]; then
        echo "[INFO] | Le joueur $ID_JOUEUR a demandé à quitter la partie."
        if [ "$MODE_RESEAU" = true ]; then
            echo "QUIT" > gestionJeu.pipe
        else
            echo "QUIT" > gestionJeu.pipe
        fi
        exit
    fi
}

#Fonction pour valider si la carte jouée est correcte
function validerCarte() {
    CARTE_INVALIDE=true
    obtenirCartes  # Récupère les cartes courantes du joueur

    # Vérifie si l'entrée est un nombre entier
    if [[ $CARTE_A_JOUER =~ ^-?[0-9]+$ ]]; then
        for (( x=0; x<$NB_CARTES; x++ )); do
            CARTE_COURANTE=${CARTES_COURANTES[x]}
            if [ "$CARTE_A_JOUER" -eq "$CARTE_COURANTE" ]; then
                CARTE_INVALIDE=false  # La carte est présente dans sa main
                break
            fi
        done

        # Si la carte n'est pas valide, affiche un message d'erreur
        if [ "$CARTE_INVALIDE" = true ]; then
            echo "Impossible de jouer cette carte, vos cartes sont : ${CARTES_COURANTES[@]}"
        fi
    else
        echo "Entrée invalide. Veuillez entrer un nombre correspondant à une carte."
    fi
}

#Fonction pour supprimer la carte jouée de la main du joueur
function supprimerCarteJouee() {
    NOUVELLES_CARTES=()
    for (( x=0; x<$NB_CARTES; x++ )); do
        CARTE_COURANTE=${CARTES_COURANTES[x]}
        if [ "$CARTE_A_JOUER" -ne "$CARTE_COURANTE" ]; then
            NOUVELLES_CARTES+=("$CARTE_COURANTE")
        fi
    done

    CARTES_COURANTES=("${NOUVELLES_CARTES[@]}")  # Met à jour les cartes restantes
    NB_CARTES=${#CARTES_COURANTES[@]}  # Met à jour le nombre de cartes restantes

    definirCartes  # Sauvegarde les cartes restantes dans le fichier temporaire
}

# Fonction pour envoyer la carte jouée au gestionnaire via le tube
function envoyerCarteJouee() {
    if [ "$MODE_RESEAU" = true ]; then
        echo "$CARTE_A_JOUER" > gestionJeu.pipe
    else
        echo "$CARTE_A_JOUER" > gestionJeu.pipe
    fi
    echo "Carte $CARTE_A_JOUER jouée"
}

#Fonction pour afficher les cartes restantes après avoir joué une carte
function afficherCartesRestantes() {
    if [ "$NB_CARTES" -eq 0 ]; then
        echo "Vous n'avez plus de cartes"
    elif [ "$NB_CARTES" -eq 1 ]; then
        echo "Il vous reste une carte : ${CARTES_COURANTES[@]}"
    else
        echo "Vos cartes sont : ${CARTES_COURANTES[@]}"
    fi
}

#Fonction principale orchestrant les sous-fonctions pour jouer une carte
function ecouterCarteAJouer() {
    while true; do
        CARTE_INVALIDE=true

        while $CARTE_INVALIDE; do
            commandeQuitter  # Demande à l'utilisateur d'entrer une carte
            validerCarte  # Valide si la carte est correcte ou non
        done
        
        supprimerCarteJouee  # Supprime la carte jouée de la main du joueur
        envoyerCarteJouee  # Envoie la carte au gestionnaire
        afficherCartesRestantes  # Affiche les cartes restantes après avoir joué une carte
    done
}

# Gérer les messages reçus du serveur/gestionnaire
function traiterMessage() {
    local ID_MSG=$1
    local CONTENU_MSG=$2

    echo "[DEBUG] Traitement du message : type=$ID_MSG contenu='$CONTENU_MSG'"

    case $ID_MSG in
        "1") # Une carte de la manche courante a été trouvée
            echo "$CONTENU_MSG"
            ;;
        "2") # Une mauvaise carte a été trouvée, la manche recommence
            echo "$CONTENU_MSG"
            CARTES_COURANTES=()
            ;;
        "3") # La manche est terminée, on passe à la suivante
            echo "$CONTENU_MSG"
            CARTES_COURANTES=()
            ;;
        "4") # La partie est terminée
            echo "$CONTENU_MSG"
            exit
            ;;
        "5") # Toutes les cartes ont été reçues
            obtenirCartes
            echo "Démarrage du jeu avec les cartes : ${CARTES_COURANTES[@]}"
            ecouterCarteAJouer &
            ;;
        "6") # Réception des cartes
            echo "[DEBUG] Réception des cartes : $CONTENU_MSG"
            # Transformer la chaîne de cartes en tableau
            CARTES_COURANTES=($CONTENU_MSG)
            # Sauvegarder dans le fichier temporaire
            echo "[DEBUG] Sauvegarde des cartes dans ${ID_JOUEUR}_CARTES_COURANTES.tmp"
            definirCartes
            echo "Cartes reçues ! Vos cartes : ${CARTES_COURANTES[@]}"
            ;;
    esac
}

# Fonction principale d'écoute des messages
function ecouterPipe() {
    if [ "$MODE_RESEAU" = true ]; then
        while IFS= read -r ligne; do
            APPEL_API=${ligne%%;*}
            CONTENU_MSG=${ligne#*;}
            traiterMessage "$APPEL_API" "$CONTENU_MSG"
        done < "$ID_JOUEUR.pipe"
    else
        while true; do
            read ligne < "$ID_JOUEUR.pipe"
            APPEL_API=${ligne%%;*}
            CONTENU_MSG=${ligne#*;}
            traiterMessage "$APPEL_API" "$CONTENU_MSG"
        done
    fi
}

# Nettoyage à la sortie
function nettoyage() {
    rm -f "${ID_JOUEUR}_CARTES_COURANTES.tmp"
    rm -f "${ID_JOUEUR}.pipe"
    exit 0
}

trap nettoyage EXIT

echo "Vous êtes le joueur n°$ID_JOUEUR"
if [ "$MODE_RESEAU" = true ]; then
    echo "Mode réseau activé"
fi
echo "En attente de vos cartes ..."

ecouterPipe