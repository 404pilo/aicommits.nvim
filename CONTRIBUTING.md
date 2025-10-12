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

## Adding a Provider

This section guides you through implementing a new AI provider for aicommits.nvim. Providers enable the plugin to work with different AI services (like Ollama, Azure OpenAI, Anthropic, etc.).

### Provider Architecture Overview

The provider system in aicommits.nvim is designed to be modular and extensible:

1. **Base Interface** (`lua/aicommits/providers/base.lua`) - Defines the contract all providers must implement
2. **Provider Registry** (`lua/aicommits/providers/init.lua`) - Manages provider registration and discovery
3. **Provider Implementations** (e.g., `lua/aicommits/providers/openai.lua`) - Concrete implementations for specific AI services
4. **Configuration System** (`lua/aicommits/config.lua`) - Handles provider-specific settings
5. **Health Checks** (`lua/aicommits/health.lua`) - Validates provider setup

### Provider Interface Requirements

All providers must implement the interface defined in [`lua/aicommits/providers/base.lua`](lua/aicommits/providers/base.lua). Here's what's required:

#### Required Methods

1. **`name`** (string) - Unique identifier for the provider (e.g., "ollama", "anthropic")

2. **`generate_commit_message(self, diff, config, callback)`** - Generate commit messages from a git diff
   - `diff`: The git diff output (string)
   - `config`: Provider-specific configuration (table)
   - `callback`: Callback function with signature `function(error, messages)` where messages is an array of strings

3. **`validate_config(self, config)`** - Validate provider configuration
   - Returns: `boolean valid, table errors`
   - `valid`: true if configuration is valid
   - `errors`: array of error messages (empty if valid)

#### Optional Methods (with defaults)

4. **`get_auth_headers(self, config)`** - Get HTTP authentication headers
   - Returns: table of HTTP headers
   - Default: Returns empty table `{}`

5. **`get_capabilities(self)`** - Describe provider features
   - Returns: table with capabilities
   - Default: Returns basic capabilities (no streaming, single generation)

### Step-by-Step Implementation Guide

#### Step 1: Create Provider File

Create a new file in `lua/aicommits/providers/` for your provider:

```bash
touch lua/aicommits/providers/ollama.lua
```

#### Step 2: Implement Basic Structure

```lua
-- lua/aicommits/providers/ollama.lua
-- Ollama provider implementation for aicommits.nvim
local base = require("aicommits.providers.base")
local http = require("aicommits.http")
local prompts = require("aicommits.prompts")

-- Create provider instance using base.new()
local M = base.new({
  name = "ollama",
})

-- Implement required methods below...

return M
```

#### Step 3: Implement Configuration Validation

Validate all required configuration options:

```lua
-- Validate Ollama provider configuration
-- @param config table Provider configuration
-- @return boolean valid True if configuration is valid
-- @return table errors Array of error messages (empty if valid)
function M:validate_config(config)
  local errors = {}

  -- Validate required fields
  if not config.model or config.model == "" then
    table.insert(errors, "model is required and must be a non-empty string")
  end

  -- Validate endpoint
  if config.endpoint and type(config.endpoint) ~= "string" then
    table.insert(errors, "endpoint must be a string")
  end

  -- Validate numeric parameters
  if config.max_length and (type(config.max_length) ~= "number" or config.max_length <= 0) then
    table.insert(errors, "max_length must be a positive number")
  end

  if config.temperature and (type(config.temperature) ~= "number" or config.temperature < 0 or config.temperature > 2) then
    table.insert(errors, "temperature must be a number between 0 and 2")
  end

  return #errors == 0, errors
end
```

#### Step 4: Implement Commit Message Generation

This is the core functionality - calling the AI API and processing responses:

```lua
-- Generate commit message(s) using Ollama API
-- @param diff string The git diff to generate message for
-- @param config table Provider-specific configuration
-- @param callback function(error, messages) Callback with error or array of messages
function M:generate_commit_message(diff, config, callback)
  -- Get configuration with defaults
  local endpoint = config.endpoint or "http://localhost:11434/api/generate"
  local model = config.model or "llama2"
  local max_length = config.max_length or 50
  local temperature = config.temperature or 0.7

  -- Build API request body
  local request_body = {
    model = model,
    prompt = prompts.build_system_prompt(max_length) .. "\n\n" .. diff,
    stream = false,
    options = {
      temperature = temperature,
    },
  }

  -- Make API request
  http.post(endpoint, self:get_auth_headers(config), vim.json.encode(request_body), function(err, response_body)
    if err then
      callback(err, nil)
      return
    end

    -- Parse JSON response
    local ok, response = pcall(vim.json.decode, response_body)
    if not ok then
      callback("Failed to parse Ollama API response: " .. tostring(response), nil)
      return
    end

    -- Check for API errors
    if response.error then
      callback("Ollama API Error: " .. (response.error or vim.inspect(response)), nil)
      return
    end

    -- Extract message from response
    if not response.response or response.response == "" then
      callback("No commit message was generated. Try again.", nil)
      return
    end

    -- Process and return messages
    local processed = prompts.process_messages({ response.response })
    if #processed == 0 then
      callback("No valid commit messages were generated. Try again.", nil)
      return
    end

    callback(nil, processed)
  end)
end
```

