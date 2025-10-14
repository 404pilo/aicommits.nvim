# AGENTS.md - aicommits.nvim

> Specialized AI agents for different aspects of aicommits.nvim development

This file documents specialized agents that can help with specific aspects of the aicommits.nvim project. Each agent has deep expertise in its domain and can provide focused assistance for plugin development, provider implementation, testing, documentation, architecture, and user experience.

## Quick Reference

| Agent | Use When |
|-------|----------|
| **Neovim Plugin Dev** | Working on plugin features, commands, keymaps, integrations, health checks |
| **Provider Implementation** | Adding new AI providers (Anthropic, Ollama, etc.), debugging provider issues |
| **Testing & Quality** | Writing tests, fixing failures, improving coverage, mock patterns |
| **Documentation** | Updating docs, creating examples, writing guides, LuaDoc comments |
| **Architecture & Design** | Major refactoring, architectural decisions, performance optimization |
| **Config & UX** | Configuration changes, user experience improvements, error messages |

---

## 1. Neovim Plugin Development Agent

### Identity
- **Role**: Expert in Neovim plugin development with Lua 5.1/LuaJIT
- **Expertise**: Neovim API, plugin architecture, lazy loading, commands, health checks, integrations
- **Scope**: Core plugin functionality, Neovim-specific patterns, runtime compatibility

### When to Use
- Creating new plugin commands (`:AICommit`, `:AICommitHealth`, etc.)
- Implementing health check functionality (`:checkhealth aicommits`)
- Adding keymaps and user commands
- Integrating with other Neovim plugins (neogit, fugitive, telescope)
- Working with Neovim's async patterns (vim.loop, callbacks)
- Debugging Neovim API issues
- Optimizing plugin startup and loading

### Capabilities
- Implement Neovim commands with proper parameter handling
- Create robust health check systems using `vim.health` API
- Design lazy-loadable plugin architectures
- Integrate with popular Neovim plugins (telescope, neogit)
- Use Neovim's async primitives (vim.schedule, vim.loop)
- Handle Neovim version compatibility (0.9+)
- Implement proper error handling and user notifications
- Design plugin APIs that follow Neovim conventions

### Key Context

**Important Files:**
- `lua/aicommits/init.lua` - Plugin entry point and setup
- `lua/aicommits/commands.lua` - Command registration
- `lua/aicommits/health.lua` - Health check implementation
- `lua/aicommits/integrations/neogit.lua` - Neogit integration
- `lua/aicommits/ui/picker.lua` - Custom UI picker with telescope

**Plugin Structure:**
```lua
-- Standard plugin entry point pattern
local M = {}

function M.setup(opts)
  -- 1. Merge config with defaults
  -- 2. Initialize providers
  -- 3. Register commands
  -- 4. Setup integrations
end

return M
```

**Health Check Pattern:**
```lua
-- lua/aicommits/health.lua
function M.check()
  vim.health.start("Section Name")

  if condition then
    vim.health.ok("Check passed")
  else
    vim.health.error("Check failed", "Suggestion to fix")
  end
end
```

### Examples

**Command Registration:**
```lua
-- From lua/aicommits/commands.lua
vim.api.nvim_create_user_command("AICommit", function(opts)
  require("aicommits.commit").generate_and_commit()
end, {
  desc = "Generate AI-powered commit message",
})
```

**Async Pattern:**
```lua
-- Async callback pattern used throughout
http.post(url, headers, body, function(err, response)
  if err then
    vim.schedule(function()
      vim.notify("Error: " .. err, vim.log.levels.ERROR)
    end)
    return
  end

  -- Process response...
end)
```

**Integration Pattern:**
```lua
-- From lua/aicommits/integrations/neogit.lua
local neogit_ok, neogit = pcall(require, "neogit")
if not neogit_ok then
  return
end

-- Add keymap to neogit status buffer
vim.api.nvim_create_autocmd("FileType", {
  pattern = "NeogitStatus",
  callback = function(opts)
    vim.keymap.set("n", "C", function()
      require("aicommits").commit()
    end, { buffer = opts.buf })
  end,
})
```

### Guidelines
- **Always** use `pcall()` when requiring optional dependencies
- **Always** wrap UI updates in `vim.schedule()` when in async context
- Use `vim.notify()` for user-facing messages with appropriate log levels
- Follow Neovim 0.9+ API patterns (avoid deprecated functions)
- Implement health checks for all critical functionality
- Use `vim.api.nvim_create_user_command()` for command registration
- Handle version compatibility gracefully with feature detection
- Keep plugin loading lazy - defer heavy operations to command execution

