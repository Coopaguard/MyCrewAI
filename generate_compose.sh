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
    if [[ ! -f "jq.exe" ]]; then
      # Installation de jq sur Windows
      echo "Téléchargement de jq pour Windows..."
      curl -L -o jq.exe https://github.com/jqlang/jq/releases/latest/download/jq-win64.exe

      # Vérifier si le téléchargement a réussi
      if [[ ! -f jq.exe ]]; then
          echo "Erreur lors du téléchargement de jq.exe."
          exit 1
      fi

      # Vérifier si le déplacement a réussi
      if [[ ! -f "./jq.exe" ]]; then
          echo "Erreur lors du déplacement de jq.exe."
          exit 1
      fi

      echo "jq a été installé avec succès."
    fi
  else
      echo "Système d'exploitation non pris en charge pour l'installation automatique de jq."
      exit 1
  fi
fi

#!/bin/bash

# Lire le fichier config.json
configJson=$(cat config.json)

# Extraire les variables du JSON

INSTANCES=$(./jq.exe -r '.INSTANCES[]' "config.json")
GPUS_COUNT=$(./jq.exe -r '.GPUS_COUNT' "config.json")
SHARED_PATH_HOST=$(./jq.exe -r '.SHARED_PATH_HOST' "config.json")
CUSTOM_API_KEY=$(./jq.exe -r '.CUSTOM_API_KEY' "config.json")
POSTGRES_USER=$(./jq.exe -r '.POSTGRES_USER' "config.json")
POSTGRES_PASSWORD=$(./jq.exe -r '.POSTGRES_PASSWORD' "config.json")
POSTGRES_DB=$(./jq.exe -r '.POSTGRES_DB' "config.json")
RESTART=$(./jq.exe -r '.RESTART_OPTION' "config.json")
WEBUI_DOCKER_TAG=$(./jq.exe -r '.WEBUI_DOCKER_TAG' "config.json")
WEBUI_PORT=$(./jq.exe -r '.WEBUI_PORT' "config.json")

if [[ -z "$WEBUI_DOCKER_TAG" ]]; then
    WEBUI_DOCKER_TAG="main"
fi
if [[ -z "$WEBUI_PORT" ]]; then
    WEBUI_PORT="3000"
fi

# Vérifier si l'image Docker 'crewai-studio' existe localement
imageExists=$(docker images -q crewai-studio)
if [ -z "$imageExists" ]; then
    echo "L'image 'crewai-studio' n'existe pas localement. Clonage du dépôt et construction de l'image..."

    # Cloner le dépôt GitHub
    git clone https://github.com/strnad/CrewAI-Studio.git

    # Construire l'image Docker avec le nom 'crewai-studio'
    cd CrewAI-Studio
    docker build -t crewai-studio .

    # Supprimer le dossier CrewAI-Studio après la construction
    cd ..
    rm -rf CrewAI-Studio
else
    echo "L'image 'crewai-studio' existe déjà localement."
fi

# Initialiser le contenu du fichier docker-compose.yaml
composeContent=$(cat <<EOF
services:
  ollama:
    image: ollama/ollama:latest
    restart: $RESTART
    ports:
      - "11434:11434"
    volumes:
      - ollama:/root/.ollama
      - $SHARED_PATH_HOST:/shared
EOF
)

# Ajouter la configuration GPU si GPUS_COUNT est positif ou "all"
if [[ "$GPUS_COUNT" -gt 0 ]]; then
    composeContent+=$(cat <<EOF

    environment:
      - NVIDIA_VISIBLE_DEVICES=all
      - NVIDIA_DRIVER_CAPABILITIES=compute,utility
      - CUDA_VISIBLE_DEVICES=0
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: $GPUS_COUNT
              capabilities: [gpu]
EOF
)
fi

$ln=$( IFS=$','; echo "${INSTANCES[*]}" )

echo  $ln;
ln=${ln//[$'\t\r\n ']};
echo  $ln;

composeContent+=$(cat <<EOF

  postgres-db:
    image: postgres:latest
    restart: ${RESTART}
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    ports:
      - "5432:5432"
    volumes:
      - postgres-data:/var/lib/postgresql/data
  crewai-studio:
    image: crewai-studio
    restart: ${RESTART}
    ports:
      - "8501:8501"
    volumes:
      - crewai-data:/data
    environment:
      - DB_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres-db:5432/${POSTGRES_DB}
      - OLLAMA_HOST=http://ollama:11434
      - OLLAMA_MODELS=$ln
    depends_on:
      - ollama
      - postgres-db
EOF
)

# Demander confirmation pour ajouter une interface pour accéder à l'IA
read -p "Voulez-vous ajouter une interface pour accéder à l'IA ? (y/n*)" confirmationUI
if [ "$confirmationUI" == "y" ]; then
    composeContent+=$(cat <<EOF

  open-webui:
    build:
      context: .
      args:
        OLLAMA_BASE_URL: '/ollama'
      dockerfile: Dockerfile
    image: ghcr.io/open-webui/open-webui:${WEBUI_DOCKER_TAG}
    container_name: open-webui
    volumes:
      - open-webui:/app/backend/data
    depends_on:
      - ollama
    ports:
      - ${WEBUI_PORT}:8080
    environment:
      - 'OLLAMA_BASE_URL=http://ollama:11434'
      - 'WEBUI_SECRET_KEY='
    extra_hosts:
      - host.docker.internal:host-gateway
    restart: ${RESTART}
EOF
)
fi

composeContent+=$(cat <<EOF

volumes:
  ollama:
  crewai-data:
  postgres-data:
EOF
)

if [ "$confirmationUI" == "y" ]; then
    composeContent+=$(cat <<EOF

  open-webui:
EOF
)
fi

# Écrire le contenu dans le fichier docker-compose.yaml
echo "$composeContent" > docker-compose.yaml

echo "Fichier docker-compose.yaml généré avec succès !"

# Demander confirmation pour lancer les conteneurs Docker et télécharger les modèles
read -p "Voulez-vous lancer les conteneurs Docker et télécharger les modèles ? (y/n*) " confirmation
if [ "$confirmation" == "y" ]; then
    ./start_compose.sh
fi
