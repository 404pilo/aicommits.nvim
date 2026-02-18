-- Tests for prompt engineering and message processing
describe("prompts module", function()
  local prompts

  before_each(function()
    -- Clear package cache and load fresh module
    package.loaded["aicommits.prompts"] = nil
    prompts = require("aicommits.prompts")
  end)

  describe("build_system_prompt", function()
    it("generates a system prompt with default max length", function()
      local prompt = prompts.build_system_prompt(50)

      assert.is_string(prompt)
      assert.is_true(#prompt > 0)
    end)

    it("includes conventional commit types in the prompt", function()
      local prompt = prompts.build_system_prompt(50)

      -- Check for key commit types
      assert.matches("feat", prompt)
      assert.matches("fix", prompt)
      assert.matches("docs", prompt)
      assert.matches("refactor", prompt)
      assert.matches("test", prompt)
      assert.matches("chore", prompt)
    end)

    it("includes the specified max length in prompt", function()
      local prompt = prompts.build_system_prompt(72)

      assert.matches("72 characters", prompt)
    end)

    it("specifies the expected output format", function()
      local prompt = prompts.build_system_prompt(50)

      assert.matches("<type>", prompt)
      assert.matches("<commit message>", prompt)
    end)

    it("works with different max length values", function()
      local prompt_50 = prompts.build_system_prompt(50)
      local prompt_100 = prompts.build_system_prompt(100)

      assert.matches("50 characters", prompt_50)
      assert.matches("100 characters", prompt_100)
      assert.is_not.equals(prompt_50, prompt_100)
    end)

    it("includes commitlint config section when commitlint_config is provided", function()
      local config_content = '{"extends": ["@commitlint/config-conventional"]}'
      local prompt = prompts.build_system_prompt(50, config_content)

      assert.matches("commitlint", prompt)
      assert.matches("config%-conventional", prompt)
    end)

    it("does not include commitlint section when commitlint_config is nil", function()
      local prompt = prompts.build_system_prompt(50, nil)

      assert.is_false(prompt:find("commitlint configuration") ~= nil)
    end)

    it("prompt with commitlint config is longer than without", function()
      local prompt_without = prompts.build_system_prompt(50)
      local prompt_with = prompts.build_system_prompt(50, "extends: conventional-commits")

      assert.is_true(#prompt_with > #prompt_without)
    end)
  end)

  describe("process_messages", function()
    it("returns messages as-is when they are clean", function()
      local messages = { "feat: add new feature", "fix: resolve bug" }
      local processed = prompts.process_messages(messages)

      assert.equals(2, #processed)
      assert.equals("feat: add new feature", processed[1])
      assert.equals("fix: resolve bug", processed[2])
    end)

    it("trims leading whitespace from messages", function()
      local messages = { "  feat: add feature", "\tfeat: add feature" }
      local processed = prompts.process_messages(messages)

      assert.equals(1, #processed) -- Should deduplicate
      assert.equals("feat: add feature", processed[1])
    end)

    it("trims trailing whitespace from messages", function()
      local messages = { "feat: add feature  ", "feat: add feature\t" }
      local processed = prompts.process_messages(messages)

      assert.equals(1, #processed) -- Should deduplicate
      assert.equals("feat: add feature", processed[1])
    end)

    it("removes newlines from messages", function()
      local messages = { "feat: add\nfeature", "fix: resolve\r\nbug" }
      local processed = prompts.process_messages(messages)

      assert.equals(2, #processed)
      assert.equals("feat: addfeature", processed[1])
      assert.equals("fix: resolvebug", processed[2])
    end)

    it("removes trailing periods after word characters", function()
      local messages = { "feat: add feature.", "fix: resolve bug." }
      local processed = prompts.process_messages(messages)

      assert.equals(2, #processed)
      assert.equals("feat: add feature", processed[1])
      assert.equals("fix: resolve bug", processed[2])
    end)

    it("preserves periods in other positions", function()
      local messages = { "feat: v1.0 release", "fix: resolve bug in v2.0.1" }
      local processed = prompts.process_messages(messages)

      assert.equals(2, #processed)
      assert.equals("feat: v1.0 release", processed[1])
      assert.equals("fix: resolve bug in v2.0.1", processed[2])
    end)

    it("deduplicates identical messages", function()
      local messages = { "feat: add feature", "feat: add feature", "feat: add feature" }
      local processed = prompts.process_messages(messages)

      assert.equals(1, #processed)
      assert.equals("feat: add feature", processed[1])
    end)

    it("deduplicates messages after sanitization", function()
      local messages = { "feat: add feature", "  feat: add feature  ", "feat: add feature." }
      local processed = prompts.process_messages(messages)

      assert.equals(1, #processed)
      assert.equals("feat: add feature", processed[1])
    end)

    it("filters out empty messages", function()
      local messages = { "feat: add feature", "", "   ", "fix: resolve bug" }
      local processed = prompts.process_messages(messages)

      assert.equals(2, #processed)
      assert.equals("feat: add feature", processed[1])
      assert.equals("fix: resolve bug", processed[2])
    end)

    it("handles empty input array", function()
      local messages = {}
      local processed = prompts.process_messages(messages)

      assert.equals(0, #processed)
    end)

    it("handles all empty/whitespace messages", function()
      local messages = { "", "   ", "\t", "\n" }
      local processed = prompts.process_messages(messages)

      assert.equals(0, #processed)
    end)

    it("preserves order of unique messages", function()
      local messages = { "feat: feature 1", "fix: bug 1", "feat: feature 2", "refactor: code" }
      local processed = prompts.process_messages(messages)

      assert.equals(4, #processed)
      assert.equals("feat: feature 1", processed[1])
      assert.equals("fix: bug 1", processed[2])
      assert.equals("feat: feature 2", processed[3])
      assert.equals("refactor: code", processed[4])
    end)

    it("handles complex sanitization scenario", function()
      local messages = {
        "  feat: add feature.\n",
        "feat: add feature",
        "\tfeat: add feature.  ",
        "fix: resolve bug",
        "",
        "fix: resolve bug.",
      }
      local processed = prompts.process_messages(messages)

      -- Should deduplicate to 2 unique messages
      assert.equals(2, #processed)
      assert.equals("feat: add feature", processed[1])
      assert.equals("fix: resolve bug", processed[2])
    end)
  end)
end)
