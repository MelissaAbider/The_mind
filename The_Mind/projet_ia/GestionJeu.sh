#!/bin/bash
 
CARTES=() # Tableau qui contient les cartes mélangées
declare -i MANCHE=1 # On déclare un integer. Il décrit le numéro de la manche
CARTES_TRIEES_MANCHE_COURANTE=() # Liste des cartes tirées et triées pour la manche courante
declare -i INDEX_CARTE_COURANTE=0 # On déclare un integer. Il décrit l'index de la carte que l'on doit trouver pour la manche courante
NBJOUEURS=0 # Décrit le nombre de joueurs
NBROBOT=0 # Décrit le nombre de robots
TEMPS_REACTION=15
declare -i MANCHES_MAX=0 # On déclare un integer. Décrit le nombre maximum de manches
# Inclure le fichier contenant la logique du classement et statistiques
source ./classement.sh
source ./stats.sh

function InitJoueurs(){
  # On demande le nombre de joueurs
  echo -n "Entrer le nombre de joueurs : "
  read NBJOUEURS

  # On demande le nombre de robots
  echo -n "Entrer le nombre de robots : "
  read NBROBOT

  # On supprime les pipes existants
  supprimerAnciensFichiers
  
   if [ "$NBJOUEURS" -gt 0 ]; then
     # Initialisation des terminaux et des pipes pour chaque joueur
     for ((x = 0; x < NBJOUEURS; x++)); do
         xterm -e "./JoueurHumain.sh $x" &
         mkfifo "$x.pipe"
     done
  fi

  if [ "$NBROBOT" -gt 0 ]; then
    # Initialisation des terminaux et des pipes pour les robots
    debut=$((MANCHE * NBJOUEURS))
    fin=$((debut + MANCHE * NBROBOT - 1))

    for x in $(seq "$debut" "$fin"); do
        xterm -e "./JoueurRobot.sh $x" &
        mkfifo "$x.pipe"
    done
 fi
 EnvoyerMsgRobot "7" "$NBJOUEURS,$NBROBOT"
}

function FinJeu(){
    echo "[INFO] | Le jeu est terminé"
    
    EnvoyerMsgJoueur "4" "Félicitations, le jeu est terminé"
    
    EnvoyerMsgRobot "4" "message robot ignoré"

    #Appel les fonctions de génération de statistiques et du classement
    afficherTop10  # Afficher et sauvegarder le top 10 des scores
    genererGraphique      # Graphique du nombre de manches réussies par partie
    genererHistogrammeCartesPerdues   # Histogramme des cartes ayant échoué une manche
    calculerTempsReactionMoyen # Le temps de réaction moyen 
    genererPDF        # Générer le fichier PDF final
    supprimerAnciensFichiers

    exit
}

# Initialise le tableau des cartes (1 à 100)
function initialiserCartes() {
    CARTES=()
    for x in {1..100}; do
        CARTES+=($x)
    done
    INDEX_CARTE_COURANTE=0  # Réinitialise l'index de la carte courante
}

# Mélange les cartes en échangeant des positions aléatoires
function melangerCartes() {
    for x in {1..100}; do
        ALEATOIRE0=$((RANDOM % 99))
        ALEATOIRE1=$((RANDOM % 99))
        TMP=${CARTES[$ALEATOIRE0]}
        CARTES[$ALEATOIRE0]=${CARTES[$ALEATOIRE1]}
        CARTES[$ALEATOIRE1]=$TMP
    done
}

# Distribue les cartes aux joueurs et robots
function distribuerCartes() {
    CARTES_NON_TRIEES_MANCHE_COURANTE=()
    declare -i INDEX_CARTE_COURANTE=0

    for x in $(eval echo {0..$(($NBJOUEURS + $NBROBOT - 1))}); do
        for y in $(eval echo {0..$(($MANCHE - 1))}); do
            CARTE_COURANTE=${CARTES[INDEX_CARTE_COURANTE]}
            echo $CARTE_COURANTE
            CARTES_NON_TRIEES_MANCHE_COURANTE+=($CARTE_COURANTE)
            INDEX_CARTE_COURANTE+=1
        done > $x"_CARTES_COURANTES.tmp"
        
    done
}

