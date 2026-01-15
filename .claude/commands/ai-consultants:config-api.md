---
description: Configure API-based consultants (Qwen3, GLM, Grok, custom)
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

## Instructions

### Step 1: Show Current Status

```bash
cd "${AI_CONSULTANTS_DIR:-$HOME/.claude/skills/ai-consultants}" && source scripts/config.sh
echo "=== API Consultant Status ==="
for provider in QWEN3 GLM GROK; do
  enabled_var="ENABLE_$provider"
  key_var="${provider}_API_KEY"
  model_var="${provider}_MODEL"
  echo "$provider: ${!enabled_var:-false} (API key: $([ -n \"${!key_var}\" ] && echo 'set' || echo 'not set'))"
done
```

### Step 2: Configure a Provider

To enable an API consultant, update the .env file:

| Provider | Required Variables |
|----------|-------------------|
| Qwen3 | `ENABLE_QWEN3=true`, `QWEN3_API_KEY=<key>` |
| GLM | `ENABLE_GLM=true`, `GLM_API_KEY=<key>` |
| Grok | `ENABLE_GROK=true`, `GROK_API_KEY=<key>` |

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
