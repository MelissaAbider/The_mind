#!/bin/bash

ROBOT_ID=$1
CARTES_COURANTES=() # Contient les cartes du joueur
declare -i NB_CARTES=0 # On déclare un integer. Il décrit le nombre de carte en main
PlusPetiteCarte=0
DERNIERE_CARTE_TROUVEE=0
MANCHE=0

function supprimerCarte(){
  # On supprime la carte jouée par l'utilisateur
  NB_CARTES=${#CARTES_COURANTES[@]}
  A_SUPPRIMER=$1
  TMP=()
  for x in $( eval echo {0..$(($NB_CARTES-1))} );do
    if [ $((${CARTES_COURANTES[x]})) -ne $(($A_SUPPRIMER)) ];then
      TMP+=(${CARTES_COURANTES[x]})
    fi
  done
  NB_CARTES=$(($NB_CARTES-1))
  CARTES_COURANTES=()
  CARTES_COURANTES=(${TMP[@]})

  # On effectue un affichage des cartes
  if [ $(($NB_CARTES)) -eq $((0)) ];then
    echo "Vous n'avez plus de cartes"
  elif [ $(($NB_CARTES)) -eq $((1)) ];then
    echo "Il vous reste une carte : " ${CARTES_COURANTES[@]}
  else
    echo "Vos cartes sont ${CARTES_COURANTES[@]}"
  fi
}

function obtenirPlusPetiteCarte(){
  # On trie les cartes que les joueurs doivent trouver
  PLUS_PETITE_CARTE=1000
  NB_CARTES=$((${#CARTES_COURANTES[@]}))
  for x in $( eval echo {0..$(($NB_CARTES-1))} );do
    CARTE_COURANTE=${CARTES_COURANTES[x]}
    if [ $(($CARTE_COURANTE)) -lt $(($PLUS_PETITE_CARTE)) ];then # On vérifie si la carte courante est inférieure au minimum courant
      PLUS_PETITE_CARTE=$CARTE_COURANTE
    fi
  done    
}

function declencherEnvoiCarte() {
  NB_CARTES=${#CARTES_COURANTES[@]}

  if [ $NB_CARTES -eq 0 ]; then
    echo "Aucune carte disponible pour jouer."
  else
    IFS=',' read -r -a CARTES <<< "$2"  # On lit les cartes passées dans le pipe (si elles existent)
    CARTES_COURANTES_CHAINE=$(IFS=','; echo "${CARTES_COURANTES[*]}")
    CARTES_CHAINE=$(IFS=','; echo "${CARTES[*]}")
    echo "$CARTES_COURANTES_CHAINE"
  fi

  # Vérification de la disponibilité des paramètres pour la prédiction
  echo "$MANCHE,$NB_JOUEURS,$NB_ROBOTS"
  if [ -z "$MANCHE" ] || [ -z "$NB_JOUEURS" ] || [ -z "$NB_ROBOTS" ]; then
    echo "Erreur : MANCHE, NB_JOUEURS ou NB_ROBOTS n'est pas défini."
    return
  fi

  # Appeler la prédiction en passant les cartes sous forme de chaînes (leurs valeurs)
  CARTE_PREDITE=$(python3 prediction.py $MANCHE $NB_JOUEURS $NB_ROBOTS "$CARTES_COURANTES_CHAINE" "$CARTES_CHAINE")

  if [ $? -eq 0 ] && [ -n "$CARTE_PREDITE" ]; then
    echo $CARTE_PREDITE > gestionJeu.pipe
    echo "La carte $CARTE_PREDITE a été jouée."
    supprimerCarte $CARTE_PREDITE
  else
    echo "Erreur lors de la prédiction ou aucune carte valide à jouer."
  fi
}

function ecouterPipe(){
  DONNEES_ENTRANTES=$(cat $ROBOT_ID.pipe)

  DONNEES_SEPAREES=(${DONNEES_ENTRANTES//;/ }) # https://stackoverflow.com/a/5257398
  APPEL_API=${DONNEES_SEPAREES[0]}
  MESSAGE_API=${DONNEES_SEPAREES[1]}

  if [ $(($APPEL_API)) -eq $((1)) ];then # Une carte du tour courant a été trouvée
    IFS=',' read -r -a CARTES <<< "$MESSAGE_API" # Analyse les cartes trouvées
    echo "Cartes trouvées : ${CARTES[@]}"
    declencherEnvoiCarte 888
  elif [ $(($APPEL_API)) -eq $((5)) ];then # Toutes les cartes ont été reçues
    CARTES_COURANTES=()
    while read CARTE_COURANTE; do
      CARTES_COURANTES+=("$CARTE_COURANTE")
    done < $ROBOT_ID"_CURRENT_CARDS.tmp"
    # Écrire les cartes actuelles dans un fichier temporaire
    echo "${CARTES_COURANTES[*]}" >"cartes_courantes_robot.txt"
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
  elif [ $(($APPEL_API)) -eq $((6)) ];then
    MANCHE=$MESSAGE_API
  elif [ $(($APPEL_API)) -eq $((7)) ];then
    IFS=',' read NB_JOUEURS NB_ROBOTS <<< "$MESSAGE_API"
    echo "Informations des joueurs reçues : $MESSAGE_API"
    echo "Nombre de joueurs humains : $NB_JOUEURS"
    echo "Nombre de robots : $NB_ROBOTS"
  elif [ $(($APPEL_API)) -eq $((9)) ];then
    DISTANCE_RECUE=$MESSAGE_API  
    obtenirPlusPetiteCarte
    DISTANCE_COURANTE_2=$(($PLUS_PETITE_CARTE-$DERNIERE_CARTE_TROUVEE))

    if [ $(($DISTANCE_RECUE)) -eq $(($DISTANCE_COURANTE_2)) ];then # On vérifie si la distance n'a pas changé (qu'aucune carte n'a été jouée entre temps)
      # On joue la carte 
      echo $PLUS_PETITE_CARTE > gestionJeu.pipe
      echo "La carte $PLUS_PETITE_CARTE a été jouée"
      supprimerCarte $PLUS_PETITE_CARTE
    fi
  fi

  ecouterPipe
}

echo "Vous êtes le robot n°"$ROBOT_ID
echo "En attente de vos cartes ..."

ecouterPipe