---

## 2. Provider Implementation Agent

### Identity
- **Role**: Expert in implementing AI provider integrations for aicommits.nvim
- **Expertise**: Provider architecture, API integration, async patterns, configuration validation
- **Scope**: Adding new AI providers (Anthropic, Ollama, Google, etc.), provider interface compliance

### When to Use
- Implementing a new AI provider (Anthropic, Ollama, Google Gemini, etc.)
- Debugging provider API integration issues
- Extending provider capabilities (streaming, multiple generations)
- Fixing provider configuration validation
- Adding custom endpoint support
- Implementing provider authentication patterns
- Troubleshooting HTTP/API errors

### Capabilities
- Implement complete providers following `base.lua` interface contract
- Design provider-specific configuration schemas
- Handle async API calls with proper error handling
- Implement authentication (API keys, bearer tokens, custom headers)
- Parse and validate API responses
- Support custom endpoints and self-hosted models
- Implement provider capability detection
- Write comprehensive provider tests

### Key Context

**Provider Architecture:**
```
User → init.lua → commit.lua → providers/init.lua → providers/{name}.lua → API
                                       ↓
                                 base.lua (interface)
```

**Provider Interface Contract** (`lua/aicommits/providers/base.lua`):
```lua
{
  name = "provider_name",  -- Required: unique identifier

  -- Core method (required)
  generate_commit_message = function(self, diff, config, callback)
    callback(err, messages)  -- err: string|nil, messages: array|nil
  end,

  -- Validation (required)
  validate_config = function(self, config)
    return valid, errors  -- valid: boolean, errors: array
  end,

  -- Auth headers (optional, default: {})
  get_auth_headers = function(self, config)
    return { Authorization = "Bearer " .. api_key }
  end,

  -- Capabilities (optional, default: basic)
  get_capabilities = function(self)
    return {
      supports_streaming = false,
      supports_multiple_generations = false,
      max_generations = 1,
    }
  end
}
```

**Provider Registration** (`lua/aicommits/providers/init.lua`):
```lua
function M.setup()
  -- Register each provider
  local ok, openai = pcall(require, "aicommits.providers.openai")
  if ok then
    M.register("openai", openai)
  end
end
```

**Important Files:**
- `lua/aicommits/providers/base.lua` - Provider interface definition
- `lua/aicommits/providers/init.lua` - Provider registry and management
- `lua/aicommits/providers/openai.lua` - Reference implementation
- `lua/aicommits/http.lua` - HTTP client wrapper (curl-based)
- `lua/aicommits/prompts.lua` - Prompt building utilities
- `CONTRIBUTING.md` (lines 388-1122) - Comprehensive provider implementation guide

### Examples

**Minimal Provider Implementation:**
```lua
-- lua/aicommits/providers/ollama.lua
local base = require("aicommits.providers.base")
local http = require("aicommits.http")
local prompts = require("aicommits.prompts")

local M = base.new({ name = "ollama" })

function M:validate_config(config)
  local errors = {}
  if not config.model or config.model == "" then
    table.insert(errors, "model is required")
  end
  return #errors == 0, errors
end

function M:generate_commit_message(diff, config, callback)
  local endpoint = config.endpoint or "http://localhost:11434/api/generate"
  local request_body = {
    model = config.model or "llama2",
    prompt = prompts.build_system_prompt(config.max_length or 50) .. "\n\n" .. diff,
    stream = false,
  }

  http.post(endpoint, self:get_auth_headers(config), vim.json.encode(request_body), function(err, response_body)
    if err then
      callback(err, nil)
      return
    end

    local ok, response = pcall(vim.json.decode, response_body)
    if not ok or not response.response then
      callback("Invalid API response", nil)
      return
    end

    callback(nil, prompts.process_messages({ response.response }))
  end)
end

return M
```

**API Key Pattern (from OpenAI provider):**
```lua
local function get_api_key(config)
  -- Priority 1: config.api_key
  if config.api_key and config.api_key ~= "" then
    return config.api_key
  end

  -- Priority 2: plugin-specific env var
  local key = vim.env.AICOMMITS_NVIM_OPENAI_API_KEY
  if key and key ~= "" then
    return key
  end

  -- Priority 3: standard provider env var
  key = vim.env.OPENAI_API_KEY
  if key and key ~= "" then
    return key
  end

  return nil
end
```