# Envoie un message indiquant que les cartes ont été distribuées
function envoyerNotificationDistribution() {
    for x in $(eval echo {1..$(tput cols)}); do
        echo -e "-\c"
    done
    EnvoyerMsgJoueur "5" ""
    EnvoyerMsgRobot "5" "message robot ignoré"
}

# Trie les cartes distribuées pour la manche courante dans l'ordre croissant
function trierCartes() {
    CARTES_TRIEES_MANCHE_COURANTE=()
    for x in $(eval echo {0..$(($MANCHE * $NBJOUEURS + $MANCHE * $NBROBOT - 1))}); do
        MINIMUM_COURANT=1000
        INDEX_MINIMUM=-1
        INDEX_NON_TRIE=$((${#CARTES_NON_TRIEES_MANCHE_COURANTE[@]} - 1))

        for y in $(eval echo {0..$INDEX_NON_TRIE}); do
            CARTE_COURANTE=${CARTES_NON_TRIEES_MANCHE_COURANTE[y]}
            if [ "$CARTE_COURANTE" -lt "$MINIMUM_COURANT" ]; then
                MINIMUM_COURANT=$CARTE_COURANTE
                INDEX_MINIMUM=$y
            fi
        done

        CARTES_TRIEES_MANCHE_COURANTE+=($MINIMUM_COURANT)
        supprimerValeur $INDEX_MINIMUM  # Supprime la carte triée de la liste non triée
    done

    echo "[LOGS] | Liste des cartes à trouver : ${CARTES_TRIEES_MANCHE_COURANTE[@]}"
}

# Fonction principale orchestrant toutes les étapes ci-dessus
function EnvoyerCartes() {
    initialiserCartes           # Étape 1 : Initialisation des cartes (1 à 100)
    melangerCartes              # Étape 2 : Mélange des cartes aléatoirement
    distribuerCartes            # Étape 3 : Distribution des cartes aux joueurs/robots
    envoyerNotificationDistribution  # Étape 4 : Notification de distribution des cartes
    trierCartes                # Étape 5 : Tri des cartes pour la manche courante
    echo "Manche : $MANCHE"
    EnvoyerMsgRobot "6" "$MANCHE"
}

function supprimerValeur() {
    # Supprime la carte à l'indice spécifié dans CARTES_NON_TRIEES_MANCHE_COURANTE
    INDEX_A_SUPPRIMER=$1
    TMP=()

    for ((i = 0; i <= INDEX_NON_TRIE; i++)); do
        if [ "$i" -ne "$INDEX_A_SUPPRIMER" ]; then
            TMP+=("${CARTES_NON_TRIEES_MANCHE_COURANTE[i]}")
        fi
    done
    CARTES_NON_TRIEES_MANCHE_COURANTE=()
    CARTES_NON_TRIEES_MANCHE_COURANTE=("${TMP[@]}")
}

#Fonction à utiliser pour afficher les cartes trouvées dans une partie
function mettreAJourCartesTrouvees() {
    # Préparation de l'affichage des cartes trouvées
    CARTES_TROUVEES="( "
    
    for ((x = 0; x <= INDEX_CARTE_COURANTE; x++)); do
        CARTES_TROUVEES+="${CARTES_TRIEES_MANCHE_COURANTE[x]} "
    done

    CARTES_TROUVEES+=")"
}

# Vérifie si le pipe nommé existe, sinon il est créé
function verifierOuCreerPipe() {
    if [[ ! -p "gestionJeu.pipe" ]]; then
        mkfifo gestionJeu.pipe
    fi
}

# Enregistre l'heure de début pour calculer le temps de réaction
function enregistrerHeureDebut() {
    HEURE_DEBUT=$(date +%s)
}

# Lit les données envoyées via le pipe
function lireCarteEntrante() {
    CARTE_ENTRANTE=$(cat gestionJeu.pipe)
}

# Calcule le temps de réaction
function calculerTempsReaction() {
    HEURE_FIN=$(date +%s)
    TEMPS_REACTION=$((HEURE_FIN - HEURE_DEBUT))
}

# Vérifie si un joueur a envoyé une commande pour quitter
function commandeQuitter() {
    if [[ "$CARTE_ENTRANTE" == "QUITTER" || "$CARTE_ENTRANTE" == "q" ]]; then
        echo "[INFO] | Un joueur a demandé l'arrêt du jeu."
        FinJeu  # Appelle la fonction pour terminer proprement le jeu
    fi
}

# Vérifie si la carte reçue est correcte ou non
function verifierCarteGagnante() {
    CARTE_GAGNANTE=${CARTES_TRIEES_MANCHE_COURANTE[INDEX_CARTE_COURANTE]}
    if [ "$CARTE_GAGNANTE" -eq "$CARTE_ENTRANTE" ]; then
        gererCarteCorrecte
    else
        gererCarteIncorrecte
    fi
}

# Gère les actions en cas de bonne carte jouée
function gererCarteCorrecte() {
    mettreAJourCartesTrouvees  # Met à jour les cartes trouvées
    echo "[INFO] | La carte $CARTE_ENTRANTE a été trouvée, voici les cartes trouvées : $CARTES_TROUVEES"
    EnvoyerMsgJoueur "1" "Bravo, une carte a été trouvée, voici les cartes trouvées : $CARTES_TROUVEES"
    CARTES_TROUVEES="${CARTES_TROUVEES// /,}" # Convertit en format CSV (4,5,7)
    EnvoyerMsgRobot "1" "$CARTES_TROUVEES"
    INDEX_CARTE_COURANTE+=1  # Passe à la carte suivante
    # Met à jour les statistiques avec succès = 1 (manche réussie)
    mettreAJourStatistiques "$MANCHE" "$CARTE_ENTRANTE" "$TEMPS_REACTION" 1
    sauvegarderDonneesIA
    gererFinDeTour  # Vérifie si toutes les cartes de la manche ont été trouvées
}

# Vérifie si toutes les cartes de la manche ont été trouvées et passe à la manche suivante ou termine le jeu
function gererFinDeTour() {
    if [ "$INDEX_CARTE_COURANTE" -eq $((MANCHE * NBJOUEURS + MANCHE * NBROBOT)) ]; then
        MANCHES_MAX=$((14 - 2 * (NBJOUEURS + NBROBOT - 1)))  # Calcul du nombre maximal de manches

        if [ "$MANCHE" -lt "$MANCHES_MAX" ]; then
            echo "[INFO] | La manche n°'$MANCHE' est terminée"
            EnvoyerMsgJoueur "3" "Félicitations, la manche n°'$MANCHE' est terminée, on passe à la manche suivante"

            MANCHE+=1  # Passe à la manche suivante

            EnvoyerCartes  # Mélange et distribue un nouveau jeu de cartes

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
    echo "[INFO] | La carte $CARTE_ENTRANTE n'était pas la bonne, la bonne était : $CARTE_GAGNANTE"
    
    EnvoyerMsgJoueur "2" "Perdu, la carte $CARTE_ENTRANTE n'était pas la bonne, la bonne était : $CARTE_GAGNANTE. On recommence !"
    EnvoyerMsgRobot "2" "message robot ignoré"
    # Met à jour les statistiques avec succès = 0 (manche échouée)
    mettreAJourStatistiques "$MANCHE" "$CARTE_ENTRANTE" "$TEMPS_REACTION" 0
    sauvegarderDonneesIA
    EnvoyerCartes  # Redistribue un nouveau jeu de cartes pour recommencer la manche
}

# Fonction principale orchestrant toutes les sous-fonctions ci-dessus
function EcouterPipe() {
    verifierOuCreerPipe         # Vérifie ou crée le pipe nommé
    enregistrerHeureDebut       # Enregistre l'heure de début
    lireCarteEntrante          # Lit les données envoyées via le pipe
    calculerTempsReaction      # Calcule le temps de réaction
    commandeQuitter           # Vérifie si un joueur a demandé à quitter
    verifierCarteGagnante    # Vérifie si la carte reçue est correcte ou non
    EcouterPipe              # Relance l'écoute pour attendre une nouvelle entrée (récursivité)
}

function EnvoyerMsgJoueur() {
    if [ "$NBJOUEURS" -gt 0 ]; then
        local ID_MSG=$1
        local MSG_A_ENVOYER=$2

        for ((x = 0; x < NBJOUEURS; x++)); do
            echo "$ID_MSG;$MSG_A_ENVOYER" > "$x.pipe"
        done
        echo "[LOGS] | L'action n°$ID_MSG a été envoyée aux joueurs humains"
    fi
}

function EnvoyerMsgRobot() {
    local ID_MSG=$1
    local MSG_A_ENVOYER=$2

    for ((x = NBJOUEURS; x < NBJOUEURS + NBROBOT; x++)); do
        echo "$ID_MSG;$MSG_A_ENVOYER" > "$x.pipe"
    done
    echo "[LOGS] | L'action n°$ID_MSG a été envoyée aux joueurs robots"
}

function supprimerAnciensFichiers(){
  # Supprime tous les pipes / tous les fichiers temporaires précédents
  # On envoie les messages d'erreurs vers null 
  # Cette redirection est justifiée par le fait que s'il n'existe pas de fichiers .tmp alors rm affiche une erreur
  rm .pipe 2>/dev/null
  rm *.tmp 2>/dev/null
  rm *.pipe 2>/dev/null
}

fichier_donnees="$SCRIPT_DIR/donnees_ia.csv"
function sauvegarderDonneesIA() {
    # Vérifier si le fichier existe déjà, sinon le créer avec l'en-tête
    if [ ! -e "$fichier_donnees" ]; then
    echo "fichier en création" 
        touch "$fichier_donnees" # Crée le fichier s'il n'existe pas
        echo "MANCHE,CARTE_ENTRANTE,CARTE_GAGNANTE,DISTANCE_CIBLE,TEMPS_REACTION,SUCCES,NBJOUEURS,NBROBOT,CARTES_TROUVEES,CARTES_ROBOT" > "$fichier_donnees"
    fi

    # Calculer la distance entre la carte jouée et la carte cible
    local distance_cible=$((CARTE_ENTRANTE - $CARTE_GAGNANTE))

    local cartes_courantes=""
    local fichier_robot="cartes_courantes_robot.txt"

    if [ -f "$fichier_robot" ]; then
        cartes_courantes=$(<"$fichier_robot")  # Lire tout le contenu du fichier dans une variable
    else
        echo "[ERREUR] | Le fichier $fichier_robot n'existe pas. Impossible de récupérer les cartes."
        cartes_courantes="Aucune carte disponible"
    fi

    # Ajouter les nouvelles données au fichier CSV
    local tableau_cartes_trouvees=(${CARTES_TROUVEES//[\(\)]/})
    echo "$MANCHE,$CARTE_ENTRANTE,$CARTE_GAGNANTE,$distance_cible,$TEMPS_REACTION,$SUCCES,$NBJOUEURS,$NBROBOT,\"${tableau_cartes_trouvees[*]}\",\"$cartes_courantes\"" >> "$fichier_donnees"
}

InitJoueurs
EnvoyerCartes
EcouterPipe