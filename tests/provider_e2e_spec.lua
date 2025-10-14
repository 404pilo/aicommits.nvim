-- End-to-end tests for the provider system
-- These tests capture the manual verification phases for the provider refactoring
describe("provider system E2E", function()
  local aicommits
  local config
  local providers

  before_each(function()
    -- Clear package cache
    package.loaded["aicommits"] = nil
    package.loaded["aicommits.config"] = nil
    package.loaded["aicommits.providers"] = nil
    package.loaded["aicommits.providers.base"] = nil
    package.loaded["aicommits.providers.openai"] = nil

    -- Load fresh modules
    aicommits = require("aicommits")
    config = require("aicommits.config")
    providers = require("aicommits.providers")
  end)

  describe("Phase 1: Basic loading & initialization", function()
    it("loads provider module successfully", function()
      assert.is_not_nil(providers)
      assert.is_function(providers.setup)
      assert.is_function(providers.register)
      assert.is_function(providers.get_active_provider)
      assert.is_function(providers.list)
      assert.is_function(providers.get)
    end)

    it("loads provider base module successfully", function()
      local base = require("aicommits.providers.base")
      assert.is_not_nil(base)
      assert.is_function(base.new)
      assert.is_table(base.Provider)
    end)

    it("loads openai provider module successfully", function()
      local openai = require("aicommits.providers.openai")
      assert.is_not_nil(openai)
      assert.equals("openai", openai.name)
    end)
  end)

  describe("Phase 2: Provider registration & discovery", function()
    before_each(function()
      providers.setup()
    end)

    it("registers openai provider on setup", function()
      local provider_list = providers.list()
      assert.is_table(provider_list)
      -- list() returns array of names, not dictionary
      assert.is_true(vim.tbl_contains(provider_list, "openai"))
    end)

    it("can retrieve registered openai provider", function()
      local openai = providers.get("openai")
      assert.is_not_nil(openai)
      assert.equals("openai", openai.name)
    end)

    it("registered provider has required methods", function()
      local openai = providers.get("openai")
      assert.is_function(openai.generate_commit_message)
      assert.is_function(openai.validate_config)
      assert.is_function(openai.get_auth_headers)
      assert.is_function(openai.get_capabilities)
    end)
  end)

  describe("Phase 3: Configuration loading", function()
    it("loads default nested configuration structure", function()
      config.setup({})

      assert.equals("openai", config.get("active_provider"))
      assert.is_table(config.get("providers"))
      assert.is_table(config.get("providers.openai"))
    end)

    it("loads nested provider-specific configuration", function()
      config.setup({})

      assert.equals("gpt-4.1-nano", config.get("providers.openai.model"))
      assert.equals(50, config.get("providers.openai.max_length"))
      assert.equals(1, config.get("providers.openai.generate"))
    end)

    it("merges custom provider configuration with defaults", function()
      config.setup({
        providers = {
          openai = {
            model = "gpt-4-turbo",
            max_length = 100,
          },
        },
      })

      -- Custom values
      assert.equals("gpt-4-turbo", config.get("providers.openai.model"))
      assert.equals(100, config.get("providers.openai.max_length"))

      -- Default values preserved
      assert.equals(1, config.get("providers.openai.generate"))
      assert.equals(0.7, config.get("providers.openai.temperature"))
    end)
  end)

  describe("Phase 4: Active provider retrieval", function()
    before_each(function()
      config.setup({})
      providers.setup()
    end)

    it("retrieves active provider successfully", function()
      local provider, err = providers.get_active_provider()

      assert.is_nil(err)
      assert.is_not_nil(provider)
      assert.equals("openai", provider.name)
    end)

    it("active provider has all required methods", function()
      local provider, err = providers.get_active_provider()

      assert.is_nil(err)
      assert.is_function(provider.generate_commit_message)
      assert.is_function(provider.validate_config)
      assert.is_function(provider.get_auth_headers)
    end)

    it("returns error when active provider not configured", function()
      config.setup({ active_provider = "nonexistent" })

      local provider, err = providers.get_active_provider()

      assert.is_nil(provider)
      assert.is_not_nil(err)
      assert.matches("not found", err)
    end)

    it("returns error when active provider is empty", function()
      config.setup({ active_provider = "" })

      local provider, err = providers.get_active_provider()

      assert.is_nil(provider)
      assert.is_not_nil(err)
      assert.matches("No active provider", err)
    end)
  end)

  describe("Phase 5: Provider validation", function()
    local openai_provider

    before_each(function()
      providers.setup()
      openai_provider = providers.get("openai")
    end)

    it("validates correct configuration", function()
      local valid, errors = openai_provider:validate_config({
        model = "gpt-4.1-nano",
        api_key = "test_key",
      })

      assert.is_true(valid)
      assert.equals(0, #errors)
    end)

    it("rejects configuration with missing model", function()
      local valid, errors = openai_provider:validate_config({
        api_key = "test_key",
      })

      assert.is_false(valid)
      assert.is_true(#errors > 0)
      assert.matches("model", errors[1])
    end)

    it("rejects configuration with empty model", function()
      local valid, errors = openai_provider:validate_config({
        model = "",
        api_key = "test_key",
      })

      assert.is_false(valid)
      assert.is_true(#errors > 0)
    end)

    it("allows missing api_key (can come from environment)", function()
      local valid, errors = openai_provider:validate_config({
        model = "gpt-4.1-nano",
      })

      -- Should be valid because API key can come from OPENAI_API_KEY env var
      assert.is_true(valid)
      assert.equals(0, #errors)
    end)

    it("validates configuration through get_active_provider", function()
      config.setup({
        providers = {
          openai = {
            model = "", -- Invalid: empty model
          },
        },
      })

      local provider, err = providers.get_active_provider()

      assert.is_nil(provider)
      assert.is_not_nil(err)
      assert.matches("invalid", err)
    end)
  end)

  describe("Phase 6: Provider capabilities", function()
    local openai_provider

    before_each(function()
      providers.setup()
      openai_provider = providers.get("openai")
    end)

    it("returns capabilities object", function()
      local capabilities = openai_provider:get_capabilities()

      assert.is_table(capabilities)
      assert.is_not_nil(capabilities.supports_streaming)
      assert.is_not_nil(capabilities.supports_multiple_generations)
      assert.is_not_nil(capabilities.max_generations)
    end)

    it("has expected openai capabilities", function()
      local capabilities = openai_provider:get_capabilities()

      -- OpenAI supports multiple generations via the 'n' parameter
      assert.is_true(capabilities.supports_multiple_generations)
      assert.is_true(capabilities.max_generations > 1)
    end)
  end)

  describe("Phase 7: Complete plugin lifecycle with providers", function()
    it("initializes plugin with provider system", function()
      aicommits.setup({
        providers = {
          openai = {
            model = "gpt-4.1-nano",
            max_length = 72,
          },
        },
      })

      -- Plugin initialized
      assert.is_true(aicommits.is_initialized())

      -- Config loaded
      assert.equals("gpt-4.1-nano", config.get("providers.openai.model"))
      assert.equals(72, config.get("providers.openai.max_length"))

      -- Provider available
      local provider, err = providers.get_active_provider()
      assert.is_nil(err)
      assert.equals("openai", provider.name)
    end)

    it("handles complete workflow from setup to provider access", function()
      -- Step 1: Setup
      aicommits.setup({})

      -- Step 2: Verify config
      local valid, _ = config.validate()
      assert.is_true(valid)

      -- Step 3: Get provider
      local provider, err = providers.get_active_provider()
      assert.is_nil(err)
      assert.equals("openai", provider.name)

      -- Step 4: Validate provider config
      local provider_config = config.get("providers.openai")
      local config_valid, _ = provider:validate_config(provider_config)
      assert.is_true(config_valid)
    end)
  end)

  describe("Phase 8: Error handling", function()
    it("handles invalid provider gracefully", function()
      config.setup({ active_provider = "invalid_provider" })
      providers.setup()

      local provider, err = providers.get_active_provider()

      assert.is_nil(provider)
      assert.is_string(err)
      assert.matches("not found", err)
    end)

    it("handles disabled provider gracefully", function()
      config.setup({
        providers = {
          openai = {
            enabled = false,
          },
        },
      })
      providers.setup()

      local provider, err = providers.get_active_provider()

      assert.is_nil(provider)
      assert.is_string(err)
      assert.matches("disabled", err)
    end)

    it("handles missing provider configuration", function()
      config.setup({
        active_provider = "custom_provider", -- Provider that doesn't exist
        providers = {
          custom_provider = nil, -- Explicitly no config
        },
      })
      providers.setup()

      local provider, err = providers.get_active_provider()

      assert.is_nil(provider)
      assert.is_string(err)
      assert.matches("not found", err)
    end)
  end)

  describe("Phase 9: Provider registry management", function()
    it("can register custom providers", function()
      local base = require("aicommits.providers.base")

      local custom_provider = base.new({
        name = "test_provider",
        generate_commit_message = function(self, diff, config, callback)
          callback(nil, { "test commit message" })
        end,
        validate_config = function(self, config)
          return true, {}
        end,
      })

      providers.register("test_provider", custom_provider)

      local registered = providers.get("test_provider")
      assert.is_not_nil(registered)
      assert.equals("test_provider", registered.name)
    end)

    it("prevents registering providers with empty names", function()
      local base = require("aicommits.providers.base")

      local custom_provider = base.new({
        name = "test",
      })

      assert.has_error(function()
        providers.register("", custom_provider)
      end)
    end)

    it("lists all registered providers", function()
      providers.setup()

      local provider_list = providers.list()
      assert.is_table(provider_list)
      -- list() returns array of names, not dictionary
      assert.is_true(vim.tbl_contains(provider_list, "openai"))
    end)
  end)

  describe("Phase 10: Vertex AI provider integration", function()
    before_each(function()
      -- Clear package cache
      package.loaded["aicommits.providers.vertex"] = nil
      providers.setup()
    end)

    it("registers vertex provider on setup", function()
      local provider_list = providers.list()
      assert.is_table(provider_list)
      assert.is_true(vim.tbl_contains(provider_list, "vertex"))
    end)

    it("can retrieve registered vertex provider", function()
      local vertex = providers.get("vertex")
      assert.is_not_nil(vertex)
      assert.equals("vertex", vertex.name)
    end)

    it("vertex provider has required methods", function()
      local vertex = providers.get("vertex")
      assert.is_function(vertex.generate_commit_message)
      assert.is_function(vertex.validate_config)
      assert.is_function(vertex.get_auth_headers)
      assert.is_function(vertex.get_capabilities)
    end)

    it("validates vertex configuration correctly", function()
      local vertex = providers.get("vertex")

      -- Valid configuration
      local valid, errors = vertex:validate_config({
        model = "gemini-2.0-flash-lite",
        project = "my-project",
        location = "us-central1",
        api_key = "test_key",
      })
      assert.is_true(valid)
      assert.equals(0, #errors)

      -- Invalid: missing project
      valid, errors = vertex:validate_config({
        model = "gemini-2.0-flash-lite",
        location = "us-central1",
        api_key = "test_key",
      })
      assert.is_false(valid)
      assert.is_true(#errors > 0)
    end)

    it("can use vertex as active provider", function()
      config.setup({
        active_provider = "vertex",
        providers = {
          vertex = {
            model = "gemini-2.0-flash-lite",
            project = "my-project",
            location = "us-central1",
            api_key = "test_key",
          },
        },
      })

      local provider, err = providers.get_active_provider()

      assert.is_nil(err)
      assert.is_not_nil(provider)
      assert.equals("vertex", provider.name)
    end)

    it("vertex provider returns correct capabilities", function()
      local vertex = providers.get("vertex")
      local caps = vertex:get_capabilities()

      assert.is_table(caps)
      assert.is_false(caps.supports_multiple_generations)
      assert.equals(1, caps.max_generations)
    end)
  end)
end)

