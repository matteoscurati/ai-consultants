# synthesis_canonicalize.jq - Bring a synthesis object to the documented
# synthesis_artifact contract (scripts/lib/schema.json) before the local
# coverage-integrity audit.
#
# Arguments: $strategy (selected strategy), $count (successful consultant
# responses), $timestamp (local ISO-8601 time).
#
# Only presentation fields are canonicalized. Coverage attribution is left to
# annotate_coverage_integrity: items keep their source_ids untouched, and a
# non-array coverage under coverage/union still fails there. A non-object
# input passes through unchanged so the auditor replaces it fail-closed.

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
        elif type == "object" then ((.text // .question // .description // .name // null) | str)
        else null end
      | select(nonblank) ]
  elif nonblank then [.]
  else [] end;

def level:
  (str // "" | ascii_downcase) as $l
  | if $l == "low" or $l == "medium" or $l == "high" then $l
    elif $l == "moderate" then "medium"
    elif $l == "critical" or $l == "severe" then "high"
    elif $l == "minor" then "low"
    else "unknown" end;

if type != "object" then . else
  .synthesis_version = ((.synthesis_version | str) // "3.0")
  | .timestamp = $timestamp
  | .consultants_analyzed = $count

  | if (.coverage == null) and ($strategy != "coverage" and $strategy != "union")
    then .coverage = [] else . end
  | if (.coverage | type) == "array" then
      .coverage |= map(
        if type == "object" then
          .point = ((.point | str) // "")
          | .raised_by = (.raised_by | strlist)
          | .kind = (((.kind | str) // "consideration") | if nonblank then . else "consideration" end)
        else . end)
    else . end

  | .weighted_recommendation = (.weighted_recommendation
      | if type == "object" then . elif nonblank then {summary: .} else {} end)
  | .weighted_recommendation.approach = (((.weighted_recommendation.approach | str) // "")
      | if nonblank then . else "unspecified" end)
  | .weighted_recommendation.summary = ((.weighted_recommendation.summary | str) // "")
  | .weighted_recommendation.detailed = ((.weighted_recommendation.detailed | str) // "")
  | .weighted_recommendation.supporting_consultants |= strlist
  | .weighted_recommendation.incorporated_insights |= strlist

  | .risk_assessment = (.risk_assessment | if type == "object" then . else {} end)
  | .risk_assessment.overall_risk = (.risk_assessment.overall_risk | level)
  | .risk_assessment.risks = [
      (.risk_assessment.risks | if type == "array" then .[] elif nonblank then . else empty end)
      | if type == "object" then
          {description: ((.description // .risk // .name // .text) | str),
           severity: (.severity | level),
           mitigation: ((.mitigation | str) // ""),
           identified_by: (.identified_by | strlist)}
        elif nonblank then {description: ., severity: "unknown", mitigation: "", identified_by: []}
        else empty end
      | select(.description | nonblank) ]

  | .action_items = [
      (.action_items | if type == "array" then .[] elif nonblank then . else empty end)
      | if type == "object" then
          {priority: .priority, action: ((.action // .title // .text) | str), rationale: ((.rationale | str) // "")}
        elif nonblank then {priority: null, action: ., rationale: ""}
        else empty end
      | select(.action | nonblank) ]
    | .action_items |= [ to_entries[] | .value.priority = (
        (.value.priority | if type == "number" then (floor | if . < 1 then 1 else . end)
                           elif type == "string" then ((capture("(?<n>[0-9]+)") | .n | tonumber) // null)
                           else null end) // (.key + 1)) | .value ]

  | .follow_up_questions |= strlist
end