**Error Handling Pattern:**
```lua
-- Always check each step and provide helpful errors
local ok, response = pcall(vim.json.decode, response_body)
if not ok then
  callback("Failed to parse API response: " .. tostring(response), nil)
  return
end

if response.error then
  callback("Provider API Error: " .. (response.error.message or vim.inspect(response.error)), nil)
  return
end

if not response.choices or #response.choices == 0 then
  callback("No commit messages were generated. Try again.", nil)
  return
end
```

### Guidelines
- **Always** implement provider using `base.new({ name = "provider_name" })`
- **Always** use callbacks with signature `callback(err, result)` (error-first pattern)
- **Always** validate configuration thoroughly in `validate_config()`
- Use `prompts.build_system_prompt(max_length)` for consistent prompt formatting
- Use `prompts.process_messages(messages)` to validate/clean commit messages
- Support environment variables for API keys following the pattern: `AICOMMITS_NVIM_{PROVIDER}_API_KEY`
- Provide clear, actionable error messages that help users fix issues
- Return empty table `{}` from `get_auth_headers()` if no auth required (local models)
- Document provider capabilities accurately in `get_capabilities()`
- Follow async patterns - never block the UI during API calls
- Add provider to `lua/aicommits/providers/init.lua:setup()` after implementation
- Add default config to `lua/aicommits/config.lua:defaults.providers`

---

## 3. Testing & Quality Agent

### Identity
- **Role**: Expert in Lua testing with busted framework and test-driven development
- **Expertise**: Unit testing, integration testing, mocking, test organization, CI/CD validation
- **Scope**: Test suite maintenance, mock patterns, coverage, test debugging

### When to Use
- Writing tests for new features or providers
- Fixing failing test cases
- Creating mock implementations for HTTP/git/external dependencies
- Improving test coverage
- Debugging test failures in CI
- Refactoring tests for better maintainability
- Adding edge case tests

### Capabilities
- Write comprehensive unit tests using busted framework
- Create integration tests for end-to-end workflows
- Implement sophisticated mocks for HTTP, git, and external systems
- Test async callbacks and error handling paths
- Validate configuration schemas
- Test Neovim API interactions
- Use `app.sh` test commands that mirror CI exactly
- Debug test failures and fix flaky tests

### Key Context

**Test Infrastructure:**
- **Framework**: busted (Lua testing framework)
- **Test Runner**: `app.sh test` (runs exact same checks as CI)
- **Mock System**: `tests/helpers/mock.lua`
- **Minimal Init**: `tests/minimal_init.lua`
- **Total Tests**: 128+ test cases (as of latest run)

**Test Structure:**
```
tests/
├── minimal_init.lua           # Test setup and initialization
├── helpers/
│   └── mock.lua              # Mock utilities
├── config_spec.lua           # Config system tests
├── git_spec.lua              # Git operations tests
├── commands_spec.lua         # Command tests
├── integration_spec.lua      # Full workflow tests
├── neogit_integration_spec.lua
├── provider_e2e_spec.lua     # Provider testing
├── edge_cases_spec.lua
├── performance_spec.lua
└── ...
```

**Important Files:**
- `tests/helpers/mock.lua` - Mock utilities for vim.fn.system, environment vars, etc.
- `tests/minimal_init.lua` - Test environment setup
- `app.sh` - Development tool (setup, test, lint, ci commands)
- `.github/workflows/test.yml` - CI configuration (mirrors app.sh)

### Examples

**Basic Test Structure:**
```lua
-- tests/provider_spec.lua
describe("provider", function()
  local provider

  before_each(function()
    package.loaded["aicommits.providers.myprovider"] = nil
    provider = require("aicommits.providers.myprovider")
  end)

  describe("validate_config", function()
    it("accepts valid configuration", function()
      local valid, errors = provider:validate_config({
        model = "gpt-4",
        api_key = "sk-test",
      })

      assert.is_true(valid)
      assert.equals(0, #errors)
    end)

    it("rejects missing required fields", function()
      local valid, errors = provider:validate_config({})

      assert.is_false(valid)
      assert.is_true(#errors > 0)
      assert.matches("model", errors[1])
    end)
  end)
end)
```

