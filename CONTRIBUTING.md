# Contributing to aicommits.nvim

Thanks for your interest in contributing! This guide will help you get started.

## Quick Start for Contributors

We use `app.sh` for all development tasks. This ensures consistency between local development and CI:

```bash
./app.sh setup    # First-time setup
./app.sh test     # Run tests (same as CI)
./app.sh lint     # Check formatting (same as CI)
./app.sh ci       # Run all CI checks
```

If `./app.sh ci` passes locally, your PR will pass CI on GitHub.

## How to Contribute

### Reporting Bugs

Before opening an issue, search existing ones to avoid duplicates. Include:

- Clear description of the problem
- Steps to reproduce
- Expected vs actual behavior
- Environment details:
  - Neovim version (`:version`)
  - OS
  - Plugin configuration

### Suggesting Features

Open an issue with:
- Clear description of the feature
- Why it would be useful
- Possible implementation approach

### Pull Requests

1. Fork the repo
2. Create a feature branch
3. Make your changes
4. Write/update tests
5. Ensure tests pass
6. Submit PR with clear description

## Development Setup

### Prerequisites

**Required:**
- Neovim 0.9+ (includes Lua runtime)
- Git 2.0+
- curl (for HTTP requests to OpenAI API)
- OpenAI API key

**Optional:**
- stylua (for code formatting during development)

### Get Started

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/aicommits.nvim.git
cd aicommits.nvim

# Add upstream
git remote add upstream https://github.com/pilo404/aicommits.nvim.git

# Run first-time setup (installs plenary.nvim for testing)
./app.sh setup
```

The `app.sh` script is your main development tool. It provides:
- `setup` - First-time setup (installs dependencies)
- `test` - Run test suite (same as CI)
- `lint` - Check code formatting (same as CI)
- `format` - Auto-format code with stylua
- `ci` - Run all CI checks locally
- `status` - Check environment status

### Quick Start

```bash
# Check environment
./app.sh status

# Run tests
./app.sh test

# Check formatting
./app.sh lint

# Run all CI checks before pushing
./app.sh ci
```

### Manual Testing

Set up a test environment:

```bash
# Set API key for testing
export AICOMMITS_NVIM_OPENAI_API_KEY="sk-..."

# Create test repo
mkdir -p /tmp/test-repo
cd /tmp/test-repo
git init
echo "test" > test.txt
git add test.txt
```

Load the plugin for development:

```lua
-- minimal_init.lua
vim.cmd("set rtp+=.")
vim.cmd("runtime! plugin/plenary.vim")

require("aicommits").setup({
  -- test config
})
```

Run with: `nvim -u minimal_init.lua`

## Development Workflow

### 1. Create Branch

```bash
git checkout -b feature/your-feature
# or
git checkout -b fix/your-fix
```

### 2. Make Changes

Keep changes focused and atomic. One feature or fix per PR.

### 3. Write Tests

Add tests for new features:

```lua
-- tests/your_feature_spec.lua
describe("your feature", function()
  it("works correctly", function()
    assert.equals("expected", "expected")
  end)
end)
```

### 4. Run Tests

```bash
# Run all tests (recommended - same command as CI)
./app.sh test

# Check code formatting
./app.sh lint

# Auto-format code
./app.sh format

# Run all CI checks locally
./app.sh ci
```

For specific tests:
```bash
# Run single test file
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/your_test_spec.lua"
```

### 5. Update Docs

Update README.md if you changed user-facing features.

### 6. Commit

Use conventional commits:

```bash
git commit -m "feat: add support for custom providers"
git commit -m "fix: handle null API responses"
git commit -m "docs: update installation guide"
```

## Code Style

### Lua Conventions

```lua
-- Module structure
local M = {}

-- Constants
local MAX_RETRIES = 3

-- Private functions (prefixed with _)
local function _internal_helper()
  -- ...
end

-- Public functions
function M.public_function()
  -- ...
end

return M
```

### Naming

- Modules: `snake_case`
- Functions: `snake_case`
- Constants: `UPPER_SNAKE_CASE`
- Private: `_prefix`

### Documentation

Use LuaDoc comments:

```lua
--- Brief description
--- @param name string The parameter
--- @return boolean success Whether it worked
function M.do_something(name)
  -- ...
end
```

### Error Handling

```lua
-- Use pcall for risky operations
local ok, result = pcall(function()
  return risky_operation()
end)

if not ok then
  vim.notify("Failed: " .. result, vim.log.levels.ERROR)
  return nil
end
```

## Testing Guidelines

### Test Structure

```lua
describe("module", function()
  before_each(function()
    -- Setup
  end)

  after_each(function()
    -- Cleanup
  end)

  it("handles normal case", function()
    assert.equals("expected", result)
  end)

  it("handles errors", function()
    assert.has_error(function()
      bad_call()
    end)
  end)
end)
```

### Running Tests

```bash
# Run all tests
./app.sh test

# Check formatting
./app.sh lint

# Run everything (tests + lint)
./app.sh ci
```

All commands use the exact same checks as CI, so if `./app.sh ci` passes locally, CI will pass on GitHub.

## Pull Request Process

### Before Submitting

1. Sync with upstream:
```bash
git fetch upstream
git rebase upstream/main
```

2. Run all CI checks locally:
```bash
./app.sh ci
```

This runs the exact same checks as CI:
- All tests (128 test cases)
- Code formatting (stylua)

If `./app.sh ci` passes, your PR will pass CI.

3. Update docs if needed

4. Check commits are clean and focused

### Submitting

1. Push to your fork:
```bash
git push origin feature/your-feature
```

2. Open PR on GitHub

3. Fill out the PR template completely

4. Respond to review feedback

### Review Process

- Maintainers review within 2-3 business days
- Address all feedback
- Keep PRs focused
- Be patient and respectful

### After Merge

```bash
# Delete feature branch
git branch -d feature/your-feature
git push origin --delete feature/your-feature

# Update fork
git checkout main
git pull upstream main
git push origin main
```

## Project Structure

```
aicommits.nvim/
├── lua/aicommits/
│   ├── init.lua              # Entry point
│   ├── config.lua            # Configuration
│   ├── git.lua               # Git operations
│   ├── http.lua              # HTTP client
│   ├── openai.lua            # OpenAI API
│   ├── commit.lua            # Commit workflow
│   ├── ui.lua                # UI orchestration
│   ├── ui/picker.lua         # Floating picker
│   ├── utils.lua             # Utilities
│   ├── notifications.lua     # Notifications
│   ├── health.lua            # Health checks
│   ├── commands.lua          # Commands
│   └── integrations/
│       └── neogit.lua        # Neogit integration
├── tests/                    # Test suite (128 tests)
├── app.sh                    # Development tool (setup, test, lint, ci)
├── .github/workflows/        # CI/CD (uses app.sh)
└── .stylua.toml              # Code formatting config
```

### Module Responsibilities

- **init.lua**: Entry point, setup, main commands
- **config.lua**: Configuration management
- **git.lua**: Git operations (repo check, diff, commit)
- **http.lua**: HTTP client (curl wrapper)
- **openai.lua**: OpenAI API client
- **commit.lua**: Commit workflow orchestration
- **ui.lua**: UI orchestration
- **ui/picker.lua**: Custom floating window picker
- **health.lua**: Health check system
- **commands.lua**: Command registration

## Getting Help

- GitHub Issues: Bugs and features
- GitHub Discussions: Questions
- PR Comments: Code review

## Recognition

Contributors are recognized in:
- README acknowledgments
- Release notes
- GitHub contributors list

Thanks for contributing!
