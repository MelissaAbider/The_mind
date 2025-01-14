#!/bin/bash

ID_JOUEUR=$1
CARTES_COURANTES=() # Contient les cartes du joueur
declare -i NB_CARTES=0 # On déclare un integer. Il décrit le nombre de carte en main

#Sauvegarder les cartes actuelles du joueur dans un fichier temporaire
function definirCartes() {
  # Parcourir toutes les cartes dans le tableau 
  for carte in "${CARTES_COURANTES[@]}"; do
    # Ajouter chaque carte au fichier temporaire
    echo "$carte"
  done > "${ID_JOUEUR}_CURRENT_CARDS.tmp"
  # Mettre à jour NB_CARTES pour refléter le nombre de cartes restantes dans CARTES_COURANTES
  NB_CARTES=${#CARTES_COURANTES[@]}
}

#Charger les cartes actuelles du joueur depuis son fichier temporaire
function obtenirCartes() {
  # Initialise le tableau CARTES_COURANTES pour stocker les cartes du joueur courant
  CARTES_COURANTES=()
  # Lire chaque ligne du fichier temporaire associé au joueur et l'ajoute au tableau
  while IFS= read -r carte; do
    CARTES_COURANTES+=("$carte")
  done < "${ID_JOUEUR}_CURRENT_CARDS.tmp"
  # Mettre à jour le compteur NB_CARTES pour refléter le nombre de cartes actuelles
  NB_CARTES=${#CARTES_COURANTES[@]}
}

#Fonction pour lire entrée utilisateur
function commandeQuitter() {
    read CARTE_A_JOUER
    if [[ "$CARTE_A_JOUER" == "q" || "$CARTE_A_JOUER" == "QUIT" ]]; then
        echo "[INFO] | Le joueur $ID_JOUEUR a demandé à quitter la partie."
        echo "QUIT" > gestionJeu.pipe
        exit
    fi
}

#Fonction pour valider si la carte jouée est correcte
function validerCarte() {
    IMPOSSIBLE_JOUER_CARTE=true
    obtenirCartes  # Récupère les cartes actuelles du joueur

    # Vérifie si l'entrée est un nombre entier
    if [[ $CARTE_A_JOUER =~ ^-?[0-9]+$ ]]; then
        for (( x=0; x<$NB_CARTES; x++ )); do
            CARTE_COURANTE=${CARTES_COURANTES[x]}
            if [ "$CARTE_A_JOUER" -eq "$CARTE_COURANTE" ]; then
                IMPOSSIBLE_JOUER_CARTE=false  # La carte est présente dans sa main
                break
            fi
        done

        # Si la carte n'est pas valide, affiche un message d'erreur
        if [ "$IMPOSSIBLE_JOUER_CARTE" = true ]; then
            echo "Impossible de jouer cette carte, vos cartes sont : ${CARTES_COURANTES[@]}"
        fi
    else
        echo "Entrée invalide. Veuillez entrer un nombre correspondant à une carte."
    fi
}

#Fonction pour supprimer la carte jouée de la main du joueur
function supprimerCarteJouee() {
    NOUVELLES_CARTES_COURANTES=()
    for (( x=0; x<$NB_CARTES; x++ )); do
        CARTE_COURANTE=${CARTES_COURANTES[x]}
        if [ "$CARTE_A_JOUER" -ne "$CARTE_COURANTE" ]; then
            NOUVELLES_CARTES_COURANTES+=("$CARTE_COURANTE")
        fi
    done

    CARTES_COURANTES=("${NOUVELLES_CARTES_COURANTES[@]}")  # Met à jour les cartes restantes
    NB_CARTES=${#CARTES_COURANTES[@]}  # Met à jour le nombre de cartes restantes

    definirCartes  # Sauvegarde les cartes restantes dans le fichier temporaire
}

# Fonction pour envoyer la carte jouée au gestionnaire via le pipe
function envoyerCarteJouee() {
    echo $CARTE_A_JOUER > gestionJeu.pipe  # Envoie la carte au gestionnaire via le pipe 'gestionJeu.pipe'
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

#Fonction principale orchestrant les sous-fonctions ci-dessus
function ecouterCarteAJouer() {
    while true; do
        IMPOSSIBLE_JOUER_CARTE=true

        while $IMPOSSIBLE_JOUER_CARTE; do  # Tant que l'entrée utilisateur est mauvaise, on répète
            commandeQuitter  # Demande à l'utilisateur d'entrer une carte
            validerCarte  # Valide si la carte est correcte ou non 
        done
        supprimerCarteJouee  # Supprime la carte jouée de la main du joueur
        envoyerCarteJouee  # Envoie la carte au gestionnaire
        afficherCartesRestantes  # Affiche les cartes restantes après avoir joué une carte
    done
}

function ecouterPipe(){
  # On récupère les données qui arrivent au travers du pipe
  DONNEES_ENTRANTES=$(cat $ID_JOUEUR.pipe)

  # On récupère l'id et le message de l'action
  APPEL_API=${DONNEES_ENTRANTES:0:1}
  MESSAGE_API=${DONNEES_ENTRANTES:2}

  # On traite l'action
  if [ $(($APPEL_API)) -eq $((5)) ];then 
    # Toutes les cartes ont été reçues
    obtenirCartes
    echo "Cartes reçues ! Vos cartes : "${CARTES_COURANTES[@]}
    ecouterCarteAJouer &
  elif [ $(($APPEL_API)) -eq $((1)) ];then 
    # Une carte du tour courant a été trouvée
    echo $MESSAGE_API
  elif [ $(($APPEL_API)) -eq $((2)) ];then 
    # Une mauvaise carte a été trouvée, le tour recommence
    echo $MESSAGE_API
  elif [ $(($APPEL_API)) -eq $((3)) ];then 
    # Le tour est terminé, on passe au tour suivant
    echo $MESSAGE_API
  elif [ $(($APPEL_API)) -eq $((4)) ];then 
    # Le jeu est terminé
    echo $MESSAGE_API
    read tmp
    exit
  fi

  ecouterPipe
}

echo "Vous êtes le joueur n°"$ID_JOUEUR
echo "En attente de vos cartes ..."
ecouterPipe