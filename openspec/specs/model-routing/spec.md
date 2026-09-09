## Purpose

Defines how the deployment translates its environment variables (`BASE_URL`, `MODEL`, `API_KEY`) into a managed custom-provider block in dsh's `~/.dsh/settings.yaml`, including multi-model registration and default-model selection, applied idempotently on every container boot.

## Requirements

### Requirement: Custom provider registration

The deployment SHALL write a managed provider block into `$DSH_HOME/settings.yaml` when both `BASE_URL` and `MODEL` are set, registering an OpenAI-compatible provider that reads its API key from the `API_KEY` environment variable. The block SHALL be delimited by `# >>> dsh-web-managed` and `# <<< dsh-web-managed` markers, and rewriting it SHALL preserve any other settings in the file. When `BASE_URL` is unset, the managed block SHALL be removed.

#### Scenario: Registering a custom provider

- **WHEN** `BASE_URL` and `MODEL` are set at container boot
- **THEN** the managed block is written with a provider whose `baseURL` is the `BASE_URL` value, `api` is `openai-completions`, `apiKeyEnv` is `API_KEY`, and whose model list contains an entry for the `MODEL` value

#### Scenario: Removing the managed block

- **WHEN** `BASE_URL` is unset at container boot and a managed block exists in `settings.yaml`
- **THEN** the managed block is removed and non-managed settings in the file are left intact

#### Scenario: Idempotent rewrite

- **WHEN** the container boots repeatedly with the same env vars
- **THEN** the managed block content is identical across boots and unrelated settings are not duplicated

### Requirement: Comma-separated model list

The `MODEL` environment variable SHALL accept a comma-separated list of model ids. The deployment SHALL write every non-empty id as a separate entry in the provider's `models` list, trimming surrounding whitespace from each id.

#### Scenario: Multiple models from comma-separated value

- **WHEN** `MODEL` is set to `deepseek-chat,deepseek-reasoner`
- **THEN** the provider's `models` list contains entries for both `deepseek-chat` and `deepseek-reasoner`

#### Scenario: Whitespace and empty segments tolerated

- **WHEN** `MODEL` is set to ` a ,, b `
- **THEN** the provider's `models` list contains entries for `a` and `b` only

#### Scenario: Single model unchanged

- **WHEN** `MODEL` is set to a single id without commas
- **THEN** the provider's `models` list contains exactly that one entry, identical to the pre-change output

### Requirement: Default model selection

The deployment SHALL set the first model id in the `MODEL` list as the default model via `agent-default-model`, referencing the custom provider.

#### Scenario: First model becomes default

- **WHEN** `MODEL` is set to `deepseek-chat,deepseek-reasoner`
- **THEN** `agent-default-model` references the custom provider with `model: deepseek-chat`
