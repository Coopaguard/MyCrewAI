#!/bin/bash

# Vérifier si jq est installé, sinon l'installer
if ! command -v jq &>/dev/null; then
  echo "jq n'est pas installé. Installation en cours..."
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
      if command -v apt-get &>/dev/null; then
          sudo apt-get update && sudo apt-get install -y jq
      elif command -v yum &>/dev/null; then
          sudo yum install -y jq
      else
          echo "Veuillez installer jq manuellement."
          exit 1
      fi
  elif [[ "$OSTYPE" == "cygwin" || "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
      # Installation de jq sur Windows
      echo "Téléchargement de jq pour Windows..."
      curl -L -o jq.exe https://github.com/jqlang/jq/releases/latest/download/jq-win64.exe

      # Vérifier si le téléchargement a réussi
      if [[ ! -f jq.exe ]]; then
          echo "Erreur lors du téléchargement de jq.exe."
          exit 1
      fi

      echo "Déplacement de jq dans le répertoire cible..."
      mv jq.exe "/c/Program Files/Git/usr/bin/jq.exe"

      # Vérifier si le déplacement a réussi
      if [[ ! -f "/c/Program Files/Git/usr/bin/jq.exe" ]]; then
          echo "Erreur lors du déplacement de jq.exe."
          exit 1
      fi

      echo "jq a été installé avec succès."
  else
      echo "Système d'exploitation non pris en charge pour l'installation automatique de jq."
      exit 1
  fi
fi

# Lire le fichier config.json
config_json=$(cat config.json)

# Extraire les variables du JSON
INSTANCES=$(echo $config_json | jq -r '.INSTANCES[]')
GPUS_COUNT=$(echo $config_json | jq -r '.GPUS_COUNT')
SHARED_PATH_HOST=$(echo $config_json | jq -r '.SHARED_PATH_HOST')
CUSTOM_API_KEY=$(echo $config_json | jq -r '.CUSTOM_API_KEY')
POSTGRES_USER=$(echo $config_json | jq -r '.POSTGRES_USER')
POSTGRES_PASSWORD=$(echo $config_json | jq -r '.POSTGRES_PASSWORD')
POSTGRES_DB=$(echo $config_json | jq -r '.POSTGRES_DB')

# Vérifier si l'image Docker 'crewai-studio' existe localement
if ! docker images | grep -q 'crewai-studio'; then
    echo "L'image 'crewai-studio' n'existe pas localement. Clonage du dépôt et construction de l'image..."

    # Cloner le dépôt GitHub
    git clone https://github.com/strnad/CrewAI-Studio.git

    # Construire l'image Docker avec le nom 'crewai-studio'
    cd CrewAI-Studio || exit
    docker build -t crewai-studio .

    # Supprimer le dossier CrewAI-Studio après la construction
    cd ..
    rm -rf CrewAI-Studio
else
    echo "L'image 'crewai-studio' existe déjà localement."
fi

# Initialiser le contenu du fichier docker-compose.yaml
compose_content="version: '3.8'\n\nservices:\n"

# Ajouter le service Ollama au docker-compose
compose_content+="
  ollama:
    image: ollama/ollama:latest
    environment:
      - OLLAMA_API_KEY=${CUSTOM_API_KEY}
    ports:
      - \"11434:11434\"
    volumes:
      - ollama:/root/.ollama
      - ${SHARED_PATH_HOST}:/shared
"

# Ajouter la configuration GPU si GPUS_COUNT est positif ou "all"
if [[ "$GPUS_COUNT" -gt 0 || "$GPUS_COUNT" == "all" ]]; then
    compose_content+="
      - NVIDIA_VISIBLE_DEVICES=all
      - NVIDIA_DRIVER_CAPABILITIES=compute,utility
      - CUDA_VISIBLE_DEVICES=0
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia"

    if [[ "$GPUS_COUNT" == "all" ]]; then
        compose_content+="\n              count: all"
    else
        compose_content+="\n              count: $GPUS_COUNT"
    fi

    compose_content+="\n              capabilities: [gpu]"
fi

# Transformer la liste des instances pour le format souhaité
OLLAMA_MODELS=$(echo $INSTANCES | tr ' ' '\n' | awk '{print "ollama/"$0}' | paste -sd, -)

# Ajouter le service crewai-studio au docker-compose
compose_content+="\n  crewai-studio:\n"
compose_content+="    image: crewai-studio\n"
compose_content+="    ports:\n"
compose_content+="      - \"8501:8501\"\n"
compose_content+="    volumes:\n"
compose_content+="      - crewai-data:/data\n"
compose_content+="    environment:\n"
compose_content+="      - DB_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@db:5432/${POSTGRES_DB}\n"
compose_content+="      - OLLAMA_HOST=http://ollama:11434\n"
compose_content+="      - OLLAMA_MODELS=${OLLAMA_MODELS}\n"
compose_content+="    depends_on:\n"
compose_content+="      - ollama\n"

# Ajouter le service PostgreSQL au docker-compose
compose_content+="\n  db:\n"
compose_content+="    image: postgres:latest\n"
compose_content+="    environment:\n"
compose_content+="      POSTGRES_USER: ${POSTGRES_USER}\n"
compose_content+="      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}\n"
compose_content+="      POSTGRES_DB: ${POSTGRES_DB}\n"
compose_content+="    ports:\n"
compose_content+="      - \"5432:5432\"\n"
compose_content+="    volumes:\n"
compose_content+="      - postgres-data:/var/lib/postgresql/data\n"

compose_content+="\nvolumes:\n  ollama:\n  crewai-data:\n  postgres-data:\n"

# Écrire le contenu dans le fichier docker-compose.yaml
echo -e "$compose_content" > docker-compose.yaml

echo "Fichier docker-compose.yaml généré avec succès !"

# Demander confirmation pour lancer les conteneurs
read -p "Voulez-vous lancer les conteneurs Docker et télécharger les modèles ? (y/n) " confirmation
if [[ "$confirmation" == "y" ]]; then
    # Lancer docker-compose en arrière-plan
    docker-compose up -d

    # Attendre 10 secondes pour s'assurer que tous les conteneurs sont démarrés
    echo "Attente de 10 secondes pour s'assurer que tous les conteneurs sont démarrés..."
    sleep 10

    # Envoyer une requête HTTP POST pour chaque modèle
    port=11434
    queryUrl="http://localhost:$port/api/pull"

    for instance in $INSTANCES; do
        instance=$(echo $instance | tr -d '\r')
        queryBody=$(jq -n --arg model "$instance" '{"model": $model}')

        echo "Téléchargement du modèle: $instance"

        # Envoyer la requête POST
        curl -s -o /dev/null -X POST $queryUrl -H "Content-Type: application/json" -d "$queryBody"
    done

    echo "Initialisation des conteneurs terminée."
fi
