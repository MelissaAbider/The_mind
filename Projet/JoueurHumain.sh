#!/bin/bash

PLAYER_ID=$1
CURRENT_CARDS=() # Contient les cartes du joueur
declare -i NB_CARDS=0 # On déclare un integer. Il décrit le nombre de carte en main

function setCards(){
  # On enregistre les cartes du joueur courant dans son fichier tmp associé
  for CURRENT_VALUE in "${CURRENT_CARDS[@]}";do
    echo $CURRENT_VALUE
  done > $PLAYER_ID"_CURRENT_CARDS.tmp"
  NB_CARDS=${#CURRENT_CARDS[@]}
}

function getCards(){
  # On récupère les cartes du joueur courant dans son fichier tmp associé
  CURRENT_CARDS=()
  while read CURRENT_CARD; do 
    CURRENT_CARDS+=("$CURRENT_CARD")
  done < $PLAYER_ID"_CURRENT_CARDS.tmp"
  NB_CARDS=${#CURRENT_CARDS[@]}
}

function ListenCardToPlay() {
    while true; do
        CANT_PLAY_THIS_CARD=true  # On initialise un booléen pour savoir si l'entrée utilisateur est bonne

        while $CANT_PLAY_THIS_CARD; do  # Tant que l'entrée utilisateur est mauvaise, on répète
            read CARD_TOPLAY  # On demande au joueur d'entrer la carte qu'il souhaite jouer
	if [[ "$CARD_TOPLAY" == "q" || "$CARD_TOPLAY" == "QUIT" ]]; then
                echo "[INFO] | Le joueur $PLAYER_ID a demandé à quitter la partie."
                echo "QUIT" > gestionJeu.pipe # Envoie un signal d'arrêt au gestionnaire via le pipe
                exit # Quitte le terminal du joueur
            fi

            getCards # Récupère les cartes actuelles du joueur

            # Vérification que l'entrée est bien un chiffre
            if [[ $CARD_TOPLAY =~ ^-?[0-9]+$ ]]; then
                for (( x=0; x<$NB_CARDS; x++ )); do
                    CURRENT_CARD=${CURRENT_CARDS[x]}

                    # On vérifie si la carte courante est présente dans son jeu
                    if [ "$CARD_TOPLAY" -eq "$CURRENT_CARD" ]; then
                        CANT_PLAY_THIS_CARD=false  # La carte est présente dans sa main
                    fi
                done

                # Si la carte n'est pas dans sa main, on affiche un message d'erreur et les cartes disponibles
                if [ "$CANT_PLAY_THIS_CARD" = true ]; then
                    echo "Impossible de jouer cette carte, vos cartes sont : ${CURRENT_CARDS[@]}"
                fi
            fi
        done

        # Suppression de la carte jouée par l'utilisateur
        NEW_CURRENT_CARDS=()
        for (( x=0; x<$NB_CARDS; x++ )); do
            CURRENT_CARD=${CURRENT_CARDS[x]}
            if [ "$CARD_TOPLAY" -ne "$CURRENT_CARD" ]; then
                NEW_CURRENT_CARDS+=("$CURRENT_CARD")  # Ajout des cartes restantes à un nouveau tableau
            fi
        done

        # Mise à jour des cartes restantes après suppression de la carte jouée
        CURRENT_CARDS=("${NEW_CURRENT_CARDS[@]}")

        # Mise à jour du nombre de cartes restantes après suppression
        NB_CARDS=${#CURRENT_CARDS[@]}

        setCards  # Sauvegarde des cartes restantes dans le fichier temporaire

        # Envoi de la carte jouée au gestionnaire via le pipe 'gestionJeu.pipe'
        echo $CARD_TOPLAY > gestionJeu.pipe

        # Affichage des cartes restantes après avoir joué une carte
        if [ "$NB_CARDS" -eq 0 ]; then
            echo "Vous n'avez plus de cartes"
        elif [ "$NB_CARDS" -eq 1 ]; then
            echo "Il vous reste une carte : ${CURRENT_CARDS[@]}"
        else
            echo "Vos cartes sont : ${CURRENT_CARDS[@]}"
        fi
    done
}


function ListenPipe(){
  # On récupère les données qui arrive au travers du pipe
  INCOMING_DATA=$(cat $PLAYER_ID.pipe)

  # On récupère l'id et le message de l'action
  API_CALL=${INCOMING_DATA:0:1}
  API_MESSAGE=${INCOMING_DATA:2}

  # On traite l'action
  if [ $(($API_CALL)) -eq $((5)) ];then 
    # Toutes les cartes ont été reçues
    getCards
    echo "Cartes reçues ! Vos cartes : "${CURRENT_CARDS[@]}
    ListenCardToPlay &
  elif [ $(($API_CALL)) -eq $((1)) ];then 
    # Une carte du tour courant a été trouvée
    echo $API_MESSAGE
  elif [ $(($API_CALL)) -eq $((2)) ];then 
    # Une mauvaise carte a été trouvée, le tour recommence
    echo $API_MESSAGE
  elif [ $(($API_CALL)) -eq $((3)) ];then 
    # Le tour est terminé, on passe au tour suivant
    echo $API_MESSAGE
  elif [ $(($API_CALL)) -eq $((4)) ];then 
    # Le jeu est terminé
    echo $API_MESSAGE
    read tmp
    exit
  fi

  ListenPipe
}

echo "Vous êtes le joueur n°"$PLAYER_ID
echo "En attente de vos cartes ..."

ListenPipe 
