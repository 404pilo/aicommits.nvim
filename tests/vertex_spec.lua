-- Unit tests for Vertex AI provider
describe("vertex provider", function()
  local vertex
  local base

  before_each(function()
    package.loaded["aicommits.providers.vertex"] = nil
    package.loaded["aicommits.providers.base"] = nil

    base = require("aicommits.providers.base")
    vertex = require("aicommits.providers.vertex")
  end)

  describe("initialization", function()
    it("has correct name", function()
      assert.equals("vertex", vertex.name)
    end)

    it("implements required methods", function()
      assert.is_function(vertex.generate_commit_message)
      assert.is_function(vertex.validate_config)
      assert.is_function(vertex.get_auth_headers)
      assert.is_function(vertex.get_capabilities)
    end)
  end)

  describe("validate_config", function()
    it("accepts valid configuration", function()
      local valid, errors = vertex:validate_config({
        model = "gemini-2.0-flash-lite",
        project = "my-gcp-project",
        location = "us-central1",
        api_key = "test_key",
      })

      assert.is_true(valid)
      assert.equals(0, #errors)
    end)

    it("rejects configuration with missing model", function()
      local valid, errors = vertex:validate_config({
        project = "my-gcp-project",
        location = "us-central1",
        api_key = "test_key",
      })

      assert.is_false(valid)
      assert.is_true(#errors > 0)
      assert.matches("model", errors[1])
    end)

    it("rejects configuration with empty model", function()
      local valid, errors = vertex:validate_config({
        model = "",
        project = "my-gcp-project",
        location = "us-central1",
        api_key = "test_key",
      })

      assert.is_false(valid)
      assert.is_true(#errors > 0)
      assert.matches("model", errors[1])
    end)

    it("rejects configuration with missing project", function()
      local valid, errors = vertex:validate_config({
        model = "gemini-2.0-flash-lite",
        location = "us-central1",
        api_key = "test_key",
      })

      assert.is_false(valid)
      assert.is_true(#errors > 0)
      -- Check that at least one error mentions project
      local has_project_error = false
      for _, err in ipairs(errors) do
        if err:match("project") then
          has_project_error = true
          break
        end
      end
      assert.is_true(has_project_error)
    end)

    it("rejects configuration with empty project", function()
      local valid, errors = vertex:validate_config({
        model = "gemini-2.0-flash-lite",
        project = "",
        location = "us-central1",
        api_key = "test_key",
      })

      assert.is_false(valid)
      assert.is_true(#errors > 0)
    end)

    it("rejects configuration with missing location", function()
      local valid, errors = vertex:validate_config({
        model = "gemini-2.0-flash-lite",
        project = "my-gcp-project",
        api_key = "test_key",
      })

      assert.is_false(valid)
      assert.is_true(#errors > 0)
      -- Check that at least one error mentions location
      local has_location_error = false
      for _, err in ipairs(errors) do
        if err:match("location") then
          has_location_error = true
          break
        end
      end
      assert.is_true(has_location_error)
    end)

    it("rejects configuration with empty location", function()
      local valid, errors = vertex:validate_config({
        model = "gemini-2.0-flash-lite",
        project = "my-gcp-project",
        location = "",
        api_key = "test_key",
      })

      assert.is_false(valid)
      assert.is_true(#errors > 0)
    end)

    it("rejects configuration with invalid max_length", function()
      local valid, errors = vertex:validate_config({
        model = "gemini-2.0-flash-lite",
        project = "my-gcp-project",
        location = "us-central1",
        api_key = "test_key",
        max_length = -1,
      })

      assert.is_false(valid)
      assert.is_true(#errors > 0)
      assert.matches("max_length", errors[1])
    end)

    it("allows missing api_key (can come from environment)", function()
      local valid, errors = vertex:validate_config({
        model = "gemini-2.0-flash-lite",
        project = "my-gcp-project",
        location = "us-central1",
      })

      -- Should be invalid because API key is required and not in env
      assert.is_false(valid)
      assert.is_true(#errors > 0)
    end)

    it("validates with environment variable VERTEX_API_KEY", function()
      -- Set environment variable
      vim.env.VERTEX_API_KEY = "test_vertex_key"

      local valid, errors = vertex:validate_config({
        model = "gemini-2.0-flash-lite",
        project = "my-gcp-project",
        location = "us-central1",
      })

      -- Clean up
      vim.env.VERTEX_API_KEY = nil

      assert.is_true(valid)
      assert.equals(0, #errors)
    end)

    it("validates with environment variable AICOMMITS_NVIM_VERTEX_API_KEY", function()
      -- Set environment variable
      vim.env.AICOMMITS_NVIM_VERTEX_API_KEY = "test_vertex_key"

      local valid, errors = vertex:validate_config({
        model = "gemini-2.0-flash-lite",
        project = "my-gcp-project",
        location = "us-central1",
      })

      -- Clean up
      vim.env.AICOMMITS_NVIM_VERTEX_API_KEY = nil

      assert.is_true(valid)
      assert.equals(0, #errors)
    end)
  end)

  describe("get_auth_headers", function()
    it("returns headers with Bearer token", function()
      local headers = vertex:get_auth_headers({
        api_key = "test_key_123",
      })

      assert.is_table(headers)
      assert.equals("Bearer test_key_123", headers.Authorization)
      assert.equals("application/json", headers["Content-Type"])
    end)

    it("uses config api_key when provided", function()
      local headers = vertex:get_auth_headers({
        api_key = "config_key",
      })

      assert.equals("Bearer config_key", headers.Authorization)
    end)

    it("uses environment variable when config api_key is nil", function()
      vim.env.VERTEX_API_KEY = "env_key"

      local headers = vertex:get_auth_headers({})

      vim.env.VERTEX_API_KEY = nil

      assert.equals("Bearer env_key", headers.Authorization)
    end)

    it("prioritizes config over environment", function()
      vim.env.VERTEX_API_KEY = "env_key"

      local headers = vertex:get_auth_headers({
        api_key = "config_key",
      })

      vim.env.VERTEX_API_KEY = nil

      assert.equals("Bearer config_key", headers.Authorization)
    end)
  end)

  describe("get_capabilities", function()
    it("returns capabilities object", function()
      local capabilities = vertex:get_capabilities()

      assert.is_table(capabilities)
      assert.is_boolean(capabilities.supports_streaming)
      assert.is_boolean(capabilities.supports_multiple_generations)
      assert.is_number(capabilities.max_generations)
    end)

    it("has expected vertex capabilities", function()
      local capabilities = vertex:get_capabilities()

      -- Vertex AI Gemini typically generates one response
      assert.is_false(capabilities.supports_multiple_generations)
      assert.equals(1, capabilities.max_generations)
      assert.is_false(capabilities.supports_streaming)
    end)
  end)

  describe("generate_commit_message", function()
    it("requires api_key", function()
      local called = false
      local error_msg = nil

      vertex:generate_commit_message("test diff", {
        model = "gemini-2.0-flash-lite",
        project = "my-project",
        location = "us-central1",
      }, function(err, messages)
        called = true
        error_msg = err
      end)

      assert.is_true(called)
      assert.is_not_nil(error_msg)
      assert.matches("API key not found", error_msg)
    end)

    it("calls callback with error on missing api_key", function()
      local callback_called = false
      local received_error = nil
      local received_messages = nil

      vertex:generate_commit_message("test diff", {
        model = "gemini-2.0-flash-lite",
        project = "my-project",
        location = "us-central1",
        -- api_key intentionally missing
      }, function(err, messages)
        callback_called = true
        received_error = err
        received_messages = messages
      end)

      assert.is_true(callback_called)
      assert.is_not_nil(received_error)
      assert.is_nil(received_messages)
    end)
  end)
end)
