# CrewAI Studio && Ollama fast setup with docker

## Docker Compose Setup Scripts

This repository contains scripts to automate the setup and configuration of Docker Compose for a specific application environment. The scripts handle the creation of a `docker-compose.yaml` file, the installation of necessary tools, and the deployment of Docker containers.

### Purpose

The primary purpose of these scripts is to streamline the process of setting up a Docker environment with multiple services, including:

- **Ollama Instances**: Multiple instances of the Ollama service, each configured with specific models.
- **CrewAI Studio**: A service that requires a PostgreSQL database.
- **PostgreSQL Database**: A database service to support CrewAI Studio.

### Prerequisites

- Docker and Docker Compose must be installed on your system.
- Git must be installed to clone the necessary repositories.
- For Windows users, Git Bash or a similar Bash environment is recommended.

### How To

Simply run script generate_compose.sh(or .ps1 on windows)
- you cloud accept auto strep witch will call (http://ollama:$port/api/pull [POST] body: {model=modelName(ex:llama3.2)})

After setup completed simply open you're browser on: [http://localhost:8501/](http://localhost:8501/) (CrewAI-Studio Instance)

### Configuration

The configuration for the Docker Compose setup is managed through a `config.json` file. Below is an example of how this file should be structured:

```json
{
  "INSTANCES": ["mistral:7b", "codestral:22b-v0.1-q3_K_S", ...(any oLlama model)],
  "GPUS_COUNT": 0 // or 1/2/3/... to authorise Ollama use some GPUs or "all" to use all gpus
  "SHARED_PATH_HOST": "C:/MyCrew/shared",
  "CUSTOM_API_KEY": "",
  "POSTGRES_USER": "crewaiuser",
  "POSTGRES_PASSWORD": "secret123",
  "POSTGRES_DB": "crewai"
}
```
liste of Ollama models: [Ollama models](https://ollama.com/search)

### Dependencies

- [CrewAI Studio (GitHub)](https://github.com/strnad/CrewAI-Studio)
- [Ollama](https://ollama.com/)


### Update to newer versino of CrewAI-Studio

if you want force the update to thelastest version of CrewAI-Studio, delete the CrewAI-Studio image from your docker images this will force the script to clone and build the lastest version