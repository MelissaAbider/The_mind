import pandas as pd
import numpy as np
import joblib
import sys
from sklearn.preprocessing import MultiLabelBinarizer

# Charger le modèle entraîné depuis un fichier
modele = joblib.load('modele_arbre_decision.joblib')

def valider_et_convertir_entier(valeur, nom):
    try:
        return int(valeur)
    except ValueError:
        print(f"Erreur : '{nom}' doit être un entier valide. Reçu : '{valeur}'")
        sys.exit(1)

# Extraire les paramètres depuis les arguments de la ligne de commande
numero_tour = valider_et_convertir_entier(sys.argv[1], "ROUND")
nb_joueurs_humains = valider_et_convertir_entier(sys.argv[2], "NBPLAYERS")
nb_robots = valider_et_convertir_entier(sys.argv[3], "NBROBOT")

# Traiter les cartes passées en arguments (actuelles et du robot)
try:
    cartes_actuelles = list(map(int, sys.argv[4].split(','))) if sys.argv[4] else []
    cartes_robot = list(map(int, sys.argv[5].split(','))) if sys.argv[5] else []
except ValueError as e:
    print(f"Erreur lors de la conversion des cartes : {e}")
    sys.exit(1)

# Encoder les cartes comme dans l'entraînement avec MultiLabelBinarizer
encodeur = MultiLabelBinarizer()
encodeur.fit(cartes_actuelles + cartes_robot)  # Ajuster sur toutes les cartes possibles

cartes_actuelles_encodees = encodeur.transform([cartes_actuelles])
cartes_robot_encodees = encodeur.transform([cartes_robot])

# Préparer les données pour la prédiction (combiner toutes les caractéristiques)
donnees_prediction = np.hstack(([numero_tour, nb_joueurs_humains, nb_robots],
                                cartes_actuelles_encodees.flatten(),
                                cartes_robot_encodees.flatten()))

# Faire une prédiction avec le modèle chargé
try:
    succes_prevu = modele.predict([donnees_prediction])[0]

    # Déterminer quelle carte jouer en fonction du succès prédit
    if cartes_robot:
        carte_a_jouer = min(cartes_robot) if succes_prevu == 1 else None
    else:
        carte_a_jouer = None

    if carte_a_jouer is not None:
        print(carte_a_jouer)
    else:
        print("Erreur : Aucune carte valide à jouer.")

except Exception as e:
    print(f"Erreur lors de la prédiction : {e}")
    sys.exit(1)