**Mock Pattern for System Calls:**
```lua
local mock = require("tests.helpers.mock")

describe("git operations", function()
  it("detects git repository", function()
    local cleanup = mock.mock_system({
      ["git rev%-parse %-%-is%-inside%-work%-tree"] = "true\n",
    })

    local git = require("aicommits.git")
    assert.is_true(git.is_git_repo())

    cleanup()  -- Always cleanup mocks
  end)
end)
```

**Mock Pattern for HTTP Responses:**
```lua
local mock = require("tests.helpers.mock")

it("handles API errors gracefully", function()
  local cleanup = mock.mock_system({
    ["curl.*"] = vim.json.encode({
      error = { message = "Invalid API key" }
    }),
  })

  local called = false
  provider:generate_commit_message("diff", {}, function(err, result)
    called = true
    assert.is_not_nil(err)
    assert.matches("Invalid API key", err)
    assert.is_nil(result)
  end)

  assert.is_true(called, "Callback should be invoked")
  cleanup()
end)
```

**Testing Async Callbacks:**
```lua
it("calls callback with generated messages", function()
  local callback_called = false
  local error_result = nil
  local messages_result = nil

  provider:generate_commit_message("diff", config, function(err, messages)
    callback_called = true
    error_result = err
    messages_result = messages
  end)

  assert.is_true(callback_called)
  assert.is_nil(error_result)
  assert.is_table(messages_result)
  assert.is_true(#messages_result > 0)
end)
```

**Running Tests:**
```bash
# Run all tests (same as CI)
./app.sh test

# Check formatting (same as CI)
./app.sh lint

# Run all CI checks locally
./app.sh ci

# Run specific test file
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/provider_spec.lua"
```

### Guidelines
- **Always** run `./app.sh ci` before submitting PRs (matches CI exactly)
- Use `describe()` for test groups, `it()` for individual tests
- Use `before_each()` and `after_each()` for setup/cleanup
- **Always** cleanup mocks to avoid test pollution
- Reload modules with `package.loaded["module"] = nil` before tests
- Test both success and error paths
- Validate async callbacks are actually called
- Use meaningful assertion messages for clarity
- Test edge cases: empty inputs, nil values, malformed responses
- Mock external dependencies (HTTP, git, file system)
- Keep tests isolated - no dependencies between test files
- Use `assert.equals()` for exact matches, `assert.matches()` for patterns
- Test provider interface compliance for all new providers

---

## 4. Documentation Agent

### Identity
- **Role**: Expert in technical writing, API documentation, and developer guides
- **Expertise**: README updates, LuaDoc comments, help files, tutorials, configuration examples
- **Scope**: All project documentation including user-facing and developer-facing content

### When to Use
- Updating README.md with new features
- Writing LuaDoc comments for functions
- Creating provider implementation guides
- Documenting configuration options
- Writing tutorial content
- Creating usage examples
- Updating CONTRIBUTING.md
- Writing help documentation (`:help aicommits`)

### Capabilities
- Write clear, concise user-facing documentation
- Create comprehensive API documentation with LuaDoc
- Develop step-by-step implementation guides
- Document configuration schemas with examples
- Write effective code examples and tutorials
- Structure documentation for different audiences (users vs developers)
- Create visual diagrams for architecture documentation
- Maintain consistency across documentation files

### Key Context

**Documentation Structure:**
- `README.md` - User-facing documentation, setup, usage, configuration
- `CONTRIBUTING.md` - Developer guide, adding providers, testing, code style
- `doc/aicommits.txt` - Vim help documentation
- `memory-bank/` - Project memory bank (technical context, architecture, progress)
- Code comments - LuaDoc format for functions

**LuaDoc Format:**
```lua
--- Brief description of what the function does
--- @param param_name type Description of parameter
--- @param optional_param? type Optional parameter (note the ?)
--- @return type description Description of return value
--- @return type description Second return value
function M.function_name(param_name, optional_param)
  -- Implementation
end
```

**Important Files:**
- `README.md` - Main user documentation
- `CONTRIBUTING.md` - Comprehensive developer guide (includes provider guide)
- `memory-bank/systemPatterns.md` - Architecture documentation
- `memory-bank/techContext.md` - Technical details and constraints
- All `.lua` files - Should have LuaDoc comments on public functions

### Examples

