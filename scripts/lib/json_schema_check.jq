# json_schema_check.jq - Minimal JSON Schema (draft-07 subset) checker in jq,
# so the documented contracts in scripts/lib/schema.json are executable
# without a Python/Node dependency.
#
# Supported keywords: type (string or array), required, properties, items,
# enum, minimum, maximum, minLength, minItems, pattern, and local
# "$ref": "#/definitions/<name>". Unknown keywords are ignored.
#
# Usage:
#   jq -n --slurpfile schema scripts/lib/schema.json --slurpfile doc file.json \
#      [--arg definition synthesis_artifact] -f scripts/lib/json_schema_check.jq
# Output: an array of error strings (empty when the document conforms).

def resolve($root):
  if type == "object" and has("$ref")
  then $root.definitions[(.["$ref"] | sub("^#/definitions/"; ""))]
  else . end;

def json_type:
  if type == "number" then (if . == floor then "integer" else "number" end) else type end;

def type_ok($t):
  json_type as $a
  | if $t == "number" then ($a == "number" or $a == "integer") else $a == $t end;

def check($schema; $root; $path):
  ($schema | resolve($root)) as $s
  | . as $v
  # A $ref to a missing definition must not validate everything vacuously.
  | if ($s | type) != "object" then ["\($path): unresolvable schema \($schema | tojson)"] else
    (if ($s.type // null) == null then []
     elif ($s.type | type) == "array" then
       (if any($s.type[]; . as $t | $v | type_ok($t)) then [] else ["\($path): expected one of \($s.type | join("|")), got \($v | json_type)"] end)
     elif ($v | type_ok($s.type)) then []
     else ["\($path): expected \($s.type), got \($v | json_type)"] end) as $type_errors
  | if ($type_errors | length) > 0 then $type_errors else
      [
        (if $s.enum and (any($s.enum[]; . == $v) | not) then "\($path): \($v | tojson) not in enum" else empty end),
        (if ($v | type) == "object" then
           (($s.required // [])[] | . as $k | select(($v | has($k)) | not) | "\($path): missing required \($k)"),
           (($s.properties // {}) | to_entries[] | . as $p | select($v | has($p.key))
             | ($v[$p.key] | check($p.value; $root; "\($path).\($p.key)"))[])
         else empty end),
        (if ($v | type) == "array" then
           (if $s.minItems and ($v | length) < $s.minItems then "\($path): fewer than \($s.minItems) items" else empty end),
           (if $s.items then ($v | to_entries[] | .key as $i | .value | check($s.items; $root; "\($path)[\($i)]"))[] else empty end)
         else empty end),
        (if ($v | type) == "number" then
           (if ($s.minimum != null) and $v < $s.minimum then "\($path): \($v) < minimum \($s.minimum)" else empty end),
           (if ($s.maximum != null) and $v > $s.maximum then "\($path): \($v) > maximum \($s.maximum)" else empty end)
         else empty end),
        (if ($v | type) == "string" then
           (if $s.minLength and ($v | length) < $s.minLength then "\($path): shorter than \($s.minLength)" else empty end),
           (if $s.pattern and ($v | test($s.pattern) | not) then "\($path): does not match \($s.pattern)" else empty end)
         else empty end)
      ]
    end
    end;

$schema[0] as $root
| ($ARGS.named.definition // "") as $definition
| (if $definition != "" then $root.definitions[$definition] else $root end) as $target
# An unknown definition name is an error, never an empty (passing) result.
| if $target == null then ["unknown schema definition: \($definition)"]
  else $doc[0] | check($target; $root; "$") end
