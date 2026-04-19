# Ontology Practice

This repository contains practice materials for the Ontology Lecture, including multiple Neo4j datasets managed as git submodules.

## Prerequisites

- Git
- Docker
- Docker Compose

## Cloning the Repository

To clone this repository along with all included submodules, perform the following command:

```bash
git clone --recursive git@github.com:seonwookim92/ontology-lecture.git
```

If you have already cloned the repository without submodules, you can initialize them using:

```bash
git submodule update --init --recursive
```

## Environment Configuration

The project requires a `.env` file to specify the active dataset.

1. Create a `.env` file from the provided sample:
   ```bash
   cp .env.sample .env
   ```

2. Open the `.env` file and set the `ACTIVE_DATASET` variable to one of the following available datasets:
   - `stackoverflow`
   - `pole`
   - `network-management`
   - `recommendations`

Example `.env` content:
```env
ACTIVE_DATASET=recommendations
```

## Running the Application

Start the Neo4j instance using Docker Compose:

```bash
docker-compose up -d
```

Once the container is running:
- The Neo4j Browser is available at: [http://localhost:7474](http://localhost:7474)
- Bolt protocol is exposed at: `bolt://localhost:7687`

The default authentication is configured as:
- Username: `neo4j`
- Password: `testpassword`

## Project Structure

- `dataset/`: Contains datasets as git submodules.
- `neo4j/`: Persistent storage for databases, logs, and plugins.
- `cypher/`: Collection of Cypher queries for practice.
- `neo4j_init.sh`: Custom entrypoint script for initializing datasets.
