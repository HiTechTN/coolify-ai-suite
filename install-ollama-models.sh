#!/bin/bash
# install-ollama-models.sh - Installer les modèles AI pour Ollama
# Ce script s'exécute après le démarrage d'Ollama

set -e

echo "=========================================="
echo "  Installation des modèles Ollama"
echo "=========================================="
echo ""

# Vérifier qu'Ollama fonctionne
echo "⏳ Vérification d'Ollama..."
until curl -s http://localhost:11434/api/tags > /dev/null 2>&1; do
    echo "   Ollama n'est pas encore prêt, attente de 10 secondes..."
    sleep 10
done
echo "  ✅ Ollama est prêt !"
echo ""

# Liste des modèles à installer
MODELS=(
    "qwen2.5-coder:3b"
    "deepseek-coder-v2:16b-lite-instruct-q2_K"
    "phi3:3.8b"
    "llama3.2:3b"
)

echo "📦 Modèles à installer :"
for model in "${MODELS[@]}"; do
    echo "   • $model"
done
echo ""

echo "⏳ Téléchargement des modèles (cela peut prendre du temps)..."
echo ""

for model in "${MODELS[@]}"; do
    echo "📥 Téléchargement de $model..."
    ollama pull "$model"
    echo "  ✅ $model installé !"
    echo ""
done

echo "=========================================="
echo "  ✅ Tous les modèles sont installés !"
echo "=========================================="
echo ""
echo "📊 Modèles disponibles :"
curl -s http://localhost:11434/api/tags | jq -r '.models[] | "   • " + .name + " (" + (.size | tostring) + " bytes)"'
echo ""
echo "💡 Pour tester un modèle :"
echo "   curl http://localhost:11434/api/generate -d '{\"model\": \"qwen2.5-coder:3b\", \"prompt\": \"Hello!\", \"stream\": false}'"
echo ""
