---@meta

---@class AiProviderPreferences
---@field default_provider? string Default provider used by chat calls without an explicit provider.
---@field [string] table Provider-specific preferences. Provider tables currently support `model`.

---@class AiProviderProviderConfig
---@field default_model string Default model used when no persisted model exists for this provider.
---@field timeout? integer Optional provider timeout in milliseconds.
---@field context_size? integer Optional provider-wide default context size.
---@field keep_alive? string|integer Optional provider-wide keep-alive/unload timeout. Ollama accepts values like `4h`, `10m`, or `0`.
---@field load_timeout? integer Optional model preload timeout in milliseconds. Used by Ollama before the normal chat timeout starts.
---@field think? boolean Optional Ollama thinking mode override for reasoning models.
---@field models? table<string, string|AiProviderModelConfig> Optional logical model profiles. Keys are selectable model names.

---@class AiProviderHelperConfig
---@field provider string Provider name used by the helper.
---@field model string Model/profile name returned by the helper. This is a reference to the configured model name, not copied options.
---@field label? string Display label, usually `provider/model`.

---@class AiProviderSelectHelperOptions
---@field prompt? string Picker prompt.
---@field current? AiProviderHelperConfig Current selection used for picker highlighting.

---@class AiProviderModelConfig
---@field model string Underlying provider model name.
---@field context_size? integer Optional model-specific context size override.
---@field think? boolean Optional Ollama thinking mode override for this logical model profile.

---@class AiProviderConfig
---@field default_provider string Default provider used when no persisted default provider exists.
---@field providers table<string, AiProviderProviderConfig> Required provider defaults.

---@class AiProviderChatMeta
---@field requested_model string Model requested by the caller.
---@field used_model string Model reported by the provider response.
---@field elapsed_ms number Request duration in milliseconds.
---@field done_reason? string Provider stop reason, if reported.
---@field error? string Provider/runtime error when `message` is nil.
---@field total_duration? integer Provider total duration in nanoseconds, when reported.
---@field load_duration? integer Initial model load duration in nanoseconds, when reported.
---@field prompt_eval_count? integer Prompt tokens evaluated, when reported.
---@field prompt_eval_duration? integer Prompt evaluation duration in nanoseconds, when reported.
---@field eval_count? integer Generated tokens evaluated, when reported.
---@field eval_duration? integer Generation duration in nanoseconds, when reported.

---@class AiProviderStatus
---@field provider string Provider name.
---@field phase string Standard phase, for example `loading`, `loaded`, `thinking`, `generating`, `done`, or `error`.
---@field message string Human-readable status message.
---@field model? string Model/profile name.
---@field used_model? string Raw provider model name.
---@field tokens? integer Token count when the provider reports one.
---@field tokens_per_second? number Generation throughput when the provider reports enough timing data.
---@field elapsed_ms? number Elapsed duration in milliseconds.

---@class AiProviderChatRequest
---@field provider? string Provider name. Defaults to `get_default_provider()`.
---@field model? string Model name. Defaults to the selected model for the provider.
---@field prompt string User prompt to send to the provider.
---@field stream? boolean Whether the provider should stream chunks. Defaults to true when supported.
---@field max_tokens? integer Maximum generated tokens/provider equivalent.
---@field context_size? integer Per-request context size override.
---@field keep_alive? string|integer Per-request keep-alive/unload timeout override.
---@field load_timeout? integer Per-request model preload timeout in milliseconds.
---@field preload? boolean Whether to preload the model before chat. Defaults to false; callers such as ai-commit can enable it to exclude load time from chat timeout.
---@field think? boolean Per-request Ollama thinking mode override.
---@field on_chunk? fun(chunk: string, raw: table) Called for each streamed text chunk.
---@field on_status? fun(status: AiProviderStatus) Called with standardized provider progress updates.
---@field callback? fun(message: string|nil, meta: AiProviderChatMeta|nil) Called once the request finishes.
---@field is_cancelled? fun(): boolean Optional cancellation predicate.
---@field register_http_job? fun(job: table) Receives the provider job/process for external cancellation.

---@class AiProvider
local M = {}

local core = require 'ai-provider.core'

---@return AiProviderPreferences prefs Saved provider preferences.
function M.load_preferences()
  return core.load_preferences()
end

---@param prefs AiProviderPreferences
---@return boolean saved Whether preferences were written.
function M.save_preferences(prefs)
  return core.save_preferences(prefs)
end

---@param name string Provider name, for example `ollama`.
---@return table|nil provider Active provider implementation table. Returns nil for known but unconfigured providers.
function M.get_provider(name)
  return core.get_provider(name)
