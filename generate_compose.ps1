# Lire le fichier config.json
$configJson = Get-Content -Raw -Path config.json | ConvertFrom-Json

# Extraire les variables du JSON
$INSTANCES = $configJson.INSTANCES
$GPU_INSTANCES = $configJson.GPU_INSTANCES
$GPUS_COUNT = $configJson.GPUS_COUNT
$SHARED_PATH_HOST = $configJson.SHARED_PATH_HOST
$CUSTOM_API_KEY = $configJson.CUSTOM_API_KEY
$POSTGRES_USER = $configJson.POSTGRES_USER
$POSTGRES_PASSWORD = $configJson.POSTGRES_PASSWORD
$POSTGRES_DB = $configJson.POSTGRES_DB

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
    restart: unless-stopped
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
    restart: unless-stopped
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
    restart: unless-stopped
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

volumes:
  ollama:
  crewai-data:
  postgres-data:
"@

# Écrire le contenu dans le fichier docker-compose.yaml
$composeContent | Out-File -FilePath docker-compose.yaml -Encoding utf8

Write-Output "Fichier docker-compose.yaml généré avec succès !"

$confirmation = Read-Host "Voulez-vous lancer les conteneurs Docker et télécharger les models ? (y/n)"
if ($confirmation -eq 'y') {
    ./start_compose.ps1
}
