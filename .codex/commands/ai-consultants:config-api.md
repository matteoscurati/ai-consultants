---
description: Configure API-based consultants (Qwen3, GLM, Grok, DeepSeek, custom)
argument-hint: [provider] [api-key]
allowed-tools: Bash Read Edit
---

# AI Consultants - API Configuration

Configure API-based consultants. These require API keys but no CLI installation.

**Arguments:** $ARGUMENTS

## Available API Consultants

| Provider | Model | Persona | API Key Source |
|----------|-------|---------|----------------|
| Qwen3 | qwen-max | The Analyst | https://dashscope.console.aliyun.com/ |
| GLM | glm-4 | The Methodologist | https://open.bigmodel.cn/ |
| Grok | grok-beta | The Provocateur | https://console.x.ai/ |
| DeepSeek | deepseek-coder | The Code Specialist | https://platform.deepseek.com/ |

## Instructions

### Step 1: Show Current Status

```bash
ENV_FILE="${AI_CONSULTANTS_DIR:-$HOME/.codex/skills/ai-consultants}/.env"
echo "=== API Consultant Status ==="
for provider in QWEN3 GLM GROK DEEPSEEK; do
  enabled=$(grep "^ENABLE_${provider}=" "$ENV_FILE" 2>/dev/null | cut -d= -f2 || echo "false")
  has_key=$(grep "^${provider}_API_KEY=" "$ENV_FILE" 2>/dev/null | grep -v '=$' > /dev/null && echo "set" || echo "not set")
  echo "$provider: ${enabled:-false} (API key: $has_key)"
done
```

### Step 2: Configure a Provider

To enable an API consultant, update the .env file:

| Provider | Required Variables |
|----------|-------------------|
| Qwen3 | `ENABLE_QWEN3=true`, `QWEN3_API_KEY=<key>` |
| GLM | `ENABLE_GLM=true`, `GLM_API_KEY=<key>` |
| Grok | `ENABLE_GROK=true`, `GROK_API_KEY=<key>` |
| DeepSeek | `ENABLE_DEEPSEEK=true`, `DEEPSEEK_API_KEY=<key>` |

### Step 3: Custom API Provider (Optional)

For OpenAI-compatible APIs (OpenRouter, Groq, Together):

```
ENABLE_CUSTOMNAME=true
CUSTOMNAME_API_KEY=<api-key>
CUSTOMNAME_API_URL=https://api.example.com/v1/chat/completions
CUSTOMNAME_MODEL=model-name
CUSTOMNAME_TIMEOUT=180
CUSTOMNAME_FORMAT=openai
```

### Step 4: Secure the Configuration

```bash
chmod 600 .env
```

## Security

- API keys stored with mode 600 (owner read/write only)
- Keys never logged or displayed in full
- The .env file is gitignored
