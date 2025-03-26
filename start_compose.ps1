# Lire le fichier config.json
$configJson = Get-Content -Raw -Path config.json | ConvertFrom-Json
$SHARED_PATH_HOST = $configJson.SHARED_PATH_HOST


# Créer les dossier input et output s'ils n'éxiste pas
# if (-not (Test-Path -Path $SHARED_PATH_HOST_INPUT)) {
#     New-Item -ItemType Directory -Force -Path $SHARED_PATH_HOST_INPUT
# }
if (-not (Test-Path -Path $SHARED_PATH_HOST)) {
    New-Item -ItemType Directory -Force -Path $SHARED_PATH_HOST
}

# Lancer docker-compose en arrière-plan
docker-compose up -d

# Attendre 10 secondes pour s'assurer que tous les conteneurs sont démarrés
Write-Output "Attente de 10 secondes pour s'assurer que tous les conteneurs sont démarrés..."
Start-Sleep -Seconds 10

# Envoyer une requête HTTP POST pour chaque modèle
$port = 11434
$queryUrl = "http://localhost:$port/api/pull"

for ($index = 0; $index -lt $INSTANCES.Length; $index++) {
    $instance = $INSTANCES[$index] -replace "`r",""
    $queryBody = [PSCustomObject]@{model=$instance} | ConvertTo-Json

    Write-Output "Téléchargement du modèle: $instance"

    # Envoyer la requête POST
    Invoke-RestMethod -Uri $queryUrl -Method Post -ContentType "application/json" -Body $queryBody
}

Write-Output "Initialisation des conteneurs terminée."