#### Step 5: Implement Authentication (if needed)

If your provider requires API keys or custom headers:

```lua
-- Get authentication headers for Ollama API
-- @param config table Provider configuration
-- @return table headers HTTP headers
function M:get_auth_headers(config)
  -- Ollama typically doesn't need auth headers for local use
  -- But you can add support for authenticated instances:
  if config.api_key and config.api_key ~= "" then
    return {
      Authorization = "Bearer " .. config.api_key,
    }
  end
  return {}
end
```

#### Step 6: Define Capabilities (optional)

Describe what your provider supports:

```lua
-- Get Ollama provider capabilities
-- @return table capabilities Provider feature support
function M:get_capabilities()
  return {
    supports_streaming = true, -- Ollama supports streaming
    supports_multiple_generations = false, -- Ollama generates one at a time
    max_generations = 1,
  }
end
```

#### Step 7: Register Your Provider

Edit `lua/aicommits/providers/init.lua` to register your provider during setup:

```lua
function M.setup()
  -- Existing providers...
  local ok, openai_provider = pcall(require, "aicommits.providers.openai")
  if ok then
    M.register("openai", openai_provider)
  end

  -- Add your provider
  local ok, ollama_provider = pcall(require, "aicommits.providers.ollama")
  if ok then
    M.register("ollama", ollama_provider)
  else
    vim.notify("Failed to load Ollama provider: " .. tostring(ollama_provider), vim.log.levels.ERROR)
  end
end
```

### Configuration Integration

#### Step 8: Add Default Configuration

Add your provider's default configuration in `lua/aicommits/config.lua`:

```lua
M.defaults = {
  active_provider = "openai",
  
  providers = {
    openai = {
      -- ... existing config
    },
    
    -- Add your provider config
    ollama = {
      enabled = true,
      endpoint = "http://localhost:11434/api/generate",
      model = "llama2",
      max_length = 50,
      temperature = 0.7,
    },
  },
}
```

### Testing Requirements

#### Unit Tests

Create unit tests in `tests/providers/` to test your provider implementation:

```lua
-- tests/providers/ollama_spec.lua
describe("ollama provider", function()
  local ollama
  local base

  before_each(function()
    package.loaded["aicommits.providers.ollama"] = nil
    package.loaded["aicommits.providers.base"] = nil
    
    base = require("aicommits.providers.base")
    ollama = require("aicommits.providers.ollama")
  end)

  describe("initialization", function()
    it("has correct name", function()
      assert.equals("ollama", ollama.name)
    end)

    it("implements required methods", function()
      assert.is_function(ollama.generate_commit_message)
      assert.is_function(ollama.validate_config)
      assert.is_function(ollama.get_auth_headers)
      assert.is_function(ollama.get_capabilities)
    end)
  end)

  describe("validate_config", function()
    it("accepts valid configuration", function()
      local valid, errors = ollama:validate_config({
        model = "llama2",
        endpoint = "http://localhost:11434/api/generate",
      })
      
      assert.is_true(valid)
      assert.equals(0, #errors)
    end)

    it("rejects missing model", function()
      local valid, errors = ollama:validate_config({})
      
      assert.is_false(valid)
      assert.is_true(#errors > 0)
      assert.matches("model", errors[1])
    end)

    it("rejects invalid temperature", function()
      local valid, errors = ollama:validate_config({
        model = "llama2",
        temperature = 5,
      })
      
      assert.is_false(valid)
      assert.matches("temperature", table.concat(errors, " "))
    end)
  end)

  describe("get_capabilities", function()
    it("returns capability table", function()
      local caps = ollama:get_capabilities()
      
      assert.is_table(caps)
      assert.is_boolean(caps.supports_streaming)
      assert.is_boolean(caps.supports_multiple_generations)
      assert.is_number(caps.max_generations)
    end)
  end)
end)
```

#### Integration Tests

Add E2E tests in `tests/provider_e2e_spec.lua` or create a dedicated file:

