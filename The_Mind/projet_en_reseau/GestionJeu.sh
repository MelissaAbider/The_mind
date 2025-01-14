#!/bin/bash
 
CARTES=() # Tableau qui contient les cartes mélangées
declare -i MANCHE=1 # On déclare un integer. Il décrit le numéro du tour
CARTES_TRIEES_MANCHE_COURANTE=() # Liste des cartes tirees et triees pour le tour courant
declare -i INDICE_CARTE_COURANTE=0 # On déclare un integer. Il décrit l'index de la carte que l'on doit trouver pour le MANCHE courant
NBJOUEURS=0 # Décrit le nombre de joueur
NBROBOT=0 # Décrit le nombre de robot
TPS_REACTION=15
declare -i MANCHE_MAX=0 # On déclare un integer. Décrit le nombre maximun de tour
MODE_RESEAU=false # Indique si on est en mode réseau

# Inclure le fichier contenant la logique du classement et statistiques
source ./classement.sh
source ./stats.sh

function InitJoueurs(){
  if [ "$1" = "network" ]; then
    MODE_RESEAU=true
    # En mode réseau, on lit le nombre de joueurs et robots depuis stdin
    read NBJOUEURS
    read NBROBOT
    echo "[INFO] Mode réseau : $NBJOUEURS joueurs et $NBROBOT robots"
  else
    # Mode normal : demander le nombre de joueurs et robots
    echo -n "Entrer le nombre de joueur : "
    read NBJOUEURS
    echo -n "Entrer le nombre de robot : "
    read NBROBOT
  fi

  # On supprime les pipes existants
  supprimerAnciensFichiers
  
  # En mode réseau, on ne lance pas les terminaux
  if [ "$MODE_RESEAU" = false ]; then
    if [ "$NBJOUEURS" -gt 0 ]; then
      for ((x = 0; x < NBJOUEURS; x++)); do
        xterm -e "./JoueurHumain.sh $x" & 
        mkfifo "$x.pipe"
      done
    fi

    if [ "$NBROBOT" -gt 0 ]; then
      start=$((NBJOUEURS))
      end=$((start + NBROBOT - 1))

      for x in $(seq "$start" "$end"); do
        xterm -e "./JoueurRobot.sh $x" &
        mkfifo "$x.pipe"
      done
    fi
  else
    # En mode réseau, créer seulement le pipe de gestion
    mkfifo "gestionJeu.pipe"
  fi
}

function FinJeu(){
    echo "[INFO] | Le jeu est terminé"
    
    EnvoyerMsgJoueur "4" "Félicitations, le jeu est terminé"
    
    EnvoyerMsgRobot "4" "robot msg skip"

    #Appel les fonctions de génération de stat et du classement '''
    afficherTop10  # Afficher et sauvegarder le top 10 des scores
    genererGraphique      # Graphique du nombre de manches réussies par partie.
    genererHistogrammeCartesPerdues   # Histogramme des cartes ayant échoué une manche.
    calculerTempsReactionMoyen #le temps de reation moyen 
    genererPDF        # Générer le fichier PDF final.
    supprimerAnciensFichiers

    exit
}


# Initialise le tableau des cartes (1 à 100)
function initialiserCartes() {
    CARTES=()
    for x in {1..100}; do
        CARTES+=($x)
    done
    INDICE_CARTE_COURANTE=0  # Réinitialise l'index de la carte courante
}

# Mélange les cartes en échangeant des positions aléatoires
function melangerCartes() {
    for x in {1..100}; do
        RANDOM0=$((RANDOM % 99))
        RANDOM1=$((RANDOM % 99))
        TMP=${CARTES[$RANDOM0]}
        CARTES[$RANDOM0]=${CARTES[$RANDOM1]}
        CARTES[$RANDOM1]=$TMP
    done
}

