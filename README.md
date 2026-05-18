# Coolify AI Suite

**Environnement de développement IA auto-hébergé** — Déployez votre stack IA en une commande.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-2.2.0-green)](CHANGELOG.md)
[![CI Tests](https://github.com/HiTechTN/coolify-ai-suite/actions/workflows/ci.yml/badge.svg)](https://github.com/HiTechTN/coolify-ai-suite/actions/workflows/ci.yml)

---

## Services

| Service | Rôle | Accès par défaut |
|---------|------|------------------|
| **Coolify** | Orchestrateur de déploiement (PaaS) | `http://IP:8000` |
| **Code-Server** | VS Code dans le navigateur | `http://IP:8443` |
| **Ollama** | Moteur de modèles LLM locaux | `http://IP:11434` |
| **Open WebUI** | Interface de chat IA | `http://IP:3000` |

> Avec un domaine configuré : `https://coolify.votredomaine.tn`, `https://code.votredomaine.tn`, etc.

---

## Quick Start

```bash
sudo ./setup-ai-suite.sh
```

Le script interactif vous guide :
1. Choix des services à installer
2. Configuration personnalisée des ports et du domaine
3. Installation automatique (Docker, pare-feu, HTTPS)
4. Génération de mots de passe sécurisés

**Prérequis :** Ubuntu/Debian, 4 Go RAM, 20 Go disque, accès root

---

## Scripts

| Script | Usage |
|--------|-------|
| `setup-ai-suite.sh` | Installation complète (menu interactif) |
| `setup-domain.sh` | Ajouter un nom de domaine + SSL à une installation existante |
| `setup-traefik-only.sh` | Ajouter HTTPS/Traefik uniquement |
| `check-ai-suite-status.sh` | Vérifier l'état des services |
| `install-ollama-models.sh` | Télécharger des modèles IA (qwen2.5-coder, llama3.2, etc.) |
| `backup-ai-suite.sh` | Sauvegarder / restaurer l'installation |

```bash
# Exemples
sudo ./check-ai-suite-status.sh
sudo ./install-ollama-models.sh
sudo ./backup-ai-suite.sh backup
sudo ./backup-ai-suite.sh restore backup_20260425.tar.gz
```

---

## Configuration Domaine

Liez un nom de domaine réel (ex: `hitech.tn`) avec SSL automatique Let's Encrypt.

### Architecture

```
*.votredomaine.tn → Serveur → Traefik (HTTPS)
├── coolify.votredomaine.tn  → Coolify
├── code.votredomaine.tn     → Code-Server
├── chat.votredomaine.tn     → Open WebUI
├── ollama.votredomaine.tn   → Ollama
└── donbosco.votredomaine.tn → Don Bosco (si installé)
```

### DNS

| Type | Nom | Valeur |
|------|-----|--------|
| A | `votredomaine.tn` | IP du serveur |
| A | `*.votredomaine.tn` | IP du serveur |

### Nouvelle installation

```bash
sudo ./setup-ai-suite.sh
# Menu → [C] Configuration personnalisée → saisir le domaine
```

### Installation existante

```bash
sudo ./setup-domain.sh
```

### Nouveaux projets Docker

Ajoutez ces labels à votre `docker-compose.yml` :

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.monprojet.rule=Host(\`monprojet.votredomaine.tn\`)"
  - "traefik.http.routers.monprojet.tls=true"
  - "traefik.http.routers.monprojet.entrypoints=websecure"
```

---

## Variables d'environnement

Fichier `.env` généré automatiquement (cf. `.env.example`).

| Variable | Description | Défaut |
|----------|-------------|--------|
| `DOMAIN` | Nom de domaine | *(vide = .local)* |
| `SSL_EMAIL` | Email Let's Encrypt | `admin@example.com` |
| `COOLIFY_PORT` | Port Coolify | `8000` |
| `CODE_SERVER_PORT` | Port Code-Server | `8443` |
| `OPEN_WEBUI_PORT` | Port Open WebUI | `3000` |
| `OLLAMA_PORT` | Port Ollama | `11434` |
| `BACKUP_DIR` | Dossier de sauvegarde | `/opt/backups/ai-suite` |
| `RETENTION_DAYS` | Jours de rétention | `7` |

---

## Maintenance

```bash
# Logs d'un service
docker logs -f code-server

# Redémarrer un service
cd /opt/ai-suite/code-server && docker compose restart

# Nettoyage Docker
docker system prune -af

# Sauvegardes automatiques (cron) : tous les jours à 3h00
crontab -l
```

---

## Structure

```
/opt/ai-suite/
├── code-server/          # VS Code dans le navigateur
│   ├── docker-compose.yml
│   ├── config/
│   └── projects/
├── ollama/               # Moteur LLM
│   └── docker-compose.yml
├── open-webui/           # Interface de chat
│   └── docker-compose.yml
├── traefik/              # Proxy inverse HTTPS
│   ├── docker-compose.yml
│   ├── traefik.yml
│   └── config/
├── backup.sh
├── cleanup.sh
└── .env
```

---

## Ressources

- [Coolify](https://coolify.io/docs) — Documentation officielle
- [Ollama](https://ollama.com/library) — Bibliothèque de modèles
- [Open WebUI](https://github.com/open-webui/open-webui) — Interface de chat
- [Code-Server](https://github.com/coder/code-server) — VS Code distant

---

## Auteur

**Mohamed Azmi KAANICHE** — [HiTechTN](https://github.com/HiTechTN)

Licence MIT — Voir [LICENSE](LICENSE) et [CHANGELOG](CHANGELOG.md).
