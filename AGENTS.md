# AGENTS.md

## Project Overview

**aicommits.nvim** - AI-powered git commit message generation directly in Neovim.

This Neovim plugin analyzes staged git changes and generates properly formatted conventional commit messages using AI providers (currently OpenAI, extensible to others). Written in Lua 5.1/LuaJIT for Neovim 0.9+.

Key features: Conventional commit format, multiple message options, custom UI picker, Neogit integration, extensible provider system.

## Build and Test Commands

### Setup
```bash
# First-time setup (installs plenary.nvim for testing)
./app.sh setup

# Set API key for testing
export AICOMMITS_NVIM_OPENAI_API_KEY="sk-..."
```

### Development
```bash
# Check environment status
./app.sh status

# Manual testing: Load plugin in test repo
nvim -u tests/minimal_init.lua
```

### Testing
```bash
# Run all tests (128+ test cases, same as CI)
./app.sh test

# Run specific test file
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/your_test_spec.lua"

# Check code formatting (same as CI)
./app.sh lint

# Auto-format code
./app.sh format

# Run all CI checks locally
./app.sh ci
```

**CI Guarantee**: If `./app.sh ci` passes locally, your PR will pass CI on GitHub.

## Code Style Guidelines

**Formatter**: stylua with config in `.stylua.toml`

- **Indentation**: 2 spaces
- **Line length**: 120 characters max
- **Quote style**: Auto-prefer double quotes
- **Call parentheses**: Always use parentheses for function calls
- **Naming conventions**:
  - Modules/functions: `snake_case`
  - Constants: `UPPER_SNAKE_CASE`
  - Private functions: `_prefix_with_underscore`

### Lua Module Structure
```lua
local M = {}

-- Constants
local MAX_RETRIES = 3

-- Private functions (prefixed with _)
local function _internal_helper()
  -- ...
end

-- Public functions with LuaDoc
--- Brief description
--- @param name string Parameter description
--- @return boolean success Whether operation succeeded
function M.public_function(name)
  -- ...
end

return M
```

### Error Handling Pattern
```lua
-- Use pcall for risky operations
local ok, result = pcall(function()
  return risky_operation()
end)

if not ok then
  vim.notify("Error: " .. result, vim.log.levels.ERROR)
  return nil
end
```

### Async Callback Pattern
```lua
-- Error-first callback pattern (node.js style)
function M.async_operation(args, callback)
  -- callback signature: function(error, result)
  callback(err, result)
end
```

## Testing Instructions

**Framework**: busted via plenary.nvim
**Test Location**: `tests/*_spec.lua`
**Mock System**: `tests/helpers/mock.lua`

### Requirements
- All new features must include tests
- Test both success and error paths
- Mock external dependencies (HTTP, git, system calls)
- Always cleanup mocks in `after_each()`
- Use `before_each()` to reload modules: `package.loaded["module"] = nil`

### Test Structure
```lua
describe("module name", function()
  before_each(function()
    -- Reload module to avoid test pollution
    package.loaded["aicommits.module"] = nil
  end)

  it("handles normal case", function()
    assert.equals("expected", actual)
  end)

  it("handles errors gracefully", function()
    assert.has_error(function()
      bad_operation()
    end)
  end)
end)
```

### Running Tests
```bash
# Before submitting PR
./app.sh ci          # Must pass - runs same checks as CI

# During development
./app.sh test        # Run all tests
./app.sh lint        # Check formatting
```

## Security Considerations

**API Keys**: Never commit API keys or credentials to the repository.

### Environment Variables (Priority Order)
1. `AICOMMITS_NVIM_OPENAI_API_KEY` - Plugin-specific
2. `OPENAI_API_KEY` - Standard OpenAI variable

### Sensitive Files (gitignored)
- `.env`, `.env.*` files
- `memory-bank/` directory (local project context)
- API keys in config files

### Security Best Practices
- Use environment variables for API keys, not hardcoded values
- Validate API responses before processing
- Handle API errors gracefully without exposing credentials
- Review `.gitignore` before committing sensitive configurations

### Dependency Security
- Minimal external dependencies (only plenary.nvim for testing)
- No runtime dependencies beyond Neovim built-ins
- HTTP requests use Neovim's built-in `curl` wrapper

## Git Workflow

### Branch Naming
```bash
git checkout -b feature/your-feature
git checkout -b fix/your-bugfix
```

### Commit Message Format
Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

Examples:
feat(providers): add Anthropic provider support
fix(ui): handle empty commit message list
docs: update installation instructions
test: add provider validation tests
refactor: simplify config validation logic
```

**Types**: feat, fix, docs, style, refactor, perf, test, build, ci, chore

### PR Requirements
- [ ] `./app.sh ci` passes locally
- [ ] New features include tests
- [ ] Documentation updated (README, code comments)
- [ ] Conventional commit messages
- [ ] Code formatted with stylua

---

*Generated using Claude Code's `/generate-agents-md` command*
*Last updated: 2025-10-14*
