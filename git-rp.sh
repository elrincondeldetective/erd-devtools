#!/usr/bin/env bash
# /webapps/erd-ecosystem/devops/scripts/git-rp.sh
# "Reset & Push" - Elimina el último commit local y remoto.
set -euo pipefail

# 1. Seguridad: Ramas Protegidas
CURRENT_BRANCH=$(git branch --show-current)
PROTECTED_BRANCHES=("main" "dev" "staging" "master")

for branch in "${PROTECTED_BRANCHES[@]}"; do
    if [[ "$CURRENT_BRANCH" == "$branch" ]]; then
        echo "🛑 PELIGRO: No puedes ejecutar 'git rp' en la rama protegida '$branch'."
        echo "   Este comando destruye historial. Úsalo solo en tus ramas feature/**."
        exit 1
    fi
done

# 2. Mostrar qué se va a destruir
echo "⚠️  ESTÁS A PUNTO DE ELIMINAR EL ÚLTIMO COMMIT DE: $CURRENT_BRANCH"
echo "   Tanto en tu local como en el remoto (origin)."
echo ""
echo "El commit que se eliminará para siempre es:"
echo "------------------------------------------------"
git log -1 --format="%C(red)%h%C(reset) - %s %C(bold blue)<%an>%C(reset) (%ar)"
echo "------------------------------------------------"
echo ""

# 3. Confirmación
read -r -p "¿Estás 100% seguro? Escribe 'si' para confirmar: " confirm
if [[ "$confirm" != "si" ]]; then
    echo "❌ Operación cancelada."
    exit 0
fi

# 4. Ejecución (Reset + Force Push)
echo "🔥 Destruyendo commit..."
git reset --hard HEAD~1
git push origin "$CURRENT_BRANCH" --force

echo "✅ Listo. Has retrocedido en el tiempo 1 commit en '$CURRENT_BRANCH'."