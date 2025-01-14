#!/bin/bash

DOSSIER_SCRIPT=$(dirname "$(realpath "$0")")
FICHIER_STATS="$DOSSIER_SCRIPT/stats.txt"
FICHIER_PDF="$DOSSIER_SCRIPT/stats.pdf"

function mettreAJourStatistiques() {
    MANCHE=$1
    CARTE_ENTRANTE=$2
    TEMPS_REACTION=$3
    REUSSITE=$4  # Indicateur de succès

    if [[ -z "$MANCHE" || -z "$CARTE_ENTRANTE" || -z "$TEMPS_REACTION" || -z "$REUSSITE" ]]; then
        echo "Erreur : arguments manquants pour mettreAJourStatistiques"
        return 1
    fi
    echo -e "$MANCHE\t$CARTE_ENTRANTE\t$TEMPS_REACTION\t$REUSSITE" >> "$FICHIER_STATS"
}

function genererGraphique() {
    awk '$4 == 1 {print $1}' "$FICHIER_STATS" | sort | uniq -c > "$DOSSIER_SCRIPT/donnees_reussite.txt"
    
    gnuplot <<- EOF
        set terminal png size 800,600
        set output "$DOSSIER_SCRIPT/manches_reussies.png"
        set title "Nombre de cartes réussies par manche"
        set xlabel "Manches"
        set ylabel "cartes réussies"
        plot "$DOSSIER_SCRIPT/donnees_reussite.txt" using 2:1 with linespoints title "Cartes réussies"
EOF
}

function genererHistogrammeCartesPerdues() {
    # Préparer les données pour un histogramme groupé
    awk '
    $4 == 0 { 
        # Ajouter la valeur de la carte perdue par manche
        valeurs[$1][$2] = $2    # Stocker la valeur de la carte perdue
        cartes[$2] = 1          # Enregistrer toutes les cartes uniques
    } 
    END {
        # Construire l’en-tête (les noms des colonnes correspondant aux cartes)
        printf "Manche"
        for (carte in cartes) {
            printf "\t%s", carte
        }
        printf "\n"

        # Construire les lignes avec les données agrégées par manche
        for (manche in valeurs) {
            printf "%s", manche
            for (carte in cartes) {
                # Afficher la valeur de la carte si elle a été perdue dans cette manche
                printf "\t%s", (valeurs[manche][carte] ? valeurs[manche][carte] : 0)
            }
            printf "\n"
        }
    }' "$FICHIER_STATS" > "$DOSSIER_SCRIPT/valeurs_ratees_par_manche_groupees.txt"

    # Générer l'histogramme avec Gnuplot
    gnuplot <<- EOF
        set terminal png size 800,600
        set output "$DOSSIER_SCRIPT/histogramme_valeurs_ratees_groupees.png"
        set title "Histogramme des valeurs des cartes perdues par manche"
        set xlabel "Manches"
        set ylabel "Valeurs des cartes perdues"
        set style data histograms
        set style histogram clustered gap 1
        set boxwidth 0.9 relative
        set style fill solid border -1
        set key autotitle columnhead
        set yrange [0:*]
        plot for [i=2:*] "$DOSSIER_SCRIPT/valeurs_ratees_par_manche_groupees.txt" using i:xtic(1) title columnheader(i)
EOF

    echo "Histogramme généré : $DOSSIER_SCRIPT/histogramme_valeurs_ratees_groupees.png"
}

function calculerTempsReactionMoyen() {
    # Vérifier si le fichier FICHIER_STATS existe et contient des données valides
    if [ ! -s "$FICHIER_STATS" ]; then
        echo "Erreur : Le fichier $FICHIER_STATS est vide ou n'existe pas."
        return 1
    fi

    # Calculer la moyenne du temps de réaction (colonne 3)
    moyenne=$(awk '{somme += $3; compteur++} END {if (compteur > 0) print somme / compteur; else print "N/A"}' "$FICHIER_STATS")

    # Afficher le résultat
    if [ "$moyenne" != "N/A" ]; then
        echo "Le temps de réaction moyen est : $moyenne secondes."
    else
        echo "Erreur : Impossible de calculer la moyenne (aucune donnée)."
    fi
}

function genererPDF() {
    # Vérifier si Pandoc est installé
    if ! command -v pandoc &> /dev/null; then
        echo "Erreur : Pandoc n'est pas installé. Installez-le pour générer le PDF."
        return 1
    fi

    # Définir les chemins des fichiers nécessaires
    FICHIER_MARKDOWN="$DOSSIER_SCRIPT/rapport_stats.md"
    FICHIER_PDF="$DOSSIER_SCRIPT/rapport_stats.pdf"

    # Étape 1 : Générer les graphiques et calculs nécessaires
    echo "Génération des graphiques et calculs..."
    if ! genererGraphique || ! genererHistogrammeCartesPerdues || ! calculerTempsReactionMoyen; then
        echo "Erreur : Échec lors de la génération des graphiques ou des calculs."
        return 1
    fi

    # Étape 2 : Construire le contenu du fichier Markdown
    echo "Création du fichier Markdown..."
    {
        # Titre principal
        echo "# Statistiques du Jeu"
        echo ""

        # Section 1 : Graphique des manches réussies
        echo "## 1. Graphique : Nombre de manches réussies"
        echo "![Nombre de manches réussies]($DOSSIER_SCRIPT/manches_reussies.png)"
        echo ""

        # Section 2 : Histogramme des cartes perdues par manche
        echo "## 2. Histogramme : Cartes perdues par manche"
        echo "![Cartes perdues par manche]($DOSSIER_SCRIPT/histogramme_valeurs_ratees_groupees.png)"
        echo ""

        # Section 3 : Temps de réaction moyen
        echo "## 3. Temps de réaction moyen"
        temps_reaction_moyen=$(awk '{somme += $3; compteur++} END {if (compteur > 0) print somme / compteur; else print "N/A"}' "$FICHIER_STATS")
        echo "- Le temps de réaction moyen est : **$temps_reaction_moyen secondes**."
        echo ""

        # Section 4 : Données brutes
        echo "## 4. Données brutes"
        echo "Les données utilisées pour générer les statistiques :"
        echo ""
        
        # Ajouter les données brutes formatées dans un tableau Markdown
        column -t -s $'\t' "$FICHIER_STATS" | sed 's/^/    /'
    } > "$FICHIER_MARKDOWN"

    # Étape 3 : Conversion du fichier Markdown en PDF avec Pandoc
    echo "Conversion du fichier Markdown en PDF..."
    pandoc "$FICHIER_MARKDOWN" -o "$FICHIER_PDF"

    # Vérifier si la conversion a réussi
    if [ $? -eq 0 ]; then
        echo "PDF généré avec succès : $FICHIER_PDF"
    else
        echo "Erreur lors de la génération du PDF."
        return 1
    fi
}
