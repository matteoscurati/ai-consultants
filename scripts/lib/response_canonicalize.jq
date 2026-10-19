# response_canonicalize.jq - Canonicalize a parsed consultant answer into the
# documented response contract (scripts/lib/schema.json), or emit nothing when
# it cannot be done without guessing.
#
# Deterministic, content-preserving repairs of shapes observed from providers:
#   - a single wrapper key around the answer ({"answer": {...}});
#   - a flat answer without the "response" object ({"summary": ..., ...});
#   - "confidence" nested inside "response", or given as a bare number/string;
#   - a score given as a numeric string ("8/10"), a 0-1 fraction, a 0-100
#     percentage, or a word (very low|low|medium|moderate|high|very high);
#   - list fields given as a single string, or containing non-string items.
# Rejected (no output): anything that is not an object, has no "summary", or
# carries no usable confidence. Callers treat that as schema-invalid.

def str:
  if type == "string" then .
  elif type == "number" or type == "boolean" then tostring
  else null end;

def nonblank: type == "string" and test("\\S");

def strlist:
  if type == "array" then
    [ .[]
      | if type == "string" then .
        elif type == "number" or type == "boolean" then tostring
        elif type == "object" then ((.text // .description // .point // .name // null) | str)
        else null end
      | select(nonblank) ]
  elif nonblank then [.]
  else [] end;

def score_value:
  (if type == "number" then .
   elif type == "string" then
     (ascii_downcase | gsub("^\\s+|\\s+$"; "")) as $w
     | if $w == "very high" then 9 elif $w == "high" then 8 elif $w == "medium" or $w == "moderate" then 5
       elif $w == "low" then 3 elif $w == "very low" then 2
       else ((capture("(?<n>[0-9]+([.][0-9]+)?)") | .n | tonumber) // null) end
   else null end) as $n
  | if $n == null then null
    elif $n > 0 and $n < 1 then ($n * 10 | round | if . < 1 then 1 else . end)
    elif $n > 10 and $n <= 100 then ($n / 10 | round)
    elif $n < 1 then 1
    elif $n > 10 then 10
    else ($n | round) end;

def confidence_object:
  if type == "object" then .
  elif type == "number" or type == "string" then {score: .}
  else null end;

select(type == "object")

# {"answer": {...}} and similar single-key wrappers.
| if (has("response") | not) and (keys | length) == 1
     and (.[keys[0]] | type) == "object"
     and (.[keys[0]] | has("response") or has("summary"))
  then .[keys[0]] else . end

# Flat answer: the response fields sit at the top level.
| if (has("response") | not) and has("summary")
  then {response: del(.confidence), confidence: .confidence}
  else . end

| select((.response | type) == "object")

# Confidence: lift a nested object, accept a bare score.
| if (.confidence == null) then .confidence = .response.confidence else . end
| del(.response.confidence)
| .confidence = (.confidence | confidence_object)
| select(.confidence != null)
| .confidence.score = (.confidence.score | score_value)
| select(.confidence.score != null)
| .confidence.reasoning = ((.confidence.reasoning | str) // "")
| .confidence.uncertainty_factors = (.confidence.uncertainty_factors | strlist)

# Answer text.
# The summary must be provided by the consultant (it may be blank, which
# simply yields no summary finding). It is never derived from "detailed":
# detailed text is deliberately not atomized into attributable findings.
| .response.detailed = ((.response.detailed | str) // "")
| .response.summary = (.response.summary | str)
| select(.response.summary != null)
| .response.approach = (((.response.approach | str) // "") | if nonblank then . else "unspecified" end)

# List fields.
| .response.pros |= strlist
| .response.cons |= strlist
| .response.caveats |= strlist
| .response.references |= strlist
| .response.alternatives |= (if type == "array" then [ .[] | select(type == "string" or type == "object") ]
                             elif nonblank then [.]
                             else [] end)
| if (.response.code_snippets | type) == "array"
  then .response.code_snippets |= [ .[] | select(type == "object") ]
  else del(.response.code_snippets) end
