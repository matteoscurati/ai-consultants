#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
python3 - "$SCRIPT_DIR" <<'PY'
import json, subprocess, sys
script=sys.argv[1]+'/lib/claude_stream.jq'
a={'type':'assistant','message':{'id':'a','model':'claude-fable-5-1','content':[{'type':'text','text':'hello'}],'usage':{'input_tokens':2,'output_tokens':3}}}
t={'type':'result','subtype':'success','result':'hello','total_cost_usd':0.7,'usage':{'input_tokens':10,'output_tokens':20},'modelUsage':{'billing-only':{'costUSD':0.2}}}
def parse(events, tail=''):
 return json.loads(subprocess.check_output(['jq','-Rs','-f',script],input=('\n'.join(map(json.dumps,events))+tail).encode()))
r=parse([a,t]); assert r['success'] and r['content_model']=='claude-fable-5-1' and r['cost']==0.7 and r['input_tokens']==10
assert parse([t])['content_model'] is None
for model in [None,'opus','bad model']:
 b=json.loads(json.dumps(a)); b['message']['model']=model
 assert parse([b,t])['content_model'] is None
b=json.loads(json.dumps(a)); b['message']['model']='claude-opus-5'
assert parse([b,t])['content_model']=='claude-opus-5'
assert parse([a,b,t])['content_model'] is None
assert not parse([a])['success']
assert parse([a,a])['input_tokens']==2
assert not parse([a,t], '\n{"cut":')['success']
for field,value in [('subtype','error_max_turns'),('is_error',True),('stop_reason','max_tokens')]:
 u=dict(t);u[field]=value;r=parse([a,u]);assert not r['success'] and r['cost']==0.7
assert not parse([a,t,t])['success']
assert not parse([a,{'type':'error','error':'provider failure'},t])['success']
assert not parse([42,a,t])['success']
print('Claude stream identity, completion and accounting checks passed')
PY
mkdir -p "$TMP/bin" "$TMP/home" "$TMP/config"
printf '#!/bin/bash\n: > "$DISPATCH_FILE"\nexit 99\n' > "$TMP/bin/curl"
chmod +x "$TMP/bin/curl"
for provider in claude codex; do
    rc=0
    env -u ANTHROPIC_API_KEY -u OPENAI_API_KEY HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/config" \
        AI_CONSULTANTS_CONFIG_DIR="$TMP/config" PATH="$TMP/bin:$PATH" DISPATCH_FILE="$TMP/dispatched" \
        CLAUDE_USE_API=true CODEX_USE_API=true ENABLE_PERSONA=false \
        bash "$SCRIPT_DIR/query_$provider.sh" hello '' "$TMP/$provider.json" > /dev/null 2>&1 || rc=$?
    [[ $rc -ne 0 && ! -e "$TMP/dispatched" ]]
    jq -e '.metadata.response_quality == "error"' "$TMP/$provider.json" >/dev/null
done
printf '%s\n' 'Missing API keys write errors without dispatch'
