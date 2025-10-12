#!/bin/bash
# aicommits.nvim - Management Script

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Project info
PROJECT_NAME="aicommits.nvim"
NVIM_MIN_VERSION="0.9.0"

# Paths
PLENARY_PATH_LOCAL="$HOME/.local/share/nvim/site/pack/vendor/start/plenary.nvim"
PLENARY_PATH_LAZY="$HOME/.local/share/nvim/lazy/plenary.nvim"
TEST_DIR="tests"
LUA_DIR="lua"

# Status functions
print_header() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${PURPLE}${PROJECT_NAME}${NC} - Management Script                                         ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_step() {
    echo -e "${PURPLE}▶${NC} $1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check Neovim installation
check_neovim() {
    if ! command_exists nvim; then
        print_error "Neovim not found"
        echo "  Install from: https://neovim.io"
        return 1
    fi

    local version=$(nvim --version | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    print_success "Neovim $version found"
    return 0
}

# Check if plenary.nvim is installed
check_plenary() {
    if [ -d "$PLENARY_PATH_LOCAL" ] || [ -d "$PLENARY_PATH_LAZY" ]; then
        print_success "plenary.nvim found"
        return 0
    else
        print_warning "plenary.nvim not found"
        return 1
    fi
}

# Setup plenary.nvim for testing
setup_plenary() {
    print_step "Installing plenary.nvim for testing..."

    if [ -d "$PLENARY_PATH_LOCAL" ]; then
        print_info "plenary.nvim already installed at $PLENARY_PATH_LOCAL"
        return 0
    fi

    mkdir -p "$(dirname "$PLENARY_PATH_LOCAL")"
    git clone --depth=1 https://github.com/nvim-lua/plenary.nvim.git "$PLENARY_PATH_LOCAL"

    if [ $? -eq 0 ]; then
        print_success "plenary.nvim installed successfully"
        return 0
    else
        print_error "Failed to install plenary.nvim"
        return 1
    fi
}

# Check stylua installation
check_stylua() {
    if command_exists stylua; then
        local version=$(stylua --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
        print_success "stylua $version found"
        return 0
    else
        print_warning "stylua not found (optional for local development)"
        echo "  Install with: cargo install stylua"
        echo "  Or download from: https://github.com/JohnnyMorganz/StyLua/releases"
        return 1
    fi
}

# Setup command - prepare development environment
cmd_setup() {
    print_header
    print_step "Setting up development environment..."
    echo ""

    # Check prerequisites
    print_step "Checking prerequisites..."
    check_neovim || exit 1
    echo ""

    # Setup plenary.nvim
    if ! check_plenary; then
        setup_plenary || exit 1
    fi
    echo ""

    print_success "Setup complete! You can now run tests with: ./app.sh test"
}

# Test command - run Neovim tests (same as CI)
cmd_test() {
    print_header
    print_step "Running tests..."
    echo ""

    # Verify plenary is available
    if ! check_plenary; then
        print_error "plenary.nvim not found. Run './app.sh setup' first"
        exit 1
    fi

    # Show Neovim version
    print_info "Neovim version:"
    nvim --version | head -n1
    echo ""

    # Run tests (same command as CI)
    print_step "Running test suite..."
    output=$(nvim --headless --noplugin -u tests/minimal_init.lua \
        -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }" 2>&1)

    echo "$output"

    # Check for failures in output (plenary doesn't exit with proper code)
    if echo "$output" | grep -q "Failed\s*:\s*[1-9]"; then
        echo ""
        print_error "Tests failed"
        exit 1
    fi

    if echo "$output" | grep -q "Errors\s*:\s*[1-9]"; then
        echo ""
        print_error "Tests had errors"
        exit 1
    fi

    echo ""
    print_success "All tests passed!"
}

# Lint command - run stylua check (same as CI)
cmd_lint() {
    print_header
    print_step "Running stylua check..."
    echo ""

    if ! command_exists stylua; then
        print_error "stylua not found"
        echo ""
        echo "Install stylua:"
        echo "  cargo install stylua"
        echo "  Or download from: https://github.com/JohnnyMorganz/StyLua/releases"
        exit 1
    fi

    # Run stylua check (same as CI)
    print_step "Checking Lua formatting..."
    stylua --check lua/ tests/

    if [ $? -eq 0 ]; then
        echo ""
        print_success "All files are properly formatted!"
    else
        echo ""
        print_error "Formatting issues found"
        print_info "Run './app.sh format' to fix automatically"
        exit 1
    fi
}

# Format command - auto-format with stylua
cmd_format() {
    print_header
    print_step "Formatting Lua files..."
    echo ""

    if ! command_exists stylua; then
        print_error "stylua not found"
        echo ""
        echo "Install stylua:"
        echo "  cargo install stylua"
        exit 1
    fi

    print_step "Formatting lua/ and tests/..."
    stylua lua/ tests/

    if [ $? -eq 0 ]; then
        echo ""
        print_success "Files formatted successfully!"
    else
        echo ""
        print_error "Formatting failed"
        exit 1
    fi
}

# CI command - run all CI checks locally
cmd_ci() {
    print_header
    print_step "Running all CI checks locally..."
    echo ""

    # Run tests
    cmd_test
    echo ""

    # Run lint
    cmd_lint
    echo ""

    print_success "All CI checks passed! Ready to push."
}

# Status command - show environment status
cmd_status() {
    print_header
    print_step "Checking environment status..."
    echo ""

    echo "Prerequisites:"
    check_neovim
    check_plenary
    echo ""

    echo "Optional Tools:"
    check_stylua
    echo ""

    echo "Project Files:"
    if [ -d "$LUA_DIR" ]; then
        local lua_files=$(find "$LUA_DIR" -name "*.lua" | wc -l | tr -d ' ')
        print_success "$lua_files Lua files in $LUA_DIR/"
    fi

    if [ -d "$TEST_DIR" ]; then
        local test_files=$(find "$TEST_DIR" -name "*_spec.lua" | wc -l | tr -d ' ')
        print_success "$test_files test files in $TEST_DIR/"
    fi

    if [ -f ".stylua.toml" ]; then
        print_success "Stylua config found"
    fi
}

# Help command
cmd_help() {
    print_header

    echo -e "${PURPLE}Usage:${NC}"
    echo "  ./app.sh <command>"
    echo ""
    echo -e "${PURPLE}Core Commands:${NC}"
    echo -e "  ${GREEN}setup${NC}         First-time setup (install dependencies)"
    echo -e "  ${GREEN}test${NC}          Run Neovim tests (same as CI)"
    echo -e "  ${GREEN}lint${NC}          Check code formatting with stylua (same as CI)"
    echo -e "  ${GREEN}format${NC}        Auto-format code with stylua"
    echo -e "  ${GREEN}ci${NC}            Run all CI checks locally"
    echo ""
    echo -e "${PURPLE}Utility Commands:${NC}"
    echo -e "  ${GREEN}status${NC}        Show environment status"
    echo -e "  ${GREEN}help${NC}          Show this help message"
    echo ""
    echo -e "${PURPLE}Examples:${NC}"
    echo "  ./app.sh setup          # First-time setup"
    echo "  ./app.sh test           # Run tests"
    echo "  ./app.sh ci             # Run all CI checks before pushing"
    echo ""
    echo -e "${PURPLE}CI Workflow Mapping:${NC}"
    echo -e "  ${CYAN}CI test job${NC}     → ./app.sh test"
    echo -e "  ${CYAN}CI lint job${NC}     → ./app.sh lint"
    echo -e "  ${CYAN}All CI checks${NC}   → ./app.sh ci"
    echo ""
}

# Main command dispatcher
main() {
    case "${1:-help}" in
        setup)
            cmd_setup
            ;;
        test)
            cmd_test
            ;;
        lint)
            cmd_lint
            ;;
        format)
            cmd_format
            ;;
        ci)
            cmd_ci
            ;;
        status)
            cmd_status
            ;;
        help|--help|-h)
            cmd_help
            ;;
        *)
            print_error "Unknown command: $1"
            echo ""
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
