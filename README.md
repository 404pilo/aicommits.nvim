# aicommits.nvim

AI-powered git commit messages directly in Neovim.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

<div align="center">
  <img src="assets/demo.gif" alt="aicommits.nvim demo" width="800">
</div>

## What is this?

This plugin generates conventional commit messages using AI. Stage your changes, run `:AICommit`, and get a properly formatted commit message. It's that simple.

## Requirements

- Neovim 0.9+
- Git
- OpenAI API key
- curl

## Installation

### lazy.nvim

Minimal setup:
```lua
{
  "pilo404/aicommits.nvim",
  config = true,
}
```

With custom config:
```lua
{
  "pilo404/aicommits.nvim",
  config = function()
    require("aicommits").setup({
      model = "gpt-4.1-nano",
      max_length = 50,
      generate = 1,
    })
  end,
}
```

### Other plugin managers

**packer.nvim:**
```lua
use {
  "pilo404/aicommits.nvim",
  config = function()
    require("aicommits").setup()
  end
}
```

**vim-plug:**
```vim
Plug 'pilo404/aicommits.nvim'

lua << EOF
require("aicommits").setup()
EOF
```

## Setup

Set your OpenAI API key:

```bash
export AICOMMITS_NVIM_OPENAI_API_KEY="sk-..."
```

Or use the standard OpenAI environment variable:

```bash
export OPENAI_API_KEY="sk-..."
```

Add to your shell config (`~/.bashrc`, `~/.zshrc`, etc.) and restart your shell.

## Usage

```bash
# Stage changes
git add .
```

In Neovim:
```vim
:AICommit
```

The plugin will:
1. Analyze your changes
2. Generate commit message(s)
3. Show a picker
4. Create the commit

### Neogit Integration

If you use Neogit, press `C` in the status buffer to trigger AI commits.

## Configuration

All options with defaults:

```lua
require("aicommits").setup({
  -- OpenAI settings
  model = "gpt-4.1-nano",       -- Which model to use
  max_length = 50,              -- Max characters in commit message
  generate = 1,                  -- Number of options (1-5)

  -- UI settings
  ui = {
    use_custom_picker = true,  -- Custom picker vs vim.ui.select
    picker = {
      width = 0.4,             -- Percentage of screen width
      height = 0.3,            -- Percentage of screen height
      border = "rounded",      -- Border style
    },
  },

  -- Integrations
  integrations = {
    neogit = {
      enabled = true,          -- Auto-refresh after commit
      mappings = {
        enabled = true,        -- Add keymap in status buffer
        key = "C",            -- Which key to use
      },
    },
  },

  -- Debugging
  debug = false,
})
```

### Examples

**Generate multiple options:**
```lua
require("aicommits").setup({
  generate = 3,  -- Pick from 3 messages
})
```

**Use a different model:**
```lua
require("aicommits").setup({
  model = "gpt-4",
  max_length = 72,
})
```

**Use vim.ui.select instead:**
```lua
require("aicommits").setup({
  ui = {
    use_custom_picker = false,
  },
})
```

**Disable Neogit integration:**
```lua
require("aicommits").setup({
  integrations = {
    neogit = { enabled = false },
  },
})
```

## Commands

| Command | What it does |
|---------|-------------|
| `:AICommit` | Generate and create commit |
| `:AICommitHealth` | Check if everything is set up |
| `:AICommitDebug` | Show debug info |

## Commit Format

All commits follow Conventional Commits:

```
<type>(<scope>): <description>
```

Types:
- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation
- `style` - Formatting
- `refactor` - Code restructuring
- `perf` - Performance
- `test` - Tests
- `build` - Build system
- `ci` - CI changes
- `chore` - Other

Examples:
```
feat(auth): add OAuth2 support
fix(api): handle null responses
docs: update installation steps
```

## Troubleshooting

**"OpenAI API key not found"**

Set the environment variable and restart Neovim.

**"No staged changes found"**

Run `git add` first.

**"Not in a git repository"**

Navigate to a git repo or run `git init`.

**Check setup**

Run `:AICommitHealth` to verify everything is configured correctly.

## Development

Use `app.sh` to run the same checks that CI runs:

```bash
./app.sh setup    # First-time setup
./app.sh test     # Run tests (same as CI)
./app.sh lint     # Check formatting (same as CI)
./app.sh ci       # Run all CI checks locally
./app.sh status   # Check environment
```

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - see [LICENSE](LICENSE).

## Credits

Inspired by [aicommits](https://github.com/Nutlope/aicommits) by [@Nutlope](https://github.com/Nutlope).
