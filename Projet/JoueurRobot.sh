#!/bin/bash

ROBOT_ID=$1
CURRENT_CARDS=() # Contient les cartes du joueur
declare -i NB_CARDS=0 # On déclare un integer. Il décrit le nombre de carte en main
SmallestCard=0
LAST_FOUNDED_CARD=0

function removeCard(){
  # On supprime la carte jouée par l'utilisateur
  NB_CARDS=${#CURRENT_CARDS[@]}
  TO_REMOVE=$1
  TMP=()
  for x in $( eval echo {0..$(($NB_CARDS-1))} );do
    if [ $((${CURRENT_CARDS[x]})) -ne $(($TO_REMOVE)) ];then
      TMP+=(${CURRENT_CARDS[x]})
    fi
  done
  NB_CARDS=$(($NB_CARDS-1))
  CURRENT_CARDS=()
  CURRENT_CARDS=(${TMP[@]})

  # On effectue un affichage des cartes
  if [ $(($NB_CARDS)) -eq $((0)) ];then
    echo "Vous n'avez plus de cartes"
  elif [ $(($NB_CARDS)) -eq $((1)) ];then
    echo "Il vous reste une carte : " ${CURRENT_CARDS[@]}
  else
    echo "Vos cartes sont ${CURRENT_CARDS[@]}"
  fi
}

function getSmallestCard(){
 # On trie les cartes que les joueurs doivent trouver
  SMALLEST_CARD=1000
  NB_CARDS=$((${#CURRENT_CARDS[@]}))
  for x in $( eval echo {0..$(($NB_CARDS-1))} );do
    CURRENT_CARD=${CURRENT_CARDS[x]}
    if [ $(($CURRENT_CARD)) -lt $(($SMALLEST_CARD)) ];then # On vérifie si la carte courante est inférieur au minimun courant
      SMALLEST_CARD=$CURRENT_CARD
    fi
  done    
}

function triggerShouldSendCard(){
  NB_CARDS=${#CURRENT_CARDS[@]}
  if [ $(($NB_CARDS)) -gt $((0)) ];then
    LAST_FOUNDED_CARD=$1
    getSmallestCard
    CURRENT_DISTANCE=$(($SMALLEST_CARD-$LAST_FOUNDED_CARD))
    RANDOM0=$((RANDOM%5+4))
    (sleep $RANDOM0; echo '9;'$CURRENT_DISTANCE> $ROBOT_ID.pipe) & 
  fi
}

function ListenPipe(){
  INCOMING_DATA=$(cat $ROBOT_ID.pipe)

  SPLIT_DATA=(${INCOMING_DATA//;/ }) # https://stackoverflow.com/a/5257398
  API_CALL=${SPLIT_DATA[0]}
  API_MESSAGE=${SPLIT_DATA[1]}

  if [ $(($API_CALL)) -eq $((1)) ];then # Une carte du tour courant a été trouvée
    triggerShouldSendCard 888
  elif [ $(($API_CALL)) -eq $((5)) ];then # Toutes les cartes ont été reçues
    CURRENT_CARDS=()
    while read CURRENT_CARD; do
      CURRENT_CARDS+=("$CURRENT_CARD")
    done < $ROBOT_ID"_CURRENT_CARDS.tmp"
    echo "Cartes reçues ! Vos cartes : "${CURRENT_CARDS[@]}
    triggerShouldSendCard 777
  elif [ $(($API_CALL)) -eq $((2)) ];then # Une mauvaise carte a été trouvée, le tour recommence
    CURRENT_CARDS=()
    LAST_FOUNDED_CARD=666
  elif [ $(($API_CALL)) -eq $((3)) ];then # Le tour est terminé, on passe au tour suivant
    CURRENT_CARDS=()
    LAST_FOUNDED_CARD=555
  elif [ $(($API_CALL)) -eq $((4)) ];then # Le jeu est terminé
    exit
  elif [ $(($API_CALL)) -eq $((9)) ];then
      RECEIVED_DISTANCE=$API_MESSAGE  
      getSmallestCard
      CURRENT_DISTANCE_2=$(($SMALLEST_CARD-$LAST_FOUNDED_CARD))

    if [ $(($RECEIVED_DISTANCE)) -eq $(($CURRENT_DISTANCE_2)) ];then # On vérifie si la distance n'a pas changé ( que aucune carte n'a été jouée entre temps )
      # On joue la carte 
      echo $SMALLEST_CARD > gestionJeu.pipe
      echo "La carte $SMALLEST_CARD a été jouer"
      removeCard $SMALLEST_CARD
    fi
  fi

  ListenPipe
}

echo "Vous êtes le robot n°"$ROBOT_ID
echo "En attente de vos cartes ..."


ListenPipe 
