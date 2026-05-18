# Changelog

Tous les changements notables de ce projet seront documentés dans ce fichier.

Le format est basé sur [Keep a Changelog](https://keepachangelog.com/fr-FR/1.0.0/).

## [2.2.0] - 2026-05-18

### Ajouté
- Support des noms de domaine réels (ex: `hitech.tn`)
- Script `setup-domain.sh` pour configurer un domaine sur installation existante
- Configuration automatique Let's Encrypt avec le domaine
- Routage Traefik avec sous-domaines: `code.*`, `chat.*`, `ollama.*`, `coolify.*`
- Sous-domaines personnalisables pour chaque service

### Ajouté
- Script `check-public-ip.sh` pour surveiller l'IP publique et la cohérence DNS
- Support des serveurs DNS personnalisables (dns1.tunet.tn, dns2.tunet.tn)

### Modifié
- `setup-ai-suite.sh` (v2.2): support domaine avec fallback `.local`
- `setup-traefik-only.sh` (v1.1): support domaine avec prompt interactif
- `final-summary.sh` (v2.1): affichage URLs domaine
- `.env.example`: variables `DOMAIN`, `SSL_EMAIL`, `FIXED_IP`, `DNS_SERVERS`
- Documentation README avec sections domaine et surveillance IP

## [2.1.0] - 2026-04-25

### Ajouté
- Support HTTPS automatique avec Traefik
- Certificats SSL Let's Encrypt automatiques
- Script `setup-traefik-only.sh` pour installation existante
- Labels Traefik sur tous les services
- Renouvellement automatique des certificats SSL
- Menu interactif pour choisir les services
- Validation des prérequis système (RAM, espace, ports)
- Script de backup/restauration (`backup-ai-suite.sh`)
- Configuration `.env` pour les variables
- Fichier `.env.example` comme template

### Modifié
- Refactorisation complète de `setup-ai-suite.sh` (v2.1)
- Amélioration de `check-ai-suite-status.sh` (v2.0)
- Amélioration de `final-summary.sh` (v2.0)
- Documentation README.md restructurée

## [2.0.0] - 2026-04-25

### Ajouté
- Menu interactif pour choisir les services
- Configuration personnalisée des ports
- Génération automatique de mots de passe sécurisés
- Configuration des limites de ressources (mémoire)
- Logs structurés avec timestamps
- Script de backup avec rétention
- Export de configuration `.env`

### Modifié
- Scripts bash modernisés avec couleurs
- Meilleure gestion des erreurs
- Validation des prérequis

## [1.0.0] - 2026-04-12

### Ajouté
- Script d'installation `setup-ai-suite.sh`
- Script de vérification `check-ai-suite-status.sh`
- Script d'installation modèles `install-ollama-models.sh`
- Résumé final `final-summary.sh`
- Documentation README.md complète
- Configuration Docker Compose pour:
  - Coolify
  - Code-Server
  - Ollama
  - Open WebUI
- Configuration UFW et Fail2Ban
- Nettoyage automatique (cron)
- Structure `/opt/ai-suite/`