**README Configuration Example:**
```markdown
## Configuration

All options with defaults:

```lua
require("aicommits").setup({
  -- Provider Configuration
  active_provider = "openai",  -- Which AI provider to use

  providers = {
    openai = {
      enabled = true,          -- Enable/disable this provider
      model = "gpt-4.1-nano",  -- Which model to use
      max_length = 50,         -- Max characters in commit message
      generate = 1,            -- Number of options (1-5)
    },
  },
})
```
```

**LuaDoc Example:**
```lua
--- Generate commit message(s) from a git diff
--- @param diff string The git diff output to analyze
--- @param config table Provider-specific configuration options
--- @param callback function Callback function with signature (error, messages)
---   - error: string|nil Error message if generation failed
---   - messages: table|nil Array of generated commit message strings
function M:generate_commit_message(diff, config, callback)
  -- Implementation
end
```

**Provider Guide Pattern (from CONTRIBUTING.md):**
```markdown
### Step 1: Create Provider File

Create a new file in `lua/aicommits/providers/` for your provider:

```bash
touch lua/aicommits/providers/ollama.lua
```

### Step 2: Implement Basic Structure

```lua
-- lua/aicommits/providers/ollama.lua
local base = require("aicommits.providers.base")
local M = base.new({ name = "ollama" })
return M
```

[Continue with detailed steps...]
```

**Troubleshooting Section Pattern:**
```markdown
## Troubleshooting

**"OpenAI API key not found"**

Set the environment variable and restart Neovim:
```bash
export AICOMMITS_NVIM_OPENAI_API_KEY="sk-..."
```

**"No staged changes found"**

Run `git add` first to stage your changes.
```

### Guidelines
- Use **clear, active voice** in all documentation
- **Always** provide complete, runnable code examples
- Document **both** success and error cases
- Use proper markdown formatting for code blocks with language tags
- Keep configuration examples up-to-date with actual defaults
- Link to related documentation sections when relevant
- Use tables for quick reference information
- Provide context before technical details
- Include "Why" explanations, not just "What" and "How"
- Use LuaDoc format consistently for all public functions
- Update README when adding user-facing features
- Update CONTRIBUTING when adding developer patterns
- Add examples for every configuration option
- Document environment variables and their priorities

---

## 5. Architecture & Design Agent

### Identity
- **Role**: Expert in software architecture, design patterns, and system design
- **Expertise**: Plugin architecture, provider patterns, async design, refactoring strategies
- **Scope**: Architectural decisions, major refactoring, design patterns, performance optimization

### When to Use
- Planning major architectural changes
- Refactoring existing systems
- Designing new subsystems or features
- Making design pattern decisions
- Performance optimization at architectural level
- Evaluating trade-offs between approaches
- Planning breaking changes
- Reviewing system design for maintainability

### Capabilities
- Design extensible plugin architectures
- Apply appropriate design patterns (Strategy, Registry, Abstract Factory)
- Plan non-breaking migrations and refactoring strategies
- Optimize async patterns and data flow
- Evaluate architectural trade-offs
- Design for testability and maintainability
- Create clear separation of concerns
- Plan scalable system growth

### Key Context

**Current Architecture (from memory-bank/systemPatterns.md):**
```
User Commands (:AICommit)
        ↓
    init.lua (plugin entry point)
        ↓
    commit.lua (orchestration)
        ↓
    ┌─────────────┬──────────────┬──────────────┐
    ↓             ↓              ↓              ↓
 git.lua    providers/    ui/picker.lua   notifications
            (AI layer)
```

**Design Patterns in Use:**
1. **Strategy Pattern**: Provider selection at runtime
2. **Registry Pattern**: Central provider registry
3. **Abstract Factory**: Provider interface
4. **Callback Pattern**: Async operations
5. **Singleton**: Config instance, provider registry

**Key Architectural Files:**
- `memory-bank/systemPatterns.md` - Architecture decisions and patterns
- `memory-bank/projectBrief.md` - Project goals and scope
- `lua/aicommits/providers/base.lua` - Provider interface definition
- `lua/aicommits/providers/init.lua` - Provider registry implementation
- `lua/aicommits/config.lua` - Configuration architecture

### Examples

**Provider Architecture Pattern:**
```lua
-- Abstract interface (base.lua)
M.Provider = {
  name = nil,
  generate_commit_message = function(self, diff, config, callback)
    error("Must implement")
  end,
  validate_config = function(self, config)
    return true, {}
  end,
}

-- Registry pattern (providers/init.lua)
local providers = {}

function M.register(name, provider)
  providers[name] = provider
end

function M.get(name)
  return providers[name]
end

-- Concrete implementation (providers/openai.lua)
local M = base.new({ name = "openai" })
function M:generate_commit_message(diff, config, callback)
  -- Implementation
end
```

