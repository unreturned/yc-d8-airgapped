#!/usr/bin/env bash
# Script for installing git hooks

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
HOOKS_DIR="$PROJECT_ROOT/.git/hooks"

echo "📦 Installing git hooks..."

# Create directory for hooks if it doesn't exist
mkdir -p "$HOOKS_DIR"

# Copy pre-commit hook
if [ -f "$HOOKS_DIR/pre-commit" ]; then
    echo "⚠️  pre-commit hook already exists, creating backup..."
    mv "$HOOKS_DIR/pre-commit" "$HOOKS_DIR/pre-commit.backup.$(date +%s)"
fi

cat > "$HOOKS_DIR/pre-commit" << 'HOOK_EOF'
#!/usr/bin/env bash
# Pre-commit hook for checking trailing whitespaces and exactly one newline at end of file

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "🔍 Checking code quality..."

# Get list of staged files (excluding deleted)
FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(tf|yaml|yml|sh|md|txt|Makefile)$' || true)

if [ -z "$FILES" ]; then
    echo -e "${GREEN}✓ No files to check${NC}"
    exit 0
fi

# Check each file for trailing whitespaces and exactly one newline at end
FOUND_ISSUES=0

for FILE in $FILES; do
    if [ -f "$FILE" ] && [ -s "$FILE" ]; then
        # Check for trailing whitespaces
        if grep -n ' $' "$FILE" > /dev/null 2>&1; then
            if [ $FOUND_ISSUES -eq 0 ]; then
                echo -e "${RED}✗ Issues found:${NC}"
                FOUND_ISSUES=1
            fi
            echo -e "${YELLOW}  $FILE: trailing whitespaces${NC}"
            grep -n ' $' "$FILE" | head -5 | sed 's/^/    /'
            if [ $(grep -c ' $' "$FILE") -gt 5 ]; then
                echo -e "    ${YELLOW}... and $(( $(grep -c ' $' "$FILE") - 5 )) more lines${NC}"
            fi
        fi

        # Check for exactly one newline at end of file
        # Get last 2 bytes in hex format
        LAST_TWO=$(tail -c 2 "$FILE" 2>/dev/null | od -An -tx1 | tr -d ' ')

        # Check for missing newline (last byte is not 0a)
        if [ -n "$(tail -c 1 "$FILE")" ]; then
            if [ $FOUND_ISSUES -eq 0 ]; then
                echo -e "${RED}✗ Issues found:${NC}"
                FOUND_ISSUES=1
            fi
            echo -e "${YELLOW}  $FILE: missing newline at end of file${NC}"
        # Check for multiple trailing newlines (both bytes are 0a)
        elif [ "$LAST_TWO" = "0a0a" ]; then
            if [ $FOUND_ISSUES -eq 0 ]; then
                echo -e "${RED}✗ Issues found:${NC}"
                FOUND_ISSUES=1
            fi
            echo -e "${YELLOW}  $FILE: multiple trailing newlines (should be exactly one)${NC}"
        fi
    fi
done

if [ $FOUND_ISSUES -eq 1 ]; then
    echo ""
    echo -e "${RED}❌ Commit rejected: formatting issues found${NC}"
    echo -e "${YELLOW}Fix the issues above and try again${NC}"
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ All checks passed${NC}"
exit 0
HOOK_EOF

chmod +x "$HOOKS_DIR/pre-commit"

echo "✅ Git hooks successfully installed!"
echo ""
echo "Installed hooks:"
echo "  - pre-commit: check trailing whitespaces and exactly one newline at end of files"
echo ""
echo "For testing:"
echo "  git add <file> && git commit -m 'test'"
