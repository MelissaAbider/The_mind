#!/bin/bash

SCRIPT_DIR=$(dirname "$(realpath "$0")")
STATS_FILE="$SCRIPT_DIR/stats.txt"
PDF_FILE="$SCRIPT_DIR/stats.pdf"

function updateStats() {
    ROUND=$1
    INCOMING_CARD=$2
    REACTION_TIME=$3
    SUCCESS=$4  # Indicateur de succès

    if [[ -z "$ROUND" || -z "$INCOMING_CARD" || -z "$REACTION_TIME" || -z "$SUCCESS" ]]; then
        echo "Erreur : arguments manquants pour updateStats"
        return 1
    fi
    echo -e "$ROUND\t$INCOMING_CARD\t$REACTION_TIME\t$SUCCESS" >> "$STATS_FILE"
}


function generateGraph() {
    awk '$4 == 1 {print $1}' "$STATS_FILE" | sort | uniq -c > "$SCRIPT_DIR/success_data.txt"
    
    gnuplot <<- EOF
        set terminal png size 800,600
        set output "$SCRIPT_DIR/manches_reussies.png"
        set title "Nombre de manches réussies par partie"
        set xlabel "Parties"
        set ylabel "Manches réussies"
        plot "$SCRIPT_DIR/success_data.txt" using 2:1 with linespoints title "Manches réussies"
EOF
}


function generateFailCardHistogram() {
    # Préparer les données pour un histogramme groupé
    awk '
    $4 == 0 { 
        # Ajouter la valeur de la carte perdue par manche
        values[$1][$2] = $2  # Stocker la valeur de la carte perdue
        cards[$2] = 1        # Enregistrer toutes les cartes uniques
    } 
    END {
        # Construire l’en-tête (les noms des colonnes correspondant aux cartes)
        printf "Round"
        for (card in cards) {
            printf "\t%s", card
        }
        printf "\n"

        # Construire les lignes avec les données agrégées par manche
        for (round in values) {
            printf "%s", round
            for (card in cards) {
                # Afficher la valeur de la carte si elle a été perdue dans cette manche
                printf "\t%s", (values[round][card] ? values[round][card] : 0)
            }
            printf "\n"
        }
    }' "$STATS_FILE" > "$SCRIPT_DIR/fail_values_per_round_grouped.txt"

    # Générer l'histogramme avec Gnuplot
    gnuplot <<- EOF
        set terminal png size 800,600
        set output "$SCRIPT_DIR/fail_value_grouped_histogram.png"
        set title "Histogramme des valeurs des cartes perdues par manche"
        set xlabel "Manches"
        set ylabel "Valeurs des cartes perdues"
        set style data histograms
        set style histogram clustered gap 1
        set boxwidth 0.9 relative
        set style fill solid border -1
        set key autotitle columnhead
        plot for [i=2:*] "$SCRIPT_DIR/fail_values_per_round_grouped.txt" using i:xtic(1) title columnheader(i)
EOF

    echo "Histogramme généré : $SCRIPT_DIR/fail_value_grouped_histogram.png"
}


function calculateAverageReactionTime() {
    # Vérifier si le fichier STATS_FILE existe et contient des données valides
    if [ ! -s "$STATS_FILE" ]; then
        echo "Erreur : Le fichier $STATS_FILE est vide ou n'existe pas."
        return 1
    fi

    # Calculer la moyenne du temps de réaction (colonne 3)
    average=$(awk '{sum += $3; count++} END {if (count > 0) print sum / count; else print "N/A"}' "$STATS_FILE")

    # Afficher le résultat
    if [ "$average" != "N/A" ]; then
        echo "Le temps de réaction moyen est : $average secondes."
    else
        echo "Erreur : Impossible de calculer la moyenne (aucune donnée)."
    fi
}

function generatePDF() {
    # Vérifier si Pandoc est installé
    if ! command -v pandoc &> /dev/null; then
        echo "Erreur : Pandoc n'est pas installé. Installez-le pour générer le PDF."
        return 1
    fi

    # Définir les chemins des fichiers nécessaires
    MARKDOWN_FILE="$SCRIPT_DIR/stats_report.md"
    PDF_FILE="$SCRIPT_DIR/stats_report.pdf"

    # Étape 1 : Générer les graphiques et calculs nécessaires
    echo "Génération des graphiques et calculs..."
    if ! generateGraph || ! generateFailCardHistogram || ! calculateAverageReactionTime; then
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
        echo "![Nombre de manches réussies]($SCRIPT_DIR/manches_reussies.png)"
        echo ""

        # Section 2 : Histogramme des cartes perdues par manche
        echo "## 2. Histogramme : Cartes perdues par manche"
        echo "![Cartes perdues par manche]($SCRIPT_DIR/fail_value_grouped_histogram.png)"
        echo ""

        # Section 3 : Temps de réaction moyen
        echo "## 3. Temps de réaction moyen"
        average_reaction_time=$(awk '{sum += $3; count++} END {if (count > 0) print sum / count; else print "N/A"}' "$STATS_FILE")
        echo "- Le temps de réaction moyen est : **$average_reaction_time secondes**."
        echo ""

        # Section 4 : Données brutes
        echo "## 4. Données brutes"
        echo "Les données utilisées pour générer les statistiques :"
        echo ""
        
        # Ajouter les données brutes formatées dans un tableau Markdown
        column -t -s $'\t' "$STATS_FILE" | sed 's/^/    /'
    } > "$MARKDOWN_FILE"

    # Étape 3 : Conversion du fichier Markdown en PDF avec Pandoc
    echo "Conversion du fichier Markdown en PDF..."
    pandoc "$MARKDOWN_FILE" -o "$PDF_FILE"

    # Vérifier si la conversion a réussi
    if [ $? -eq 0 ]; then
        echo "PDF généré avec succès : $PDF_FILE"
    else
        echo "Erreur lors de la génération du PDF."
        return 1
    fi
}

