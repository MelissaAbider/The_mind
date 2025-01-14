#!/bin/bash

ID_ROBOT=$1
CARTES_COURANTES=() # Contient les cartes du joueur
declare -i NB_CARTES=0 # On déclare un integer. Il décrit le nombre de cartes en main
CartePlusPetite=0
DERNIERE_CARTE_TROUVEE=0

function supprimerCarte(){
  # On supprime la carte jouée par l'utilisateur
  NB_CARTES=${#CARTES_COURANTES[@]}
  A_SUPPRIMER=$1
  TEMP=()
  for x in $( eval echo {0..$(($NB_CARTES-1))} );do
    if [ $((${CARTES_COURANTES[x]})) -ne $(($A_SUPPRIMER)) ];then
      TEMP+=(${CARTES_COURANTES[x]})
    fi
  done
  NB_CARTES=$(($NB_CARTES-1))
  CARTES_COURANTES=()
  CARTES_COURANTES=(${TEMP[@]})

  # On effectue un affichage des cartes
  if [ $(($NB_CARTES)) -eq $((0)) ];then
    echo "Vous n'avez plus de cartes"
  elif [ $(($NB_CARTES)) -eq $((1)) ];then
    echo "Il vous reste une carte : " ${CARTES_COURANTES[@]}
  else
    echo "Vos cartes sont ${CARTES_COURANTES[@]}"
  fi
}

function trouverPlusPetiteCarte(){
  # On trie les cartes que les joueurs doivent trouver
  CARTE_MINIMUM=1000
  NB_CARTES=$((${#CARTES_COURANTES[@]}))
  for x in $( eval echo {0..$(($NB_CARTES-1))} );do
    CARTE_COURANTE=${CARTES_COURANTES[x]}
    if [ $(($CARTE_COURANTE)) -lt $(($CARTE_MINIMUM)) ];then # On vérifie si la carte courante est inférieure au minimum courant
      CARTE_MINIMUM=$CARTE_COURANTE
    fi
  done    
}

function declencherEnvoiCarte(){
  NB_CARTES=${#CARTES_COURANTES[@]}
  if [ $(($NB_CARTES)) -gt $((0)) ];then
    DERNIERE_CARTE_TROUVEE=$1
    trouverPlusPetiteCarte
    DISTANCE_COURANTE=$(($CARTE_MINIMUM-$DERNIERE_CARTE_TROUVEE))
    DELAI_ALEATOIRE=$((RANDOM%5+4))
    (sleep $DELAI_ALEATOIRE; echo '9;'$DISTANCE_COURANTE> $ID_ROBOT.pipe) & 
  fi
}

function ecouterPipe(){
  DONNEES_RECUES=$(cat $ID_ROBOT.pipe)

  DONNEES_SEPAREES=(${DONNEES_RECUES//;/ }) # source (comment séparer un string) https://stackoverflow.com/a/5257398
  APPEL_API=${DONNEES_SEPAREES[0]}
  MESSAGE_API=${DONNEES_SEPAREES[1]}

  if [ $(($APPEL_API)) -eq $((1)) ];then # Une carte de la manche courante a été trouvée
    declencherEnvoiCarte 888
  elif [ $(($APPEL_API)) -eq $((5)) ];then # Toutes les cartes ont été reçues
    CARTES_COURANTES=()
    while read CARTE_COURANTE; do
      CARTES_COURANTES+=("$CARTE_COURANTE")
    done < $ID_ROBOT"_CARTES_COURANTES.tmp"
    echo "Cartes reçues ! Vos cartes : "${CARTES_COURANTES[@]}
    declencherEnvoiCarte 777
  elif [ $(($APPEL_API)) -eq $((2)) ];then # Une mauvaise carte a été trouvée, la manche recommence
    CARTES_COURANTES=()
    DERNIERE_CARTE_TROUVEE=666
  elif [ $(($APPEL_API)) -eq $((3)) ];then # La manche est terminée, on passe à la suivante
    CARTES_COURANTES=()
    DERNIERE_CARTE_TROUVEE=555
  elif [ $(($APPEL_API)) -eq $((4)) ];then # Le jeu est terminé
    exit
  elif [ $(($APPEL_API)) -eq $((9)) ];then
      DISTANCE_RECUE=$MESSAGE_API  
      trouverPlusPetiteCarte
      DISTANCE_COURANTE_2=$(($CARTE_MINIMUM-$DERNIERE_CARTE_TROUVEE))

    if [ $(($DISTANCE_RECUE)) -eq $(($DISTANCE_COURANTE_2)) ];then # On vérifie si la distance n'a pas changé (qu'aucune carte n'a été jouée entre temps)
      # On joue la carte 
      echo $CARTE_MINIMUM > gestionJeu.pipe
      echo "La carte $CARTE_MINIMUM a été jouée"
      supprimerCarte $CARTE_MINIMUM
    fi
  fi

  ecouterPipe
}

echo "Vous êtes le robot n°"$ID_ROBOT
echo "En attente de vos cartes ..."

ecouterPipe