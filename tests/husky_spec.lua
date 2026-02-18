-- Tests for aicommits.husky module
describe("aicommits.husky", function()
  local husky
  local tmp_root

  local function mkdir(path)
    os.execute("mkdir -p " .. path)
  end

  local function write_file(path, content)
    local f = io.open(path, "w")
    f:write(content)
    f:close()
  end

  before_each(function()
    package.loaded["aicommits.husky"] = nil
    husky = require("aicommits.husky")

    -- Create a fresh temp directory for each test
    local tmp = os.tmpname()
    os.remove(tmp)
    mkdir(tmp)
    tmp_root = tmp
  end)

  after_each(function()
    os.execute("rm -rf " .. tmp_root)
  end)

  describe("get_commitlint_rules(root)", function()
    it("returns nil when .husky directory does not exist", function()
      local rules = husky.get_commitlint_rules(tmp_root)
      assert.is_nil(rules)
    end)

    it("returns nil when .husky exists but no commitlint config is present", function()
      mkdir(tmp_root .. "/.husky")
      local rules = husky.get_commitlint_rules(tmp_root)
      assert.is_nil(rules)
    end)

    it("returns content when commitlint.config.js exists", function()
      mkdir(tmp_root .. "/.husky")
      write_file(
        tmp_root .. "/commitlint.config.js",
        "module.exports = { extends: ['@commitlint/config-conventional'] }"
      )

      local rules = husky.get_commitlint_rules(tmp_root)
      assert.is_string(rules)
      assert.matches("config%-conventional", rules)
    end)

    it("returns content when .commitlintrc.json exists", function()
      mkdir(tmp_root .. "/.husky")
      write_file(tmp_root .. "/.commitlintrc.json", '{"extends": ["@commitlint/config-conventional"]}')

      local rules = husky.get_commitlint_rules(tmp_root)
      assert.is_string(rules)
      assert.matches("config%-conventional", rules)
    end)

    it("returns content when .commitlintrc exists", function()
      mkdir(tmp_root .. "/.husky")
      write_file(tmp_root .. "/.commitlintrc", '{"extends": ["@commitlint/config-conventional"]}')

      local rules = husky.get_commitlint_rules(tmp_root)
      assert.is_string(rules)
      assert.matches("config%-conventional", rules)
    end)

    it("returns content when .commitlintrc.yaml exists", function()
      mkdir(tmp_root .. "/.husky")
      write_file(tmp_root .. "/.commitlintrc.yaml", "extends:\n  - '@commitlint/config-conventional'")

      local rules = husky.get_commitlint_rules(tmp_root)
      assert.is_string(rules)
      assert.matches("config%-conventional", rules)
    end)

    it("returns content when .commitlintrc.yml exists", function()
      mkdir(tmp_root .. "/.husky")
      write_file(tmp_root .. "/.commitlintrc.yml", "extends:\n  - '@commitlint/config-conventional'")

      local rules = husky.get_commitlint_rules(tmp_root)
      assert.is_string(rules)
      assert.matches("config%-conventional", rules)
    end)

    it("prefers commitlint.config.js over .commitlintrc.json", function()
      mkdir(tmp_root .. "/.husky")
      write_file(tmp_root .. "/commitlint.config.js", "// from commitlint.config.js")
      write_file(tmp_root .. "/.commitlintrc.json", '{"from": ".commitlintrc.json"}')

      local rules = husky.get_commitlint_rules(tmp_root)
      assert.matches("from commitlint.config.js", rules)
    end)

    it("falls back to package.json commitlint key when no config file exists", function()
      mkdir(tmp_root .. "/.husky")
      write_file(
        tmp_root .. "/package.json",
        '{"name": "my-app", "commitlint": {"extends": ["@commitlint/config-conventional"]}}'
      )

      local rules = husky.get_commitlint_rules(tmp_root)
      assert.is_string(rules)
      assert.matches("config%-conventional", rules)
    end)

    it("returns nil when package.json exists but has no commitlint key", function()
      mkdir(tmp_root .. "/.husky")
      write_file(tmp_root .. "/package.json", '{"name": "my-app", "version": "1.0.0"}')

      local rules = husky.get_commitlint_rules(tmp_root)
      assert.is_nil(rules)
    end)
  end)
end)