# Distribue les cartes aux joueurs et robots
function distribuerCartes() {
    echo "[DEBUG] Début de la distribution des cartes"
    CARTES_TRIEES_MANCHE_COURANTE=()
    declare -i INDICE_CARTE_COURANTE=0

    # Attendre que le pipe soit prêt
    while [ ! -p "gestionJeu.pipe" ]; do
        sleep 1
    done
    
    exec 3>gestionJeu.pipe  # Ouvrir le pipe une seule fois
    
    for x in $(eval echo {0..$(($NBJOUEURS + $NBROBOT - 1))}); do
        local cartes_du_joueur=""
        
        for y in $(eval echo {0..$(($MANCHE - 1))}); do
            CARTE_COURANTE=${CARTES[INDICE_CARTE_COURANTE]}
            cartes_du_joueur+="$CARTE_COURANTE "
            CARTES_TRIEES_MANCHE_COURANTE+=($CARTE_COURANTE)
            INDICE_CARTE_COURANTE+=1
        done

        # Écrire dans le pipe avec ID explicite
        echo "ID:$x;6;$cartes_du_joueur" >&3
        sleep 0.2  # Petit délai pour éviter la congestion
    done

    # Notification de fin de distribution
    sleep 0.5
    for x in $(eval echo {0..$(($NBJOUEURS + $NBROBOT - 1))}); do
        echo "ID:$x;5;" >&3
        sleep 0.2
    done
    
    exec 3>&-  # Fermer le descripteur de fichier
}

# Envoie un message indiquant que les cartes ont été distribuées
function envoyerNotificationDistribution() {
    for x in $(eval echo {1..$(tput cols)}); do
        echo -e "-\c"
    done
    EnvoyerMsgJoueur "5" ""
    EnvoyerMsgRobot "5" "robot msg skip"
}