**Configuration Architecture:**
```lua
-- Nested provider-specific config
{
  active_provider = "openai",  -- Runtime selection
  providers = {
    openai = {
      model = "gpt-4",
      api_key = "...",
    },
    anthropic = {
      model = "claude-3-sonnet",
      api_key = "...",
    },
  }
}
```

**Async Flow Pattern:**
```lua
-- Orchestration layer (commit.lua)
function M.generate_and_commit()
  -- 1. Get git diff
  git.get_staged_diff(function(err, diff)
    if err then return handle_error(err) end

    -- 2. Get active provider
    local provider = providers.get_active_provider()

    -- 3. Generate messages
    provider:generate_commit_message(diff, config, function(err, messages)
      if err then return handle_error(err) end

      -- 4. Show picker
      ui.show_picker(messages, function(selected)
        -- 5. Commit
        git.commit(selected)
      end)
    end)
  end)
end
```

### Guidelines
- **Separation of Concerns**: Keep layers isolated (git, providers, UI, config)
- **Interface Segregation**: Providers only implement what they need
- **Dependency Inversion**: Depend on abstractions (base.lua), not implementations
- **Open/Closed Principle**: Open for extension (add providers), closed for modification
- Use **async callbacks** for all I/O operations (network, file, git)
- Design for **testability** - use dependency injection and mocks
- Maintain **backward compatibility** when possible, document breaking changes
- Use **registry pattern** for pluggable components
- **Document architectural decisions** in memory-bank/systemPatterns.md
- Consider **performance implications** of design choices
- Plan **migration paths** for refactoring
- Favor **composition over inheritance**

---

## 6. Configuration & User Experience Agent

### Identity
- **Role**: Expert in plugin configuration, user workflows, and developer experience
- **Expertise**: Config validation, health checks, error messages, user flows, UX patterns
- **Scope**: Configuration system, validation, health checks, notifications, error handling

### When to Use
- Designing configuration schemas
- Improving validation and error messages
- Implementing health check functionality
- Enhancing user notifications
- Fixing UX issues or workflow problems
- Adding configuration options
- Improving setup experience
- Making error messages more helpful

### Capabilities
- Design intuitive configuration schemas
- Implement comprehensive validation with helpful errors
- Create robust health check systems
- Write clear, actionable error messages
- Design smooth user workflows
- Handle edge cases gracefully
- Provide helpful defaults
- Create progressive disclosure in configuration

### Key Context

**Configuration System:**
- `lua/aicommits/config.lua` - Config management and validation
- `lua/aicommits/health.lua` - Health check system (`:checkhealth aicommits`)
- Default config in `config.lua:defaults`
- User config merged via `setup(opts)`

**Health Check Categories:**
1. Required Dependencies (Neovim, git, curl)
2. Provider Configuration (registration, validation, API keys)
3. Configuration Validity (schema, required fields)
4. Current Environment (git repo, staged changes)
5. Optional Integrations (neogit, fugitive)

**Important Files:**
- `lua/aicommits/config.lua` - Configuration system
- `lua/aicommits/health.lua` - Health checks
- `lua/aicommits/notifications.lua` - User notifications
- `README.md` - User-facing config docs

### Examples

**Configuration Schema with Defaults:**
```lua
-- lua/aicommits/config.lua
M.defaults = {
  active_provider = "openai",

  providers = {
    openai = {
      enabled = true,
      api_key = nil,  -- nil = use env var
      endpoint = nil,  -- nil = use default
      model = "gpt-4.1-nano",
      max_length = 50,
      generate = 1,
    },
  },

  ui = {
    use_custom_picker = true,
    picker = {
      width = 0.4,
      height = 0.3,
      border = "rounded",
    },
  },
}
```

**Configuration Validation:**
```lua
function M.validate()
  local errors = {}

  -- Validate active_provider
  local active = M.get("active_provider")
  if not active or active == "" then
    table.insert(errors, "active_provider is required")
  end

  -- Validate provider exists
  local provider_config = M.get("providers." .. active)
  if not provider_config then
    table.insert(errors, string.format("No configuration for provider '%s'", active))
  end

  return #errors == 0, errors
end
```

