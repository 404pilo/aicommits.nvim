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
- curl
- **For OpenAI**: API key
- **For Vertex AI**: gcloud CLI + authentication (user credentials or service account)

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
      providers = {
        openai = {
          model = "gpt-4.1-nano",
          max_length = 72,
          generate = 3,
        },
      },
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

### OpenAI

Set your OpenAI API key:

```bash
export AICOMMITS_NVIM_OPENAI_API_KEY="sk-..."
```

Or use the standard OpenAI environment variable:

```bash
export OPENAI_API_KEY="sk-..."
```

### Google Vertex AI

**Prerequisites:**
- gcloud CLI installed: https://cloud.google.com/sdk/install
- GCP project with Vertex AI API enabled

**Authentication Setup:**

Choose one of the following methods:

1. **User credentials (recommended for development):**
   ```bash
   gcloud auth application-default login
   ```

2. **Service account (recommended for production):**
   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"
   ```

**Configure in your Neovim setup:**

```lua
require("aicommits").setup({
  active_provider = "vertex",
  providers = {
    vertex = {
      enabled = true,
      model = "gemini-2.0-flash-lite",
      project = "your-gcp-project-id",  -- Required: Your GCP project ID
      location = "us-central1",         -- GCP region
      max_length = 50,
      generate = 3,                     -- Generate 3 options to choose from
      temperature = 0.7,
    },
  },
})
```

**Note:** Authentication is handled automatically via gcloud. The plugin will call `gcloud auth application-default print-access-token` to obtain OAuth tokens as needed. Tokens are cached for 55 minutes to minimize gcloud calls.

### Google Gemini API (AI Studio)

**Simpler alternative to Vertex AI** - uses Google AI Studio API with straightforward API key authentication.

**Prerequisites:**
- Google Account
- Get free API key from: https://aistudio.google.com

**Key Differences from Vertex AI:**

| Feature | Gemini API | Vertex AI |
|---------|------------|-----------|
| Authentication | Simple API key | Google Cloud credentials |
| Setup Required | Just get API key | GCP project, gcloud CLI |
| Target Users | Individuals, prototyping | Enterprise, production |
| Free Tier | Generous free tier | GCP billing required |

**Authentication Setup:**

Set your Gemini API key:

```bash
export AICOMMITS_NVIM_GEMINI_API_KEY="your-api-key-here"
```

Or use the generic Gemini environment variable:

```bash
export GEMINI_API_KEY="your-api-key-here"
```

**Configure in your Neovim setup:**

```lua
require("aicommits").setup({
  active_provider = "gemini-api",
  providers = {
    ["gemini-api"] = {
      enabled = true,
      model = "gemini-2.5-flash",      -- Latest Gemini model
      max_length = 50,
      generate = 3,                     -- Generate 1-8 commit message options
      temperature = 0.7,
      max_tokens = 200,
    },
  },
})
```

**Available Models:**
- `gemini-2.5-flash` - Latest, recommended (GA)
- `gemini-2.0-flash-exp` - Experimental Gemini 2.0
- `gemini-1.5-flash` - Stable Gemini 1.5

**Note:** This provider uses the `generativelanguage.googleapis.com` API endpoint, which is completely separate from Vertex AI. No Google Cloud project or gcloud CLI required!

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
  -- Provider Configuration
  active_provider = "openai",  -- Which AI provider to use

  providers = {
    -- OpenAI Configuration
    openai = {
      enabled = true,          -- Enable/disable this provider
      api_key = nil,           -- API key (nil = use environment variables)
      endpoint = nil,          -- Custom endpoint (nil = use default)
      model = "gpt-4.1-nano",  -- Which model to use
      max_length = 50,         -- Max characters in commit message
      generate = 1,            -- Number of options (1-5)
      -- Advanced options
      temperature = 0.7,       -- Sampling temperature (0-2)
      top_p = 1,              -- Nucleus sampling parameter
      frequency_penalty = 0,   -- Frequency penalty (-2 to 2)
      presence_penalty = 0,    -- Presence penalty (-2 to 2)
      max_tokens = 200,        -- Maximum tokens in response
    },
    -- Google Vertex AI Configuration
    -- Requires gcloud CLI: https://cloud.google.com/sdk/install
    -- Authentication: gcloud auth application-default login
    -- Or set GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
    vertex = {
      enabled = false,         -- Enable/disable this provider
      model = "gemini-2.0-flash-lite",  -- Vertex AI model
      project = nil,           -- GCP project ID (required)
      location = "us-central1", -- GCP region
      max_length = 50,         -- Max characters in commit message
      generate = 3,            -- Number of options (generates 3 by default)
      temperature = 0.7,       -- Sampling temperature (0-2)
      max_tokens = 200,        -- Maximum tokens in response
    },
    -- Google Gemini API (AI Studio) Configuration
    -- Get API key from: https://aistudio.google.com
    -- Simpler alternative to Vertex AI - no GCP project required
    ["gemini-api"] = {
      enabled = false,         -- Enable/disable this provider
      api_key = nil,          -- API key (nil = use environment variables)
      model = "gemini-2.5-flash", -- Gemini model (gemini-2.5-flash, gemini-2.0-flash-exp, gemini-1.5-flash)
      max_length = 50,         -- Max characters in commit message
      generate = 1,            -- Number of options (1-8)
      temperature = 0.7,       -- Sampling temperature (0-2)
      max_tokens = 200,        -- Maximum tokens in response
    },
    -- Future providers can be added here
    -- anthropic = { ... },
    -- ollama = { ... },
  },

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

### Provider Configuration

The plugin uses a provider system to support multiple AI services. Each provider has its own configuration section under `providers`.

#### Supported Providers

- **OpenAI** - OpenAI GPT models (default)
- **Vertex AI** - Google Vertex AI Gemini models (enterprise, requires GCP)
- **Gemini API** - Google AI Studio API (simple API key, free tier available)

#### OpenAI Provider

**Configure OpenAI with custom settings:**
```lua
require("aicommits").setup({
  active_provider = "openai",
  providers = {
    openai = {
      model = "gpt-4.1-nano",      -- Use a different model
      max_length = 72,      -- Longer commit messages
      generate = 3,         -- Generate 3 options to choose from
    },
  },
})
```

**Use a custom OpenAI-compatible endpoint:**
```lua
require("aicommits").setup({
  providers = {
    openai = {
      endpoint = "https://your-proxy.com/v1/chat/completions",
      api_key = "your-api-key",  -- Or use environment variables
      model = "gpt-4.1-nano",
    },
  },
})
```

#### Vertex AI Provider

**Configure Vertex AI Gemini:**
```lua
require("aicommits").setup({
  active_provider = "vertex",
  providers = {
    vertex = {
      enabled = true,
      model = "gemini-2.0-flash-lite",
      project = "my-gcp-project",      -- Required: Your GCP project ID
      location = "us-central1",        -- GCP region
      max_length = 50,
      generate = 3,                    -- Generate 3 options to choose from
      temperature = 0.7,
      max_tokens = 200,
    },
  },
})
```

**Authentication:**

Vertex AI uses gcloud for authentication. You must have gcloud CLI installed and configured:

1. **Install gcloud CLI:**
   ```bash
   # macOS
   brew install google-cloud-sdk

   # Or download from: https://cloud.google.com/sdk/install
   ```

2. **Authenticate (choose one):**
   ```bash
   # Option 1: User credentials (development)
   gcloud auth application-default login

   # Option 2: Service account (production)
   export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"
   ```

The plugin will automatically call `gcloud auth application-default print-access-token` to obtain OAuth tokens. Tokens are cached for 55 minutes to minimize gcloud calls.

### UI Configuration

**Use vim.ui.select instead of custom picker:**
```lua
require("aicommits").setup({
  ui = {
    use_custom_picker = false,
  },
})
```

### Integration Configuration

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
