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
    -- Mock gcloud being available
    local original_executable
    before_each(function()
      original_executable = vim.fn.executable
      vim.fn.executable = function(cmd)
        if cmd == "gcloud" then
          return 1
        end
        return original_executable(cmd)
      end
    end)

    after_each(function()
      vim.fn.executable = original_executable
    end)

    it("accepts valid configuration when gcloud is available", function()
      local valid, errors = vertex:validate_config({
        model = "gemini-2.0-flash-lite",
        project = "my-gcp-project",
        location = "us-central1",
      })

      assert.is_true(valid)
      assert.equals(0, #errors)
    end)

    it("rejects configuration with missing model", function()
      local valid, errors = vertex:validate_config({
        project = "my-gcp-project",
        location = "us-central1",
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
      })

      assert.is_false(valid)
      assert.is_true(#errors > 0)
      assert.matches("model", errors[1])
    end)

    it("rejects configuration with missing project", function()
      local valid, errors = vertex:validate_config({
        model = "gemini-2.0-flash-lite",
        location = "us-central1",
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
      })

      assert.is_false(valid)
      assert.is_true(#errors > 0)
    end)

    it("rejects configuration with missing location", function()
      local valid, errors = vertex:validate_config({
        model = "gemini-2.0-flash-lite",
        project = "my-gcp-project",
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
      })

      assert.is_false(valid)
      assert.is_true(#errors > 0)
    end)

    it("rejects configuration with invalid max_length", function()
      local valid, errors = vertex:validate_config({
        model = "gemini-2.0-flash-lite",
        project = "my-gcp-project",
        location = "us-central1",
        max_length = -1,
      })

      assert.is_false(valid)
      assert.is_true(#errors > 0)
      assert.matches("max_length", errors[1])
    end)

    it("rejects configuration when gcloud CLI is not installed", function()
      -- Mock gcloud not being available
      vim.fn.executable = function(cmd)
        if cmd == "gcloud" then
          return 0
        end
        return original_executable(cmd)
      end

      local valid, errors = vertex:validate_config({
        model = "gemini-2.0-flash-lite",
        project = "my-gcp-project",
        location = "us-central1",
      })

      assert.is_false(valid)
      assert.is_true(#errors > 0)
      -- Check that error mentions gcloud
      local has_gcloud_error = false
      for _, err in ipairs(errors) do
        if err:match("gcloud") then
          has_gcloud_error = true
          break
        end
      end
      assert.is_true(has_gcloud_error)
    end)
  end)

  describe("get_auth_headers", function()
    it("returns headers with placeholder authorization", function()
      local headers = vertex:get_auth_headers({})

      assert.is_table(headers)
      assert.is_string(headers.Authorization)
      assert.equals("application/json", headers["Content-Type"])
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

      -- Vertex AI Gemini generates 3 commit message options
      assert.is_true(capabilities.supports_multiple_generations)
      assert.equals(3, capabilities.max_generations)
      assert.is_false(capabilities.supports_streaming)
    end)
  end)

  describe("generate_commit_message", function()
    local original_jobstart
    local original_executable

    before_each(function()
      original_jobstart = vim.fn.jobstart
      original_executable = vim.fn.executable

      -- Mock gcloud being available
      vim.fn.executable = function(cmd)
        if cmd == "gcloud" then
          return 1
        end
        return original_executable(cmd)
      end
    end)

    after_each(function()
      vim.fn.jobstart = original_jobstart
      vim.fn.executable = original_executable
    end)

    it("requires gcloud CLI to be installed", function()
      -- Mock gcloud not being available
      vim.fn.executable = function(cmd)
        if cmd == "gcloud" then
          return 0
        end
        return original_executable(cmd)
      end

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
      assert.matches("gcloud", error_msg)
    end)

    it("calls gcloud auth application-default print-access-token", function()
      local gcloud_called = false
      local gcloud_command = nil

      vim.fn.jobstart = function(cmd, opts)
        gcloud_called = true
        gcloud_command = cmd
        -- Simulate successful token generation
        if opts.on_stdout then
          opts.on_stdout(nil, { "test_token_12345" })
        end
        if opts.on_exit then
          opts.on_exit(nil, 0)
        end
        return 1
      end

      -- Mock http.post to prevent actual API call
      package.loaded["aicommits.http"] = {
        post = function(endpoint, headers, body, callback)
          callback(
            nil,
            vim.json.encode({
              candidates = {
                {
                  content = {
                    parts = {
                      { text = "test: commit message" },
                    },
                  },
                },
              },
            })
          )
        end,
      }

      vertex:generate_commit_message("test diff", {
        model = "gemini-2.0-flash-lite",
        project = "my-project",
        location = "us-central1",
      }, function(err, messages) end)

      assert.is_true(gcloud_called)
      assert.equals("gcloud auth application-default print-access-token", gcloud_command)
    end)

    it("caches token to avoid repeated gcloud calls", function()
      local gcloud_call_count = 0

      vim.fn.jobstart = function(cmd, opts)
        gcloud_call_count = gcloud_call_count + 1
        if opts.on_stdout then
          opts.on_stdout(nil, { "cached_token_12345" })
        end
        if opts.on_exit then
          opts.on_exit(nil, 0)
        end
        return 1
      end

      -- Mock http.post
      package.loaded["aicommits.http"] = {
        post = function(endpoint, headers, body, callback)
          callback(
            nil,
            vim.json.encode({
              candidates = {
                {
                  content = {
                    parts = {
                      { text = "test: commit message" },
                    },
                  },
                },
              },
            })
          )
        end,
      }

      -- First call
      vertex:generate_commit_message("test diff 1", {
        model = "gemini-2.0-flash-lite",
        project = "my-project",
        location = "us-central1",
      }, function(err, messages) end)

      -- Second call should use cached token
      vertex:generate_commit_message("test diff 2", {
        model = "gemini-2.0-flash-lite",
        project = "my-project",
        location = "us-central1",
      }, function(err, messages) end)

      -- Should only call gcloud once due to caching
      assert.equals(1, gcloud_call_count)
    end)
  end)
end)
