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

# Run all test specs and capture output
output=$(nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }" 2>&1)

echo "$output"

# Check if tests failed by looking for failure indicators in output
if echo "$output" | grep -q "Failed\s*:\s*[1-9]"; then
  echo ""
  echo "Tests failed!"
  exit 1
fi

if echo "$output" | grep -q "Errors\s*:\s*[1-9]"; then
  echo ""
  echo "Tests had errors!"
  exit 1
fi

echo ""
echo "Tests complete!"
