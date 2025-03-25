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
$POSTGRES_DB = $configJson.POSTGRES_DB;
$RESTART = $configJson.RESTART_OPTION;
$WEBUI_DOCKER_TAG = "main";
if ($configJson.WEBUI_DOCKER_TAG -ne "") {
  $WEBUI_DOCKER_TAG = $configJson.WEBUI_DOCKER_TAG;
}
$WEBUI_PORT = "3000";
if ($configJson.OPEN_WEBUI_PORT -ne "") {
  $WEBUI_PORT = $configJson.OPEN_WEBUI_PORT;
}

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

# Initialiser le contenu du fichier docker-compose.yaml
$composeContent = @"
services:
  ollama:
    image: ollama/ollama:latest
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

$composeContent += @"

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
      - OLLAMA_MODELS=$(($INSTANCES | ForEach-Object { "ollama/$_" }) -join ',')
    depends_on:
      - ollama
      - postgres-db

"@

# 
Write-Host "Voulez-vous ajouter une interaface pour acceder l'IA ? (y/n*)";
$confirmationUI = [System.Console]::ReadKey().Key.ToString();
if ($confirmationUI -eq 'y') {
    $composeContent += @"
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

  open-webui:
"@
}


# Écrire le contenu dans le fichier docker-compose.yaml
$composeContent | Out-File -FilePath docker-compose.yaml -Encoding utf8


Write-Output "Fichier docker-compose.yaml genere avec succes !"

Write-Host "Voulez-vous lancer les conteneurs Docker et telecharger les models ? (y/n*)";
$confirmation = [System.Console]::ReadKey().Key.ToString();
if ($confirmation -eq 'y') {
    ./start_compose.ps1
}