**Health Check Implementation:**
```lua
-- lua/aicommits/health.lua
local function check_provider()
  local config = require("aicommits.config")
  local providers = require("aicommits.providers")

  local active_name = config.get("active_provider")

  if not active_name then
    vim.health.error("No active provider configured", "Set 'active_provider' in your configuration")
    return false
  end

  vim.health.ok(string.format("Active provider: %s", active_name))

  local provider = providers.get(active_name)
  if not provider then
    vim.health.error(
      string.format("Provider '%s' not found", active_name),
      string.format("Available providers: %s", table.concat(providers.list(), ", "))
    )
    return false
  end

  local valid, errors = provider:validate_config(config.get("providers." .. active_name))
  if not valid then
    vim.health.error("Provider configuration is invalid", errors)
    return false
  end

  vim.health.ok("Provider configuration is valid")
  return true
end
```

**Helpful Error Messages:**
```lua
-- Bad error message ❌
callback("API error", nil)

-- Good error message ✅
callback(
  "OpenAI API Error: " .. error_message .. "\n" ..
  "Please check your API key and try again.\n" ..
  "Set 'providers.openai.api_key' in config or environment variable AICOMMITS_NVIM_OPENAI_API_KEY",
  nil
)
```

**User Notifications:**
```lua
-- lua/aicommits/notifications.lua
function M.error(message)
  vim.schedule(function()
    vim.notify("[aicommits] " .. message, vim.log.levels.ERROR)
  end)
end

function M.info(message)
  vim.schedule(function()
    vim.notify("[aicommits] " .. message, vim.log.levels.INFO)
  end)
end
```

### Guidelines
- **Provide helpful defaults** - minimize required configuration
- **Validate early** - catch config errors at setup time, not runtime
- **Clear error messages** - tell users exactly what's wrong and how to fix it
- **Progressive disclosure** - simple setup works, advanced options available
- Use **vim.health** API for comprehensive health checks
- Check **all preconditions** before operations (git repo, staged changes, API keys)
- Provide **actionable suggestions** in error messages
- Use **vim.notify** with appropriate log levels (ERROR, WARN, INFO)
- **Document all options** with examples in README
- Support **environment variables** as config fallbacks
- **Validate API keys exist** without exposing them
- Make **health checks informative** - check dependencies, config, environment
- Use **consistent prefixes** in notifications: `[aicommits]`
- Handle **edge cases gracefully** with clear messages

---

## Project-Specific Context

### Development Workflow

**Key Commands:**
```bash
# Setup (first time)
./app.sh setup

# Run tests (same as CI)
./app.sh test

# Check formatting (same as CI)
./app.sh lint

# Auto-format code
./app.sh format

# Run all CI checks locally
./app.sh ci

# Check environment
./app.sh status
```

**Git Workflow:**
```bash
# Create feature branch
git checkout -b feature/your-feature

# Make changes and test
./app.sh ci

# Commit with conventional commits
git commit -m "feat: add new feature"
```

### Key Files and Locations

**Core Plugin Files:**
- `lua/aicommits/init.lua` - Plugin entry point, setup function
- `lua/aicommits/config.lua` - Configuration management
- `lua/aicommits/commit.lua` - Commit orchestration
- `lua/aicommits/git.lua` - Git operations
- `lua/aicommits/http.lua` - HTTP client (curl wrapper)

**Provider System:**
- `lua/aicommits/providers/base.lua` - Provider interface
- `lua/aicommits/providers/init.lua` - Provider registry
- `lua/aicommits/providers/openai.lua` - OpenAI implementation

**Testing:**
- `tests/` - All test files
- `tests/helpers/mock.lua` - Mock utilities
- `tests/minimal_init.lua` - Test setup

**Documentation:**
- `README.md` - User documentation
- `CONTRIBUTING.md` - Developer guide (includes comprehensive provider guide)
- `memory-bank/` - Project memory bank

### Testing Commands

```bash
# Run all tests
./app.sh test

# Run specific test file
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/your_test_spec.lua"

# Format code
./app.sh format

# Check formatting
./app.sh lint

# Run full CI suite locally
./app.sh ci
```

### Code Style

**Lua Conventions:**
```lua
-- Module structure
local M = {}

-- Constants
local MAX_RETRIES = 3

-- Private functions (prefixed with _)
local function _internal_helper()
end

-- Public functions
function M.public_function()
end

return M
```

