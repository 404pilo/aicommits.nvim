#!/bin/bash
# Test runner for aicommits.nvim

set -e

echo "Running aicommits.nvim tests..."
echo ""

# Check if plenary.nvim is available
if [ ! -d "$HOME/.local/share/nvim/lazy/plenary.nvim" ] && [ ! -d "$HOME/.local/share/nvim/site/pack/*/start/plenary.nvim" ]; then
  echo "Warning: plenary.nvim not found in standard locations"
  echo "Tests may fail if plenary.nvim is not installed"
  echo ""
fi

# Run all test specs
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"

echo ""
echo "Tests complete!"