```lua
describe("ollama provider E2E", function()
  local providers
  local config

  before_each(function()
    package.loaded["aicommits.providers"] = nil
    package.loaded["aicommits.config"] = nil
    
    providers = require("aicommits.providers")
    config = require("aicommits.config")
  end)

  it("registers ollama provider on setup", function()
    providers.setup()
    
    local provider_list = providers.list()
    assert.is_true(vim.tbl_contains(provider_list, "ollama"))
  end)

  it("retrieves active ollama provider with valid config", function()
    config.setup({
      active_provider = "ollama",
      providers = {
        ollama = {
          enabled = true,
          model = "llama2",
        },
      },
    })
    providers.setup()
    
    local provider, err = providers.get_active_provider()
    
    assert.is_nil(err)
    assert.is_not_nil(provider)
    assert.equals("ollama", provider.name)
  end)
end)
```

Run tests with:
```bash
./app.sh test
```

### Health Check Integration

The health check system automatically validates your provider if it's configured as the active provider. No additional integration needed! But you can test it:

```vim
:checkhealth aicommits
```

This will verify:
- Provider is registered
- Provider is enabled
- Configuration is valid
- All required fields are present

### Configuration Examples

#### User Configuration

Show users how to configure your provider in their Neovim config:

```lua
-- Using Ollama locally
require("aicommits").setup({
  active_provider = "ollama",
  
  providers = {
    ollama = {
      enabled = true,
      endpoint = "http://localhost:11434/api/generate",
      model = "llama2",
      max_length = 50,
      temperature = 0.7,
    },
  },
})
```

#### Environment Variables (optional)

If your provider supports environment variables for API keys:

```lua
-- In your provider implementation
local function get_api_key(config)
  -- Check config first
  if config.api_key and config.api_key ~= "" then
    return config.api_key
  end

  -- Check plugin-specific env var
  local key = vim.env.AICOMMITS_NVIM_OLLAMA_API_KEY
  if key and key ~= "" then
    return key
  end

  -- Check generic env var
  key = vim.env.OLLAMA_API_KEY
  if key and key ~= "" then
    return key
  end

  return nil
end
```

### Reference Implementations

Use these as examples when building your provider:

- **OpenAI Provider** ([`lua/aicommits/providers/openai.lua`](lua/aicommits/providers/openai.lua))
  - Full-featured implementation with all optional methods
  - Shows API key handling with environment variables
  - Demonstrates multiple message generation
  - Good for REST API-based providers

- **Base Provider** ([`lua/aicommits/providers/base.lua`](lua/aicommits/providers/base.lua))
  - Interface definition with documentation
  - Shows required vs optional methods
  - Provides default implementations

- **Provider Tests** ([`tests/provider_e2e_spec.lua`](tests/provider_e2e_spec.lua))
  - Comprehensive test examples
  - Shows how to test registration, configuration, and validation
  - Demonstrates E2E testing patterns

### Checklist for New Providers

Before submitting your provider implementation, ensure:

- [ ] Provider file created in `lua/aicommits/providers/`
- [ ] All required methods implemented (`name`, `generate_commit_message`, `validate_config`)
- [ ] Optional methods implemented as needed (`get_auth_headers`, `get_capabilities`)
- [ ] Provider registered in `lua/aicommits/providers/init.lua`
- [ ] Default configuration added to `lua/aicommits/config.lua`
- [ ] Unit tests created in `tests/providers/` or `tests/`
- [ ] Integration tests added to verify registration and configuration
- [ ] Tests pass (`./app.sh test`)
- [ ] Code formatted (`./app.sh format`)
- [ ] Documentation updated in README.md (add to supported providers list)
- [ ] PR description includes configuration example
- [ ] Health check validates your provider (`:checkhealth aicommits`)

### Common Patterns

#### Error Handling

Always use callbacks for async operations and provide clear error messages:

```lua
function M:generate_commit_message(diff, config, callback)
  http.post(endpoint, headers, body, function(err, response_body)
    if err then
      callback("Network error: " .. err, nil)
      return
    end
    
    local ok, response = pcall(vim.json.decode, response_body)
    if not ok then
      callback("Failed to parse API response", nil)
      return
    end
    
    -- Success case
    callback(nil, processed_messages)
  end)
end
```

#### Configuration Helpers

Create helper functions for complex configuration logic:

```lua
local function get_endpoint(config)
  if config.endpoint and config.endpoint ~= "" then
    return config.endpoint
  end
  
  -- Return default based on environment
  if vim.env.OLLAMA_HOST then
    return vim.env.OLLAMA_HOST .. "/api/generate"
  end
  
  return "http://localhost:11434/api/generate"
end
```

#### Prompt Building

Use the prompts module to build consistent prompts:

```lua
local prompts = require("aicommits.prompts")

local system_prompt = prompts.build_system_prompt(max_length)
local full_prompt = system_prompt .. "\n\n" .. diff
```

### Getting Help

If you need help implementing a provider:

- Review existing provider implementations in `lua/aicommits/providers/`
- Check test examples in `tests/provider_e2e_spec.lua`
- Open a draft PR for early feedback
- Ask questions in GitHub Issues or Discussions

We're happy to help bring new providers to the ecosystem!

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
