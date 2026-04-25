# Coolify AI Suite - Guide d'utilisation

## Vue d'ensemble

Environnement de développement complet avec Intelligence Artificielle auto-hébergé, comprenant :
- **Coolify** - Orchestrateur de déploiement
- **Code-Server** - IDE Visual Studio Code dans le navigateur
- **Ollama** - Moteur d'exécution de modèles LLM locaux
- **Open WebUI** - Interface de chat pour interagir avec les IA

---

## URLs d'accès

| Service | URL | Status |
|---------|-----|--------|
| **Coolify** | http://IP:8000 | ✅ Actif |
| **Code-Server** | http://IP:8443 | ✅ Actif |
| **Open WebUI** | http://IP:3000 | ✅ Actif |
| **Ollama API** | http://IP:11434 | ✅ Actif |

> Note: Remplacez `IP` par l'adresse IP de votre serveur

---

## Scripts disponibles

| Script | Description |
|--------|-------------|
| `setup-ai-suite.sh` | Installation complète de l'environnement |
| `check-ai-suite-status.sh` | Vérifier l'état des services |
| `install-ollama-models.sh` | Installer les modèles IA |
| `backup-ai-suite.sh` | Sauvegarder / restaurer les données |

### Utilisation des scripts

```bash
# Installation
sudo ~/Coolify\ AI\ Suite/setup-ai-suite.sh

# Vérifier l'état
sudo ~/Coolify\ AI\ Suite/check-ai-suite-status.sh

# Installer les modèles
sudo ~/Coolify\ AI\ Suite/install-ollama-models.sh

# Sauvegarder
sudo ~/Coolify\ AI\ Suite/backup-ai-suite.sh backup

# Lister les sauvegardes
sudo ~/Coolify\ AI\ Suite/backup-ai-suite.sh list

# Restaurer
sudo ~/Coolify\ AI\ Suite/backup-ai-suite.sh restore ai-suite_20260425_120000.tar.gz
```

---

## Installation rapide

### 1. Prérequis

- Serveur Ubuntu/Debian (64-bit)
- Minimum 4GB RAM
- 20GB espace disque
- Docker installé

### 2. Lancement de l'installation

```bash
cd ~/Coolify\ AI\ Suite
chmod +x setup-ai-suite.sh
sudo ./setup-ai-suite.sh
```

Le script propose :
- Menu interactif pour choisir les services
- Configuration personnalisée des ports
- Validation des prérequis système
- Configuration automatique du pare-feu
- Génération de mots de passe sécurisés
- Sauvegarde automatique quotidienne

---

## Configuration

### Fichier .env

La configuration est exportée dans `.env` :

```bash
OLLAMA_PORT=11434
CODE_SERVER_PORT=8443
OPEN_WEBUI_PORT=3000
COOLIFY_PORT=8000
CODE_SERVER_PASSWORD=votre_mot_de_passe
WEBUI_SECRET=votre_secret
```

### Variables d'environnement

| Variable | Description | Défaut |
|----------|-------------|--------|
| `OLLAMA_PORT` | Port API Ollama | 11434 |
| `CODE_SERVER_PORT` | Port Code-Server | 8443 |
| `OPEN_WEBUI_PORT` | Port Open WebUI | 3000 |
| `COOLIFY_PORT` | Port Coolify | 8000 |
| `CODE_SERVER_PASSWORD` | Mot de passe Code-Server | Auto-généré |
| `BACKUP_DIR` | Dossier de sauvegarde | /opt/backups/ai-suite |
| `RETENTION_DAYS` | Jours de rétention backup | 7 |

---

## Services

### Coolify

Plateforme de déploiement auto-hébergée.

```bash
# Accéder à l'interface
http://IP:8000
```

### Code-Server

IDE Visual Studio Code dans le navigateur.

```bash
# Accéder à l'interface
http://IP:8443

# Volumes
- /config: Configuration
- /projects: Espace de travail
```

### Ollama

Moteur de modèles LLM locaux.

```bash
# Vérifier les modèles
curl http://localhost:11434/api/tags | jq

# Tester un modèle
curl http://localhost:11434/api/generate -d '{
  "model": "qwen2.5-coder:3b",
  "prompt": "Hello!",
  "stream": false
}'
```

### Open WebUI

Interface de chat pour Ollama.

```bash
# Accéder à l'interface
http://IP:3000
```

---

## Modèles IA recommandés

| Modèle | Taille | Usage |
|--------|--------|-------|
| `qwen2.5-coder:3b` | ~2GB | Génération de code |
| `deepseek-coder-v2:16b-lite` | ~9GB | Code avancé |
| `phi3:3.8b` | ~2.3GB | Polyvalent |
| `llama3.2:3b` | ~2GB | Conversation |

---

## Dépannage

### Services qui ne démarrent pas

```bash
# Vérifier les logs
docker logs code-server
docker logs ollama
docker logs open-webui

# Redémarrer un service
cd /opt/ai-suite/code-server
docker compose down && docker compose up -d
```

### Port occupé

