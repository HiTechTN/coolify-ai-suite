# Changelog

Tous les changements notables de ce projet seront documentés dans ce fichier.

Le format est basé sur [Keep a Changelog](https://keepachangelog.com/fr-FR/1.0.0/).

## [3.0.0] - 2026-06-12

### Ajouté
- Bibliothèque partagée `lib/common.sh` : couleurs, logging, trap handler, dry-run, force, helpers Docker, réseau
- Bibliothèque de configuration `lib/config.sh` : variables centralisées lues depuis `.env`
- Options `--help`, `--dry-run`, `--force`, `--no-color`, `--version` sur tous les scripts
- Mode `--unattended` pour `setup-ai-suite.sh` (installation non-interactive)
- Support de `NO_COLOR` pour les environnements sans terminal
- Menu interactif pour `install-ollama-models.sh` avec catégories et sélection par numéro
- Flag `--list` pour lister les modèles disponibles dans `install-ollama-models.sh`
- Sauvegarde complète : certificats SSL Traefik, crontabs, `.env`, liste des modèles Ollama
- Vérification DNS avant déploiement dans `setup-domain.sh`
- Rétablissement des services après restauration (backup)
- **Traefik** : authentification basic auth sur le dashboard (génération auto mot de passe)
- **Traefik** : rate limiting middleware (100 req/min) + sécurité headers
- **Healthchecks** Docker sur tous les services (Traefik, Code-Server, Ollama, Open WebUI)
- **Watchtower** : mise à jour automatique des images Docker (quota quotidien à 4h00)
- **Support GPU NVIDIA** pour Ollama via `--enable-gpu` (installation auto du runtime)
- Script `update-ai-suite.sh` : mise à jour depuis Git + images Docker
- Script `ai-suite-doctor.sh` : diagnostic complet (RAM, Docker, GPU, conteneurs, SSL, backups)
- Script `deploy-monitoring.sh` : déploiement optionnel cAdvisor (ou stack Prometheus+Grafana complète)
- Configuration `pre-commit` (shellcheck + shfmt + hooks)
- Dependabot pour les GitHub Actions
- Tests unitaires skeleton (bats) dans `tests/common.bats`
- Notifications (email, Telegram, Discord) via `send_notification()` dans common.sh

### Modifié
- `setup-ai-suite.sh` (v3.0) : refactorisation complète avec libs, idempotence, dry-run, bug fix select_services()
  - Ajout GPU, Watchtower, healthchecks, Traefik sécurisé
- `setup-domain.sh` (v2.0) : refactorisation avec libs, rollback, validation DNS
  - Traefik dashboard auth + middlewares
- `setup-traefik-only.sh` (v2.0) : installation des labels sans sed fragile
  - Traefik dashboard auth + rate limiting
- `check-ai-suite-status.sh` (v3.0) : ajout Traefik, certificats SSL, réseau, coolify
- `check-public-ip.sh` (v2.0) : IP fixe optionnelle (plus de valeur hardcodée), mode --fix
- `backup-ai-suite.sh` (v2.0) : sauvegarde étendue (Traefik, crontab, env, modèles)
- `install-ollama-models.sh` (v2.0) : menu interactif + --list + --dry-run
- `.env.example` : ajout TZ, FIXED_IP/DNS_SERVERS optionnels (vides par défaut)
- `.github/workflows/ci.yml` : couvre `lib/*.sh`, bats tests, pre-commit, supprime final-summary
- `.github/workflows/validate.yml` : typo fix, couvre lib, détection IP hardcodée

### Supprimé
- `final-summary.sh` (obsolète, intégré dans setup-ai-suite.sh)

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