end

---@param name string Provider name, for example `ollama`.
---@return table|nil provider Provider implementation table, even when not enabled by config.
function M.get_provider_implementation(name)
  return core.get_provider_implementation(name)
end

---@param name string Provider name, for example `ollama`.
---@return AiProviderProviderConfig|nil config Active provider config.
function M.get_provider_config(name)
  return core.get_provider_config(name)
end

---@return string[] providers Configured provider names.
function M.list_providers()
  return core.list_providers()
end

---@return string|nil provider Default provider name, or nil before valid setup.
function M.get_default_provider()
  return core.get_default_provider()
end

---@return string|nil provider Current/default provider name, or nil before valid setup.
function M.get_current_provider()
  return core.get_default_provider()
end

---@param provider string Provider name.
---@return boolean saved Whether the provider was saved as default.
function M.set_default_provider(provider)
  return core.set_default_provider(provider)
end

---@param provider string Provider name.
---@return boolean saved Whether the provider was saved as default.
function M.set_provider(provider)
  return core.set_default_provider(provider)
end

---@param provider string Provider name.
---@return string|nil model Selected model for the provider.
function M.get_selected_model(provider)
  return core.get_selected_model(provider)
end

---@param provider string Provider name.
---@return string|nil model Selected model for the provider.
function M.get_model(provider)
  return core.get_selected_model(provider)
end

---@param provider string Provider name.
---@param model string Model name.
---@return boolean saved Whether the model preference was saved.
function M.set_selected_model(provider, model)
  return core.set_selected_model(provider, model)
end

---@param provider string Provider name.
---@param model string Model name.
---@return boolean saved Whether the model preference was saved.
function M.set_model(provider, model)
  return core.set_selected_model(provider, model)
end

---@param provider string Provider name.
---@param callback fun(working: boolean)
---@param opts? table Provider-specific check options.
function M.check(provider, callback, opts)
  return core.check(provider, callback, opts)
end

---@param provider string Provider name.
---@param callback fun(authenticated: boolean)
---@param opts? table Provider-specific auth options.
function M.auth(provider, callback, opts)
  return core.auth(provider, callback, opts)
end

---@param provider string Provider name.
---@param callback fun(models: string[]|nil)
---@param opts? table Provider-specific list options.
function M.list_models(provider, callback, opts)
  return core.list_models(provider, callback, opts)
end

---Chat with the default provider, or with an explicit provider when called as
---`chat('ollama', request)`. Responses are delivered via `request.callback`.
---@param request_or_provider AiProviderChatRequest|string Prompt string, request table, or explicit provider name.
---@param callback_or_request? fun(message: string|nil, meta: AiProviderChatMeta|nil)|AiProviderChatRequest Callback for prompt strings, or request table for explicit providers.
---@return table|nil job Provider job/process handle.
function M.chat(request_or_provider, callback_or_request)
  return core.chat(request_or_provider, callback_or_request)
end

---@param provider string Provider name.
---@param request AiProviderChatRequest Chat request.
---@return table|nil job Provider job/process handle.
function M.chat_with(provider, request)
  return core.chat_with(provider, request)
end

---@param provider? string Provider name. Omit to pick across all providers.
function M.select_model(provider)
  return core.select_model(provider)
end

---Open a model picker for feature-specific callers. This does not persist state;
---callers should save the returned provider/model reference themselves.
---@param opts? AiProviderSelectHelperOptions|fun(selection: AiProviderHelperConfig|nil)
---@param callback? fun(selection: AiProviderHelperConfig|nil) Called with the selected provider/model reference.
function M.select_helper(opts, callback)
  return core.select_helper(opts, callback)
end

---@param arglead string Current command-line argument prefix.
---@param cmdline string Full command-line.
---@return string[] completions Matching command completions.
function M.command_complete(arglead, cmdline)
  return core.command_complete(arglead, cmdline)
end

---@param args string[] Parsed `:AIProvider` arguments.
function M.run_command(args)
  return core.run_command(args)
end

---Register user commands for the provider layer. `default_provider` and each
---registered provider's `default_model` are required config values; the plugin
---does not ship provider/model defaults.
---
---Command semantics:
---- `:AIProvider` opens the all-provider model picker.
---- `:AIProvider model` opens the all-provider model picker.
---- `:AIProvider model provider/model` sets the default provider and that provider's default model.
---- `:AIProvider default [provider]` shows or sets the default provider.
---- `:AIProvider <provider> model [model]` picks or sets only that provider's default model.
---@param opts AiProviderConfig
function M.setup(opts)
  return core.setup(opts)
end

return M
