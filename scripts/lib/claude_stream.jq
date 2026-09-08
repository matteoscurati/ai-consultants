# Preserve usable accounting even when a provider event has malformed fields.
def object: if type == "object" then . else {} end;
def token: if type == "number" and . >= 0 and floor == . then . else 0 end;
def has_usage: object | any(.input_tokens, .output_tokens, .cache_creation_input_tokens, .cache_read_input_tokens; type == "number");
split("\n") | map(select(test("\\S"))) | map(try fromjson catch null) as $events
| [$events[] | objects | select(.type == "result")] as $terminals
| ($terminals[-1] // {}) as $terminal
| [$events[] | objects | select(.type == "assistant") | .message | objects] as $assistants
| [$assistants[] | select(any(.content[]? | objects; .type == "text" and (.text | type == "string" and test("\\S"))))] as $messages
| [$messages[].model] as $models
| (if ($models | length) > 0 and all($models[]; type == "string" and length <= 128 and test("^claude-[A-Za-z0-9._/-]+$")) and ($models | unique | length) == 1
   then $models[0] else null end) as $model
| ($assistants | group_by(.id // tostring) | map(last)) as $unique_messages
| ($terminal.modelUsage | object) as $billing_map
| [$billing_map[] | objects] as $billing
| (any($billing[]; any(.inputTokens, .outputTokens, .cacheCreationInputTokens, .cacheReadInputTokens; type == "number"))) as $billing_usage
| (if $billing_usage then {
    input_tokens: ([$billing[] | ((.inputTokens | token) + (.cacheCreationInputTokens | token) + (.cacheReadInputTokens | token))] | add // 0),
    output_tokens: ([$billing[] | .outputTokens | token] | add // 0)
  } elif ($terminal.usage | has_usage) then ($terminal.usage | object)
  else {
    input_tokens: ([$unique_messages[].usage | object | ((.input_tokens | token) + (.cache_creation_input_tokens | token) + (.cache_read_input_tokens | token))] | add // 0),
    output_tokens: ([$unique_messages[].usage | object | .output_tokens | token] | add // 0)
  } end) as $usage
| {
  success: (($events | all(type == "object" and .type != "error" and .is_error != true)) and ($terminals | length) == 1 and $events[-1] == $terminal
    and $terminal.subtype == "success" and $terminal.is_error != true and ($terminal.result | type == "string" and test("\\S"))
    and $terminal.stop_reason != "max_tokens" and all($assistants[]; .stop_reason != "max_tokens" and .error == null)),
  result: (if ($terminal.result | type) == "string" then $terminal.result else ([$messages[].content[]? | objects | select(.type == "text") | .text | strings] | join("\n")) end),
  content_model: $model,
  billing_models: ($billing_map | keys),
  input_tokens: (($usage.input_tokens | token) + ($usage.cache_creation_input_tokens | token) + ($usage.cache_read_input_tokens | token)),
  output_tokens: ($usage.output_tokens | token),
  tokens_source: (if $billing_usage or ($terminal.usage | has_usage) or any($unique_messages[]; .usage | has_usage) then "measured" else "estimated" end),
  cost: (($terminal.total_cost_usd | numbers | select(. >= 0)) // ([$billing[].costUSD | numbers | select(. >= 0)] | add))
}
