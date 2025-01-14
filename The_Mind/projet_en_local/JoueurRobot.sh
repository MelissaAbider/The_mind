#!/bin/bash

ROBOT_ID=$1
CARTES_COURANTES=() # Contient les cartes du joueur
declare -i NOMBRE_CARTES=0 # On déclare un integer. Il décrit le nombre de carte en main
PlusPetiteCarte=0
DERNIERE_CARTE_TROUVEE=0

function retirerCarte(){
  # On supprime la carte jouée par l'utilisateur
  NOMBRE_CARTES=${#CARTES_COURANTES[@]}
  A_RETIRER=$1
  TEMPORAIRE=()
  for x in $( eval echo {0..$(($NOMBRE_CARTES-1))} );do
    if [ $((${CARTES_COURANTES[x]})) -ne $(($A_RETIRER)) ];then
      TEMPORAIRE+=(${CARTES_COURANTES[x]})
    fi
  done
  NOMBRE_CARTES=$(($NOMBRE_CARTES-1))
  CARTES_COURANTES=()
  CARTES_COURANTES=(${TEMPORAIRE[@]})

  # On effectue un affichage des cartes
  if [ $(($NOMBRE_CARTES)) -eq $((0)) ];then
    echo "Vous n'avez plus de cartes"
  elif [ $(($NOMBRE_CARTES)) -eq $((1)) ];then
    echo "Il vous reste une carte : " ${CARTES_COURANTES[@]}
  else
    echo "Vos cartes sont ${CARTES_COURANTES[@]}"
  fi
}

function obtenirPlusPetiteCarte(){
  # On trie les cartes que les joueurs doivent trouver
  PLUS_PETITE_CARTE=1000
  NOMBRE_CARTES=$((${#CARTES_COURANTES[@]}))
  for x in $( eval echo {0..$(($NOMBRE_CARTES-1))} );do
    CARTE_COURANTE=${CARTES_COURANTES[x]}
    if [ $(($CARTE_COURANTE)) -lt $(($PLUS_PETITE_CARTE)) ];then # On vérifie si la carte courante est inférieure au minimum courant
      PLUS_PETITE_CARTE=$CARTE_COURANTE
    fi
  done    
}

function declencherEnvoiCarte(){
  NOMBRE_CARTES=${#CARTES_COURANTES[@]}
  if [ $(($NOMBRE_CARTES)) -gt $((0)) ];then
    DERNIERE_CARTE_TROUVEE=$1
    obtenirPlusPetiteCarte
    DISTANCE_COURANTE=$(($PLUS_PETITE_CARTE-$DERNIERE_CARTE_TROUVEE))
    ALEATOIRE=$((RANDOM%8+8))
    (sleep $ALEATOIRE; echo '9;'$DISTANCE_COURANTE> $ROBOT_ID.pipe) & 
  fi
}

function ecouterPipe(){
  DONNEES_ENTRANTES=$(cat $ROBOT_ID.pipe)

  DONNEES_SEPAREES=(${DONNEES_ENTRANTES//;/ }) # https://stackoverflow.com/a/5257398
  APPEL_API=${DONNEES_SEPAREES[0]}
  MESSAGE_API=${DONNEES_SEPAREES[1]}

  if [ $(($APPEL_API)) -eq $((1)) ];then # Une carte du tour courant a été trouvée
    declencherEnvoiCarte 888
  elif [ $(($APPEL_API)) -eq $((5)) ];then # Toutes les cartes ont été reçues
    CARTES_COURANTES=()
    while read CARTE_COURANTE; do
      CARTES_COURANTES+=("$CARTE_COURANTE")
    done < $ROBOT_ID"_CARTES_COURANTES.tmp"
    echo "Cartes reçues ! Vos cartes : "${CARTES_COURANTES[@]}
    declencherEnvoiCarte 777
  elif [ $(($APPEL_API)) -eq $((2)) ];then # Une mauvaise carte a été trouvée, le tour recommence
    CARTES_COURANTES=()
    DERNIERE_CARTE_TROUVEE=666
  elif [ $(($APPEL_API)) -eq $((3)) ];then # Le tour est terminé, on passe au tour suivant
    CARTES_COURANTES=()
    DERNIERE_CARTE_TROUVEE=555
  elif [ $(($APPEL_API)) -eq $((4)) ];then # Le jeu est terminé
    exit
  elif [ $(($APPEL_API)) -eq $((9)) ];then
      DISTANCE_RECUE=$MESSAGE_API  
      obtenirPlusPetiteCarte
      DISTANCE_COURANTE_2=$(($PLUS_PETITE_CARTE-$DERNIERE_CARTE_TROUVEE))

    if [ $(($DISTANCE_RECUE)) -eq $(($DISTANCE_COURANTE_2)) ];then # On vérifie si la distance n'a pas changé (qu'aucune carte n'a été jouée entre temps)
      # On joue la carte 
      echo $PLUS_PETITE_CARTE > gestionJeu.pipe
      echo "La carte $PLUS_PETITE_CARTE a été jouée"
      retirerCarte $PLUS_PETITE_CARTE
    fi
  fi

  ecouterPipe
}

echo "Vous êtes le robot n°"$ROBOT_ID
echo "En attente de vos cartes ..."

ecouterPipe