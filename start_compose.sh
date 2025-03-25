#!/bin/bash

# Lire le fichier config.json
configJson=$(cat config.json)

# Extraire les variables du JSON
INSTANCES=$(./jq.exe -r '.INSTANCES[]' "config.json")
SHARED_PATH_HOST=$(./jq.exe -r '.SHARED_PATH_HOST' "config.json")

echo $SHARED_PATH_HOST;

# shared=${SHARED_PATH_HOST/C://c};
# echo $shared
# Créer les dossiers input et output s'ils n'existent pas
mkdir $SHARED_PATH_HOST;

# Lancer docker-compose en arrière-plan
docker-compose up -d

# Attendre 10 secondes pour s'assurer que tous les conteneurs sont démarrés
echo "Attente de 10 secondes pour s'assurer que tous les conteneurs sont démarrés..."
sleep 10

# Envoyer une requête HTTP POST pour chaque modèle
port=11434
queryUrl="http://localhost:$port/api/pull"

# Supposons que les instances soient définies dans un tableau
for instance in "${INSTANCES[@]}"; do
    instance=$(echo "$instance" | tr -d '\r')
    queryBody='{model: '.$instance.'}'

    echo "Téléchargement du modèle: $instance"

    # Envoyer la requête POST
    curl -X POST "$queryUrl" -H "Content-Type: application/json" -d "$queryBody"
done

echo "Initialisation des conteneurs terminée."
