# Parse line-delimited events without losing billing on a truncated last line.
split("\n") | map(select(test("\\S"))) | map(try fromjson catch null) as $events
| [$events[] | objects | select(.type == "result")] as $terminals
| ($terminals[-1] // {}) as $terminal
| [$events[] | objects | select(.type == "assistant") | .message
    | select(any(.content[]?; .type == "text" and (.text | type == "string") and (.text | length > 0)))] as $messages
| [$messages[].model] as $models
| (if ($models | length) > 0 and all($models[]; type == "string" and test("^claude-[A-Za-z0-9._/-]+$")) and ($models | unique | length) == 1
   then $models[0] else null end) as $model
| ([$messages[] | select(.id != null)] | unique_by(.id)) as $unique_messages
| ([$terminal.modelUsage[]?] ) as $billing
| ($terminal.usage // (if ($billing | length) > 0 then {
    input_tokens: ([$billing[] | (.inputTokens // 0) + (.cacheCreationInputTokens // 0) + (.cacheReadInputTokens // 0)] | add),
    output_tokens: ([$billing[].outputTokens // 0] | add)
  } else {
    input_tokens: ([$unique_messages[].usage | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)] | add // 0),
    output_tokens: ([$unique_messages[].usage.output_tokens // 0] | add // 0)
  } end)) as $usage
| {
  success: (($events | all(type == "object" and .type != "error" and .is_error != true)) and ($terminals | length) == 1 and $events[-1] == $terminal
    and $terminal.subtype == "success" and $terminal.is_error != true and ($terminal.result | type == "string")
    and $terminal.stop_reason != "max_tokens" and all($messages[]; .stop_reason != "max_tokens" and .error == null)),
  result: $terminal.result,
  content_model: $model,
  billing_models: ($terminal.modelUsage // {} | keys),
  input_tokens: (($usage.input_tokens // 0) + ($usage.cache_creation_input_tokens // 0) + ($usage.cache_read_input_tokens // 0)),
  output_tokens: ($usage.output_tokens // 0),
  tokens_source: (if $terminal.usage != null or ($billing | length) > 0 or any($unique_messages[]; .usage != null) then "measured" else "estimated" end),
  cost: ($terminal.total_cost_usd // ([$billing[].costUSD | numbers] | add))
}
