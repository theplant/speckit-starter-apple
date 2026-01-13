#!/bin/bash

set -e

echo "🍎 Installing Speckit Starter for Apple Platforms..."

# Check if uvx is available, install uv via brew if not
if ! command -v uvx &> /dev/null; then
    echo "📦 uvx not found, installing uv via Homebrew..."
    brew install uv
fi

# Step 1: Run uvx specify init with windsurf AI and sh script
echo "📦 Initializing spec-kit..."
uvx --from git+https://github.com/github/spec-kit.git specify init --ai=windsurf --script=sh --force .

# Step 2: Clone the speckit-starter-apple to a temp folder
TEMP_DIR=$(mktemp -d)
echo "📥 Cloning speckit-starter-apple to $TEMP_DIR..."
git clone --depth 1 git@github.com:theplant/speckit-starter-apple.git "$TEMP_DIR"

# Step 3: Merge .specify and .windsurf folders into current directory (overwrite existing files)
echo "📋 Merging .specify and .windsurf folders..."
mkdir -p .specify .windsurf
cp -rf "$TEMP_DIR/.specify/." .specify/
if [ -d "$TEMP_DIR/.windsurf" ]; then
    cp -rf "$TEMP_DIR/.windsurf/." .windsurf/
fi

# Cleanup
echo "🧹 Cleaning up..."
rm -rf "$TEMP_DIR"

echo "✅ Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Review the constitution: cat .specify/memory/constitution.md"
echo "  2. Check the workflows: ls -la .windsurf/workflows/"
echo "  3. Start building your iOS/macOS app with Clean Architecture!"