```bash
# Identifier le processus
sudo ss -tuln | grep PORT

# Voir ce qui utilise le port
sudo lsof -i :PORT
```

### Problème de connexion Ollama-WebUI

```bash
# Vérifier le réseau
docker network inspect ai-suite

# Redémarrer les deux services
docker restart ollama open-webui
```

### Libérer de l'espace disque

```bash
# Nettoyage standard
docker system prune -af

# Nettoyage complet
/opt/ai-suite/cleanup.sh
```

---

## Sécurité

### Pare-feu (UFW)

Ports ouverts automatiquement :
- SSH (22)
- HTTP (80)
- HTTPS (443)
- Coolify (8000)
- Code-Server (8443)
- Ollama (11434)
- Open WebUI (3000)

### Fail2Ban

Protection contre les attaques par force brute.

```bash
sudo fail2ban-client status
sudo fail2ban-client status sshd
```

### Recommandations

1. Changez les mots de passe par défaut
2. Activez HTTPS avec Traefik
3. Sauvegardez régulièrement (`backup-ai-suite.sh backup`)
4. Maintenez les images Docker à jour

---

## Structure des fichiers

```
/opt/ai-suite/
├── code-server/
│   ├── docker-compose.yml
│   ├── config/              # Configuration
│   └── projects/            # Projets
├── ollama/
│   └── docker-compose.yml
├── open-webui/
│   └── docker-compose.yml
├── backup.sh                # Sauvegarde
├── cleanup.sh               # Nettoyage
└── .env                     # Configuration

/var/log/
├── ai-suite-install.log     # Logs installation
├── ai-cleanup.log           # Logs nettoyage
└── ai-backup.log            # Logs sauvegarde
```

---

## Maintenance

### Sauvegarde automatique

Les sauvegardes s'exécutent automatiquement :
- **Backup**: Tous les jours à 3h00
- **Cleanup**: Tous les jours à 2h00
- **Rétention**: 7 jours

### Vérifier les tâches cron

```bash
crontab -l
```

### Restauration manuelle

```bash
# Lister les sauvegardes
sudo ~/Coolify\ AI\ Suite/backup-ai-suite.sh list

# Restaurer
sudo ~/Coolify\ AI\ Suite/backup-ai-suite.sh restore backup_20260425.tar.gz
```

---

## HTTPS avec Traefik

Traefik est configuré comme proxy inverse avec certificados SSL automatiques Let's Encrypt.

### Installation avec HTTPS

```bash
cd ~/Coolify\ AI\ Suite
sudo ./setup-ai-suite.sh
# Sélectionnez T pour Traefik ou A pour tout installer
```

### Ajouter HTTPS à une installation existante

```bash
sudo ~/Coolify\ AI\ Suite/setup-traefik-only.sh
```

### Configuration des clients

Sur chaque machine cliente, modifiez `/etc/hosts` :

```bash
sudo nano /etc/hosts
```

Ajoutez la ligne :
```
<IP_SERVER> code-server.local openwebui.local ollama.local
```

### URLs HTTPS

| Service | URL |
|---------|-----|
| Code-Server | https://code-server.local |
| Open WebUI | https://openwebui.local |
| Ollama API | https://ollama.local |
| Dashboard Traefik | http://IP:8080 |

### Renouvellement automatique

Les certificados SSL se renouvelent automatiquement tous les jours. Pour vérifier :
```bash
docker logs traefik | grep -i certificate
```

### Commandes Traefik

```bash
# Statut
docker ps traefik

# Logs
docker logs -f traefik

# Renouveler manuellement
docker exec traefik traefik certificates rotate

# Redémarrer
cd /opt/ai-suite/traefik && docker compose restart
```

---

## Ressources

- **Coolify**: https://coolify.io/docs
- **Ollama**: https://ollama.com/library
- **Open WebUI**: https://github.com/open-webui/open-webui
- **Code-Server**: https://github.com/coder/code-server

---

## Auteur

**Mohamed Azmi KAANICHE**
Version 2.0 - Avril 2026

---

## Changelog

### v2.1 (2026-04-25)
- ✅ Support HTTPS automatique avec Traefik
- ✅ Certificados SSL Let's Encrypt
- ✅ Script d'ajout HTTPS pour installation existante
- ✅ Labels Traefik sur tous les services
- ✅ Renouvellement automatique des certificats
- ✅ Menu interactif pour choisir les services
- ✅ Validation des prérequis système
- ✅ Configuration personnalisée des ports
- ✅ Génération automatique de mots de passe sécurisés
- ✅ Script de backup/restauration dédié
- ✅ Logs structurés avec timestamps
- ✅ Nettoyage automatique des anciennes sauvegardes
- ✅ Fichier de configuration `.env`
- ✅ Limites de ressources (mémoire) configurées

### v1.0 (2026-04-12)
- ✅ Installation initiale Coolify
- ✅ Configuration Code-Server
- ✅ Configuration Ollama
- ✅ Configuration Open WebUI
- ✅ Scripts de vérification