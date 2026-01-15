---
description: Configure API-based consultants (Qwen3, GLM, Grok, custom)
argument-hint: [provider] [api-key]
allowed-tools: Bash Read Edit
---

# AI Consultants - API Configuration

Configure API-based consultants. These require API keys but no CLI installation.

**Arguments:** $ARGUMENTS

## Available API Consultants

| Provider | Model | API URL | Persona |
|----------|-------|---------|---------|
| **Qwen3** | qwen-max | DashScope API | The Analyst |
| **GLM** | glm-4 | Zhipu BigModel | The Methodologist |
| **Grok** | grok-beta | xAI API | The Provocateur |

## Instructions

### Step 1: Show Current API Status

```bash
cd /Users/matteoscurati/work/ai-consultants
source scripts/config.sh

echo "=== API Consultant Status ==="
echo "Qwen3: ${ENABLE_QWEN3:-false}"
echo "  - API Key: $([ -n \"$QWEN3_API_KEY\" ] && echo '****' || echo 'not set')"
echo "  - Model: ${QWEN3_MODEL:-qwen-max}"
echo ""
echo "GLM: ${ENABLE_GLM:-false}"
echo "  - API Key: $([ -n \"$GLM_API_KEY\" ] && echo '****' || echo 'not set')"
echo "  - Model: ${GLM_MODEL:-glm-4}"
echo ""
echo "Grok: ${ENABLE_GROK:-false}"
echo "  - API Key: $([ -n \"$GROK_API_KEY\" ] && echo '****' || echo 'not set')"
echo "  - Model: ${GROK_MODEL:-grok-beta}"
```

### Step 2: Configure a Provider

If the user wants to enable an API consultant:

1. **Ask which provider** (Qwen3, GLM, Grok, or Custom)
2. **Ask for the API key**
3. **Update .env file** with:

For Qwen3:
```
ENABLE_QWEN3=true
QWEN3_API_KEY=<api-key>
```

For GLM:
```
ENABLE_GLM=true
GLM_API_KEY=<api-key>
```

For Grok:
```
ENABLE_GROK=true
GROK_API_KEY=<api-key>
```

### Step 3: Add Custom API Provider

For any OpenAI-compatible API (OpenRouter, Groq, Together, etc.):

```
ENABLE_CUSTOMNAME=true
CUSTOMNAME_API_KEY=<api-key>
CUSTOMNAME_API_URL=https://api.example.com/v1/chat/completions
CUSTOMNAME_MODEL=model-name
CUSTOMNAME_TIMEOUT=180
CUSTOMNAME_FORMAT=openai
```

### Step 4: Set File Permissions

After updating .env, ensure secure permissions:

```bash
chmod 600 .env
```

## API Key Sources

- **Qwen3**: https://dashscope.console.aliyun.com/
- **GLM**: https://open.bigmodel.cn/
- **Grok**: https://console.x.ai/

## Security Notes

- API keys are stored in .env with mode 600 (owner read/write only)
- Keys are never logged or displayed in full
- The .env file is gitignored by default
