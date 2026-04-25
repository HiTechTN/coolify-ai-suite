# Contribution Guidelines

Merci de contribuer à Coolify AI Suite ! Voici comment participer.

## Comment contribuer

### 1. Signaler un bug

Ouvrez une issue avec :
- Description claire du problème
- Étapes pour reproduire
- Environnement (OS, version Docker, etc.)
- Logs ou captures d'écran

### 2. Proposer une fonctionnalité

Ouvrez une issue avec :
- Description de la fonctionnalité
- Cas d'usage
- Éventuelles alternatives existantes

### 3. Soumettre du code

1. **Fork** le dépôt
2. Créez une branche : `git checkout -b feature/ma-fonctionnalite`
3. Committez : `git commit -m "feat: ajout de..."`
4. Push : `git push origin feature/ma-fonctionnalite`
5. Ouvrez une **Pull Request**

## Standards de code

### Scripts Shell

- Utilisez `set -euo pipefail`
- Ajoutez des fonctions de logging
- Vérifiez les prérequis
- Incluez une aide : `usage()` ou `--help`

```bash
#!/bin/bash
set -euo pipefail

log() { echo "[$(date)] $1"; }

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -h, --help     Afficher cette aide
    -v, --verbose  Mode verbeux
EOF
}
```

### Docker Compose

- Utilisez la syntaxe version 3.8+
- Définissez `restart: unless-stopped`
- Configurez `healthcheck` si pertinent
- Limitez les ressources (`mem_limit`, `cpus`)

```yaml
version: '3.8'
services:
  example:
    image: example:latest
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: 2g
```

## Processus de review

1. Le code sera relu par un mainteneur
2. Des corrections peuvent être demandées
3. Une fois approuvé, le PR sera fusionné

## Questions ?

Ouvrez une issue ou contactez le mainteneur.