**Naming:**
- Modules: `snake_case`
- Functions: `snake_case`
- Constants: `UPPER_SNAKE_CASE`
- Private functions: `_prefix`

**Documentation:**
- Use LuaDoc format for all public functions
- Include @param and @return annotations
- Provide brief descriptions

**Formatting:**
- Use stylua for automatic formatting
- Run `./app.sh format` before commits
- CI enforces formatting with `./app.sh lint`

### Architecture Highlights

**Provider Pattern:**
- Abstract base interface in `base.lua`
- Registry pattern for provider management
- Strategy pattern for runtime provider selection
- Each provider self-contained and testable

**Async Design:**
- Callback-based async for HTTP and git operations
- Error-first callback pattern: `callback(err, result)`
- Always wrap UI updates in `vim.schedule()`

**Configuration:**
- Nested structure: `providers.{name}.{option}`
- Provider-specific namespaces prevent collisions
- Defaults merged with user config
- Validation at setup time

**Testing:**
- Mock system for HTTP, git, system calls
- Unit tests for individual modules
- Integration tests for workflows
- E2E tests for provider implementations

---

## How to Use These Agents

### Selecting the Right Agent

**Ask yourself:**
1. **What am I working on?** (Feature type determines agent)
2. **What layer of the system?** (Plugin, provider, config, tests, docs)
3. **What's the scope?** (New feature, bug fix, architecture change)

**Quick Decision Tree:**
- Adding/fixing provider → **Provider Implementation Agent**
- Plugin command/integration → **Neovim Plugin Dev Agent**
- Writing/fixing tests → **Testing & Quality Agent**
- Updating documentation → **Documentation Agent**
- Major refactoring → **Architecture & Design Agent**
- Config/UX improvement → **Config & UX Agent**

### Multi-Agent Workflows

Some tasks benefit from multiple agents in sequence:

**Adding a New Provider (Multi-Agent):**
1. **Provider Implementation Agent** - Implement provider following interface
2. **Testing & Quality Agent** - Write comprehensive tests
3. **Documentation Agent** - Update README and CONTRIBUTING.md
4. **Config & UX Agent** - Add health checks and validation

**Major Refactoring (Multi-Agent):**
1. **Architecture & Design Agent** - Plan refactoring strategy
2. **Neovim Plugin Dev Agent** - Update plugin integration points
3. **Provider Implementation Agent** - Update provider interfaces
4. **Testing & Quality Agent** - Update tests for new structure
5. **Documentation Agent** - Update architecture docs

**UX Improvement (Multi-Agent):**
1. **Config & UX Agent** - Design better configuration schema
2. **Neovim Plugin Dev Agent** - Implement new commands/integrations
3. **Testing & Quality Agent** - Test new workflows
4. **Documentation Agent** - Document new patterns

---

## Getting Help

### Resources

- **Provider Implementation**: See CONTRIBUTING.md lines 388-1122 for comprehensive guide
- **Testing Patterns**: See `tests/` directory for examples
- **Architecture Decisions**: See `memory-bank/systemPatterns.md`
- **Technical Context**: See `memory-bank/techContext.md`

### When Stuck

1. Review reference implementations:
   - OpenAI provider: `lua/aicommits/providers/openai.lua`
   - Test examples: `tests/provider_e2e_spec.lua`
   - Mock patterns: `tests/helpers/mock.lua`

2. Check health status:
   ```vim
   :checkhealth aicommits
   ```

3. Run local CI checks:
   ```bash
   ./app.sh ci
   ```

4. Ask for help:
   - GitHub Issues for bugs
   - GitHub Discussions for questions
   - PR comments for code review

### Contributing

Before submitting changes:
- [ ] Run `./app.sh ci` (must pass - same as CI)
- [ ] Update relevant documentation
- [ ] Add/update tests as needed
- [ ] Follow code style guidelines
- [ ] Use conventional commit messages

---

## Maintenance

### Keeping This File Updated

Update AGENTS.md when:
- Adding new architectural patterns
- Introducing new systems or subsystems
- Changing provider interface
- Adding new testing patterns
- Updating development workflows
- Adding new dependencies or tools

### Version History

- **v1.0** (2025-10-14): Initial AGENTS.md created with 6 specialized agents
  - Based on provider architecture refactoring (milestone 2)
  - Comprehensive provider implementation guide integrated
  - Test suite at 128+ passing tests
