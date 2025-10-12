-- Tests for Neogit integration
describe("neogit integration", function()
  local neogit_integration
  local config

  before_each(function()
    -- Clear module cache
    package.loaded["aicommits.integrations.neogit"] = nil
    package.loaded["aicommits.config"] = nil

    -- Reload modules
    config = require("aicommits.config")
    neogit_integration = require("aicommits.integrations.neogit")
  end)

  describe("config parsing", function()
    it("handles nested config object", function()
      config.setup({
        integrations = {
          neogit = {
            enabled = true,
            mappings = {
              enabled = true,
              key = "C",
            },
          },
        },
      })

      local neogit_config = config.get("integrations.neogit")
      assert.is_not_nil(neogit_config)
      assert.is_true(neogit_config.enabled)
      assert.is_true(neogit_config.mappings.enabled)
      assert.equals("C", neogit_config.mappings.key)
    end)

    it("merges with default neogit configuration", function()
      config.setup({})

      local neogit_config = config.get("integrations.neogit")
      assert.is_not_nil(neogit_config)
      assert.is_true(neogit_config.enabled)
      assert.is_true(neogit_config.mappings.enabled)
      assert.equals("C", neogit_config.mappings.key)
    end)

    it("allows disabling neogit integration", function()
      config.setup({
        integrations = {
          neogit = {
            enabled = false,
          },
        },
      })

      local neogit_config = config.get("integrations.neogit")
      assert.is_not_nil(neogit_config)
      assert.is_false(neogit_config.enabled)
    end)

    it("allows custom key binding", function()
      config.setup({
        integrations = {
          neogit = {
            enabled = true,
            mappings = {
              enabled = true,
              key = "K",
            },
          },
        },
      })

      local neogit_config = config.get("integrations.neogit")
      assert.equals("K", neogit_config.mappings.key)
    end)

    it("allows disabling mappings while keeping refresh enabled", function()
      config.setup({
        integrations = {
          neogit = {
            enabled = true,
            mappings = {
              enabled = false,
            },
          },
        },
      })

      local neogit_config = config.get("integrations.neogit")
      assert.is_true(neogit_config.enabled)
      assert.is_false(neogit_config.mappings.enabled)
    end)
  end)

  describe("is_available", function()
    it("returns false when neogit is not loaded", function()
      package.loaded["neogit"] = nil
      assert.is_false(neogit_integration.is_available())
    end)

    it("returns true when neogit is loaded", function()
      -- Mock neogit module
      package.loaded["neogit"] = { refresh = function() end }
      assert.is_true(neogit_integration.is_available())

      -- Cleanup
      package.loaded["neogit"] = nil
    end)
  end)

  describe("setup", function()
    it("does not error when neogit integration disabled", function()
      config.setup({
        integrations = {
          neogit = {
            enabled = false,
          },
        },
      })

      assert.has_no.errors(function()
        neogit_integration.setup()
      end)
    end)

    it("does not error when mappings disabled", function()
      config.setup({
        integrations = {
          neogit = {
            enabled = true,
            mappings = {
              enabled = false,
            },
          },
        },
      })

      assert.has_no.errors(function()
        neogit_integration.setup()
      end)
    end)

    it("creates autocmd when integration enabled", function()
      config.setup({
        integrations = {
          neogit = {
            enabled = true,
            mappings = {
              enabled = true,
              key = "C",
            },
          },
        },
      })

      -- Clear any existing autocommands
      vim.api.nvim_create_augroup("AicommitsNeogitIntegration", { clear = true })

      -- Setup should create autocmd
      neogit_integration.setup()

      -- Check autocmd exists
      local autocmds = vim.api.nvim_get_autocmds({
        group = "AicommitsNeogitIntegration",
      })

      assert.is_true(#autocmds > 0)
    end)
  end)
end)
