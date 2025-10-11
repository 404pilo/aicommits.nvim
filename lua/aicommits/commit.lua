-- Main commit workflow orchestration for aicommits.nvim
local M = {}

local git = require("aicommits.git")
local provider_manager = require("aicommits.providers")
local ui = require("aicommits.ui")
local picker = require("aicommits.ui.picker")
local utils = require("aicommits.utils")

-- Generate AI commit message and create commit
function M.generate_and_commit()
  -- Step 1: Validate git repository
  if not git.is_git_repo() then
    utils.notify_error("Not in a git repository")
    return
  end

  -- Step 2: Get active provider
  local provider, provider_err = provider_manager.get_active_provider()
  if not provider then
    utils.notify_error(provider_err or "Failed to get active provider")
    return
  end

  -- Step 3: Get staged diff
  picker.show_status("Detecting staged files...")

  git.get_staged_diff(function(err, diff_data)
    if err then
      picker.close_status()
      utils.notify_error(err)
      return
    end

    if not diff_data then
      picker.close_status()
      utils.notify_error("No staged changes found. Stage your changes with 'git add' first.")
      return
    end

    -- Show detected files
    local file_count = #diff_data.files
    local file_word = file_count == 1 and "file" or "files"
    picker.show_status(string.format("Detected %d staged %s", file_count, file_word))

    -- Step 4: Generate commit message via provider
    vim.defer_fn(function()
      picker.show_status("The AI is analyzing your changes...")
    end, 500)

    local config = require("aicommits.config")
    local provider_config = config.get("providers." .. provider.name)

    provider:generate_commit_message(diff_data.diff, provider_config, function(err, messages)
      if err then
        picker.close_status()
        utils.notify_error(err)
        return
      end

      if not messages or #messages == 0 then
        picker.close_status()
        utils.notify_error("No commit messages were generated. Try again.")
        return
      end

      -- Step 5: Show user selection UI (status window auto-closes)
      ui.show_commit_prompt(
        messages,
        -- On confirm: create commit
        function(selected_message)
          picker.show_status("Creating commit...")

          git.create_commit(selected_message, function(err)
            if err then
              picker.close_status()
              utils.notify_error(err)
              return
            end

            -- Step 6: Success - refresh git clients
            picker.show_status("Successfully committed!")
            git.refresh_git_clients()

            -- Close status after brief display
            vim.defer_fn(function()
              picker.close_status()
            end, 1500)
          end)
        end,
        -- On cancel: abort (picker closes itself)
        function()
          -- Status already closed by picker, no action needed
        end
      )
    end)
  end)
end

return M