# Trie les cartes distribuées pour le MANCHE courant dans l'ordre croissant
function trierCartes() {
    CARTES_TRIEES_MANCHE_COURANTE=()
    for x in $(eval echo {0..$(($MANCHE * $NBJOUEURS + $MANCHE * $NBROBOT - 1))}); do
        MINIMUM=1000 # plus petite valeur trouvée après chaque itération
        INDICE_MINIMUM=-1
        INDICE_NON_TRIE=$((${#CARTES_TRIEES_MANCHE_COURANTE[@]} - 1))

        for y in $(eval echo {0..$INDICE_NON_TRIE}); do
            CARTE_COURANTE=${CARTES_TRIEES_MANCHE_COURANTE[y]}
            if [ "$CARTE_COURANTE" -lt "$MINIMUM" ]; then
                MINIMUM=$CARTE_COURANTE
                INDICE_MINIMUM=$y
            fi
        done

        CARTES_TRIEES_MANCHE_COURANTE+=($MINIMUM)
        supprimerValeur $INDICE_MINIMUM  # Supprime la carte triée de la liste non triée
    done

    echo "[LOGS] | Liste des cartes à trouver : ${CARTES_TRIEES_MANCHE_COURANTE[@]}"
}

# Fonction principale orchestrant toutes les étapes ci-dessus
function envoyerCartes() {
    initialiserCartes           # Étape 1 : Initialisation des cartes (1 à 100)
    melangerCartes              # Étape 2 : Mélange des cartes aléatoirement
    distribuerCartes  # Étape 3 : Distribution des cartes aux joueurs/robots
    envoyerNotificationDistribution  # Étape 4 : Notification de distribution des cartes
    trierCartes       # Étape 5 : Tri des cartes pour le MANCHE courant
}


function supprimerValeur() {
    # Supprime la carte à l'indice spécifié dans CARTES_TRIEES_MANCHE_COURANTE
    INDICE_A_SUPPRIMER=$1
    TMP=()

    for ((i = 0; i <= INDICE_NON_TRIE; i++)); do
        if [ "$i" -ne "$INDICE_A_SUPPRIMER" ]; then
            TMP+=("${CARTES_TRIEES_MANCHE_COURANTE[i]}")
        fi
    done
    CARTES_TRIEES_MANCHE_COURANTE=()
    CARTES_TRIEES_MANCHE_COURANTE=("${TMP[@]}")
}

#Fonction à utiliser pour afficher les cartes trouvé dans un partie
function mettreAJourCartesTrouvees() {
    # Préparation de l'affichage des cartes trouvées
    CARTES_TROUVEES="( "
    
    for ((x = 0; x <= INDICE_CARTE_COURANTE; x++)); do
        CARTES_TROUVEES+="${CARTES_TRIEES_MANCHE_COURANTE[x]} "
    done

    CARTES_TROUVEES+=")"
}


# Vérifie si le pipe nommé existe, sinon il est créé
function verifierOuCreerPipe() {
    if [ "$MODE_RESEAU" = true ]; then
        # En mode réseau, on utilise uniquement le pipe principal
        if [[ ! -p "gestionJeu.pipe" ]]; then
            mkfifo gestionJeu.pipe
        fi
    else
        # Mode local inchangé
        if [[ ! -p "gestionJeu.pipe" ]]; then
            mkfifo gestionJeu.pipe
        fi
        # Créer les pipes pour chaque joueur en mode local
        for ((x = 0; x < NBJOUEURS; x++)); do
            if [[ ! -p "$x.pipe" ]]; then
                mkfifo "$x.pipe"
            fi
        done
    fi
}

# Enregistre l'heure de début pour calculer le temps de réaction
function enregistrerHeureDebut() {
    START_TIME=$(date +%s)
}

# Lit les données envoyées via le pipe
function lireCarteEntrante() {
    if [ -p "gestionJeu.pipe" ]; then
        if read -t 0.1 CARTE_JOUEE <gestionJeu.pipe; then
            echo "[DEBUG] Carte reçue : $CARTE_JOUEE"
        fi
    fi
}

# Calcule le temps de réaction
function calculerTempsReaction() {
    END_TIME=$(date +%s)
    TPS_REACTION=$((END_TIME - START_TIME))
}

# Vérifie si un joueur a envoyé une commande pour quitter
function commandeQuitter() {
    if [[ "$CARTE_JOUEE" == "QUIT" || "$CARTE_JOUEE" == "q" ]]; then
        echo "[INFO] | Un joueur a demandé l'arrêt du jeu."
        FinJeu  # Appelle la fonction pour terminer proprement le jeu
    fi
}

# Vérifie si la carte reçue est correcte ou non
function verifierCarteGagnante() {
    CARTE_GAGNANTE=${CARTES_TRIEES_MANCHE_COURANTE[INDICE_CARTE_COURANTE]}
    if [ "$CARTE_GAGNANTE" -eq "$CARTE_JOUEE" ]; then
        gererCarteCorrecte
    else
        gererCarteIncorrecte
    fi
}

# Gère les actions en cas de bonne carte jouée
function gererCarteCorrecte() {
    mettreAJourCartesTrouvees  # Met à jour les cartes trouvées

    echo "[INFO] | La carte $CARTE_JOUEE a été trouvée, voici les cartes trouvées : $CARTES_TROUVEES"
    EnvoyerMsgJoueur "1" "Bravo, une carte a été trouvée, voici les cartes trouvées : $CARTES_TROUVEES"
    EnvoyerMsgRobot "1" "$CARTES_TROUVEES"

    INDICE_CARTE_COURANTE+=1  # Passe à la carte suivante

    # Met à jour les statistiques avec succès = 1 (manche réussie)
    mettreAJourStatistiques "$MANCHE" "$CARTE_JOUEE" "$TPS_REACTION" 1

    gererFinDeTour  # Vérifie si toutes les cartes du MANCHE ont été trouvées
}

# Vérifie si toutes les cartes du MANCHE ont été trouvées et passe au MANCHE suivant ou termine le jeu
function gererFinDeTour() {
    if [ "$INDICE_CARTE_COURANTE" -eq $((MANCHE * NBJOUEURS + MANCHE * NBROBOT)) ]; then
        MANCHES_MAX=$((14 - 2 * (NBJOUEURS + NBROBOT - 1)))  # Calcul du nombre maximal de manches

        if [ "$MANCHE" -lt "$MANCHES_MAX" ]; then
            echo "[INFO] | Le tour n°'$MANCHE' est terminé"
            EnvoyerMsgJoueur "3" "Félicitations, le tour n°'$MANCHE' est terminé, on passe au tour suivant"

            MANCHE+=1  # Passe au MANCHE suivant

            envoyerCartes  # Mélange et distribue un nouveau jeu de cartes

            # Met à jour le classement des joueurs et robots après une manche réussie
            for ((i = 0; i < NBJOUEURS; i++)); do
                mettreAJourClassement "Joueur_$i" "$MANCHE"
            done

            for ((i = 0; i < NBROBOT; i++)); do
                mettreAJourClassement "Robot_$i" "$MANCHE"
            done
        else
            FinJeu  # Fin du jeu si toutes les manches sont terminées
        fi
    fi
}

# Gère les actions en cas de mauvaise carte jouée
function gererCarteIncorrecte() {
    echo "[INFO] | La carte $CARTE_JOUEE n'était pas la bonne, la bonne était : $CARTE_GAGNANTE"
    
    EnvoyerMsgJoueur "2" "Perdu, la carte $CARTE_JOUEE n'était pas la bonne, la bonne était : $CARTE_GAGNANTE. On recommence !"
    EnvoyerMsgRobot "2" "robot msg skip"
    # Met à jour les statistiques avec succès = 0 (manche échouée)
    mettreAJourStatistiques "$MANCHE" "$CARTE_JOUEE" "$TPS_REACTION" 0
    envoyerCartes  # Redistribue un nouveau jeu de cartes pour recommencer le MANCHE
}

# Fonction principale orchestrant toutes les sous-fonctions ci-dessus
function EcouterPipe() {
    verifierOuCreerPipe
    while true; do
        enregistrerHeureDebut
        lireCarteEntrante || true  # Ajouter || true pour éviter l'arrêt sur erreur
        if [ -n "$CARTE_JOUEE" ]; then  # Vérifier si on a reçu une carte
            calculerTempsReaction
            
            if [[ "$CARTE_JOUEE" == "QUIT" || "$CARTE_JOUEE" == "q" ]]; then
                commandeQuitter
                continue
            fi
            
            verifierCarteGagnante
        fi
        sleep 0.1  # Petit délai pour éviter de surcharger le CPU
    done
}

function EnvoyerMsgJoueur() {
    if [ "$NBJOUEURS" -gt 0 ]; then
        local MSG_ID=$1
        local MSG_A_ENVOYER=$2

        if [ "$MODE_RESEAU" = true ]; then
            for ((x = 0; x < NBJOUEURS; x++)); do
                echo "ID:$x;$MSG_ID;$MSG_A_ENVOYER" > gestionJeu.pipe
                sleep 0.1
            done
        else
            for ((x = 0; x < NBJOUEURS; x++)); do
                if [ -p "$x.pipe" ]; then
                    echo "$MSG_ID;$MSG_A_ENVOYER" > "$x.pipe"
                fi
            done
        fi
        echo "[LOGS] | L'action n°$MSG_ID a été envoyée aux joueurs humains"
    fi
}

function EnvoyerMsgRobot() {  
    if [ "$NBROBOT" -gt 0 ]; then
        local MSG_ID=$1
        local MSG_A_ENVOYER=$2

        for ((x = NBJOUEURS; x < NBJOUEURS + NBROBOT; x++)); do
            if [ -p "$x.pipe" ]; then  # Vérifier si le pipe existe
                echo "$MSG_ID;$MSG_A_ENVOYER" > "$x.pipe"
            fi
        done
        echo "[LOGS] | L'action n°$MSG_ID a été envoyée aux joueurs robots"
    fi
}

function supprimerAnciensFichiers(){
  # Supprime toutes les pipes / tout les fichiers tmp précédent
  # On envoit les messages d'erreurs vers null 
  # Cette redirection est justifier par le fait que si il n'existe pas de fichiers .tmp alors rm affiche une erreur
  rm .pipe 2>/dev/null
  rm *.tmp 2>/dev/null
  rm *.pipe 2>/dev/null
}

# Modification de la partie principale pour supporter le mode réseau
MODE="local"
if [ "$1" = "network" ]; then
    MODE="network"
fi

InitJoueurs $MODE
envoyerCartes
EcouterPipe