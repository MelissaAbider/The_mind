import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.tree import DecisionTreeClassifier
from sklearn.metrics import accuracy_score
from sklearn.preprocessing import MultiLabelBinarizer
import joblib
import numpy as np
#source projet/bin/activate pour pouvoir lancer l'entrenement sans devoir installer les bibiotheques localement 
# Charger les données d'entraînement à partir d'un fichier CSV
donnees = pd.read_csv('donnees_ia.csv')

# Fonction pour convertir les chaînes de cartes en listes d'entiers
def convertir_en_liste(chaine):
    try:
        if isinstance(chaine, str):
            # Nettoyer la chaîne et convertir en liste d'entiers
            nettoye = chaine.strip().replace(',', ' ').split()
            return list(map(int, nettoye)) if nettoye else []
        else:
            # Si ce n'est pas une chaîne, retourner une liste vide
            return []
    except Exception as e:
        print(f"Erreur lors de la conversion : {e}")
        return []

# Remplacer les valeurs NaN par des chaînes vides pour éviter les erreurs
donnees['CARTES_ACTUELLES'] = donnees['CARTES_TROUVEES'].fillna('')
donnees['CARTES_ROBOT'] = donnees['CARTES_ROBOT'].fillna('')

# Appliquer la conversion sur les colonnes des cartes
donnees['LISTE_CARTES_ACTUELLES'] = donnees['CARTES_ACTUELLES'].apply(convertir_en_liste)
donnees['LISTE_CARTES_ROBOT'] = donnees['CARTES_ROBOT'].apply(convertir_en_liste)

# Vérifier si toutes les lignes ont été correctement converties
print(donnees[['CARTES_ACTUELLES', 'LISTE_CARTES_ACTUELLES', 'CARTES_ROBOT', 'LISTE_CARTES_ROBOT']].head())

# Encoder le contenu des listes en vecteurs binaires
encodeur = MultiLabelBinarizer()
cartes_actuelles_encodees = encodeur.fit_transform(donnees['LISTE_CARTES_ACTUELLES'])
cartes_robot_encodees = encodeur.fit_transform(donnees['LISTE_CARTES_ROBOT'])

# Combiner ces encodages avec les autres caractéristiques
caracteristiques = np.hstack((donnees[['MANCHE', 'CARTE_ENTRANTE', 'CARTE_GAGNANTE',
                                       'DISTANCE_CIBLE', 'TEMPS_REACTION',
                                       'NBJOUEURS', 'NBROBOT']].values,
                              cartes_actuelles_encodees,
                              cartes_robot_encodees))

# Définir la cible (target) pour l'entraînement du modèle
cible = donnees['SUCCES']

# Diviser les données en ensembles d'entraînement et de test (80% entraînement, 20% test)
X_train, X_test, y_train, y_test = train_test_split(caracteristiques, cible, test_size=0.2, random_state=42)

# Créer et entraîner un modèle d'arbre de décision avec une profondeur maximale de 5
modele = DecisionTreeClassifier(max_depth=5, random_state=42)
modele.fit(X_train, y_train)

# Évaluer le modèle sur l'ensemble de test et calculer la précision
y_pred = modele.predict(X_test)
precision = accuracy_score(y_test, y_pred)
print(f"Précision : {precision:.2f}")

# Sauvegarder le modèle entraîné dans un fichier pour une utilisation ultérieure
joblib.dump(modele, 'modele_arbre_decision.joblib')
print("Modèle enregistré dans 'modele_arbre_decision.joblib'")

