# Lire le fichier config.json
$configJson = Get-Content -Raw -Path config.json | ConvertFrom-Json

# Extraire les variables du JSON
$INSTANCES = $configJson.INSTANCES;
$GPU_INSTANCES = $configJson.GPU_INSTANCES;
$GPUS_COUNT = $configJson.GPUS_COUNT;
$SHARED_PATH_HOST = $configJson.SHARED_PATH_HOST;
$CUSTOM_API_KEY = $configJson.CUSTOM_API_KEY;
$POSTGRES_USER = $configJson.POSTGRES_USER;
$POSTGRES_PASSWORD = $configJson.POSTGRES_PASSWORD;
$CREWAI_DB = $configJson.CREWAI_POSTGRES_DB;
$WEBUI_DB = $configJson.OPENWEBUI_POSTGRES_DB;
$WEBUI_USER = $configJson.OPENWEBUI_POSTGRES_USER;
$WEBUI_PASSWORD = $configJson.OPENWEBUI_POSTGRES_PASSWORD;
$RESTART = $configJson.RESTART_OPTION;
$WEBUI_DOCKER_TAG = "main";
if ($configJson.OPENWEBUI_DOCKER_TAG -ne "") {
  $WEBUI_DOCKER_TAG = $configJson.OPENWEBUI_DOCKER_TAG;
}
$WEBUI_AUTH = "False";
if ($configJson.OPENWEBUI_AUTH -ne "False") {
  $WEBUI_AUTH = "True";
}
$WEBUI_PORT = "3000";
if ($configJson.OPEN_WEBUI_PORT -ne "") {
  $WEBUI_PORT = $configJson.OPEN_WEBUI_PORT;
}

$CPULIMIT = $configJson.USABLE_CPU_CORES_COUNT;
$MEMLIMIT = $configJson.MEMORY_LIMIT;

# Vérifier si l'image Docker 'crewai-studio' existe localement
$imageExists = docker images -q crewai-studio
if (-not $imageExists) {
    Write-Output "L'image 'crewai-studio' n'existe pas localement. Clonage du dépôt et construction de l'image..."

    # Cloner le dépôt GitHub
    git clone https://github.com/strnad/CrewAI-Studio.git

    # Construire l'image Docker avec le nom 'crewai-studio'
    Set-Location -Path "CrewAI-Studio"
    docker build -t crewai-studio .

    # Supprimer le dossier CrewAI-Studio après la construction
    Set-Location -Path ".."
    Remove-Item -Recurse -Force "CrewAI-Studio"
} else {
    Write-Output "L'image 'crewai-studio' existe déjà localement."
}

# set config params
Write-Host "Voulez-vous ajouter une interaface pour acceder l'IA ? (y/n*)";
$confirmationUI = [System.Console]::ReadKey().Key.ToString();

# Initialiser le contenu du fichier docker-compose.yaml
$composeContent = @"
services:
  ollama:
    image: ollama/ollama:latest
    mem_limit: ${MEMLIMIT}
    cpu_count: ${CPULIMIT}
    restart: ${RESTART}
    ports:
      - "11434:11434"
    volumes:
      - ollama:/root/.ollama
      - ${SHARED_PATH_HOST}:/shared
"@
# Ajouter la configuration GPU si GPUS_COUNT est positif ou "all"
if ($GPUS_COUNT -gt 0) {
    $composeContent += @"

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
"@
}

#PG Sql
$composeContent += @"

  postgres-db:
    image: pgvector/pgvector:pg17
    restart: ${RESTART}
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${CREWAI_DB}
    ports:
      - "5432:5432"
    volumes:
      - postgres-data:/var/lib/postgresql/data
"@ 
if ($confirmationUI -eq 'y') {
  $composeContent += @"

      - ./init-user-db.sh:/docker-entrypoint-initdb.d/init-user-db.sh

"@
} else {
  $composeContent += @"

"@
}

#CREW AI
$composeContent += @"
  crewai-studio:
    image: crewai-studio
    restart: ${RESTART}
    ports:
      - "8501:8501"
    volumes:
      - crewai-data:/data
    environment:
      - DB_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres-db:5432/${CREWAI_DB}
      - OLLAMA_HOST=http://ollama:11434
      - OLLAMA_MODELS=$(($INSTANCES | ForEach-Object { "ollama/$_" }) -join ',')
    depends_on:
      - ollama
      - postgres-db

"@

# Add Open Web UI
if ($confirmationUI -eq 'y') {
    $composeContent += @"
  open-webui:
    image: ghcr.io/open-webui/open-webui:${WEBUI_DOCKER_TAG}
    volumes:
      - openwebui-data:/app/backend/data
    depends_on:
      - ollama
      - postgres-db
    ports:
      - ${WEBUI_PORT}:8080
    environment:
      - OLLAMA_API_BASE_URL=http://ollama:11434
      - OLLAMA_API_URL=http://ollama:11434
      - WEBUI_SECRET_KEY=${CUSTOM_API_KEY}
      - DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres-db:5432/${WEBUI_DB}
      - WEBUI_AUTH=${WEBUI_AUTH}
    restart: ${RESTART}
"@
}

$composeContent += @"


volumes:
  ollama:
  crewai-data:
  postgres-data:
"@
if ($confirmationUI -eq 'y') {
  $composeContent += @"

  openwebui-data:
"@
}


# Écrire le contenu dans le fichier docker-compose.yaml
$composeContent | Out-File -FilePath docker-compose.yaml -Encoding utf8

# création du fichier de configuration supplémentaire
if ($confirmationUI -eq 'y') {

  $composeSqlPG = @"
#!/bin/bash
psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" --dbname postgres <<-EOSQL
	CREATE USER ${WEBUI_USER} WITH PASSWORD '$WEBUI_PASSWORD';
	CREATE DATABASE ${WEBUI_DB};
	GRANT ALL PRIVILEGES ON DATABASE ${WEBUI_DB} TO ${WEBUI_USER};
  \c openwebui
  CREATE EXTENSION vector;
EOSQL
"@

$composeSqlPG | Out-File -FilePath init-user-db.sh -Encoding utf8
}

Write-Output "Fichier docker-compose.yaml genere avec succes !"

Write-Host "Voulez-vous lancer les conteneurs Docker et telecharger les models ? (y/n*)";
$confirmation = [System.Console]::ReadKey().Key.ToString();
if ($confirmation -eq 'y') {
    ./start_compose.ps1
}
