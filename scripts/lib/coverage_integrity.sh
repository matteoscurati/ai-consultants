#!/bin/bash
# coverage_integrity.sh - Local normalization and audit for coverage synthesis.

# The source-ID slug is intentionally small and stable: ASCII lowercase,
# retaining only alphanumeric characters and underscores; every other run is
# one underscore, and an empty result becomes "unknown".
coverage_source_slug_contract() {
    printf '%s' 'ASCII lowercase; [a-z0-9_] retained; other runs become _; empty becomes unknown'
}

# Normalize one successful consultant envelope in place. Provider-supplied
# findings/IDs are discarded; only documented atomic legacy fields are used.
normalize_coverage_response_file() {
    local response_file="$1" tmp_file

    _is_successful_consultant_response_file "$response_file" || return 0
    tmp_file=$(mktemp "${response_file}.coverage.XXXXXX")
    if jq '
        def source_slug:
            ascii_downcase | gsub("[^a-z0-9_]+"; "_") | gsub("^_+|_+$"; "")
            | if length > 0 then . else "unknown" end;
        def text_items:
            if type == "array" then .[]? | select(type == "string" and test("\\S")) else empty end;
        def alternative_text:
            if type == "string" then select(test("\\S"))
            elif type == "object" then
                [.name?, .reason_not_chosen? | select(type == "string" and test("\\S"))] | join(": ")
                | select(test("\\S"))
            else empty end;
        (.consultant | tostring | source_slug) as $consultant |
        ((.metadata.response_quality // "unknown") == "fallback"
         or (.response.approach // "") == "unstructured-provider-response") as $fallback |
        if $fallback then
            .response.findings = []
        else
            ([
                (.response.summary? | select(type == "string" and test("\\S")) | {kind: "summary", field: "summary", text: .}),
                (.response.pros? | text_items | {kind: "recommendation", field: "pros", text: .}),
                (.response.cons? | text_items | {kind: "trade_off", field: "cons", text: .}),
                (.response.alternatives? | if type == "array" then .[] | alternative_text else empty end | {kind: "alternative", field: "alternatives", text: .}),
                (.response.caveats? | text_items | {kind: "edge_case", field: "caveats", text: .}),
                (.response.references? | text_items | {kind: "evidence", field: "references", text: .})
            ] | to_entries | map(.value + {id: ($consultant + ":" + ((.key + 1) | tostring))})) as $findings
            | .response.findings = $findings
        end
    ' "$response_file" > "$tmp_file"; then
        mv "$tmp_file" "$response_file"
    else
        rm -f "$tmp_file"
        return 1
    fi
}

# Successful fallback prose and successful envelopes with no atomic evidence
# are both non-normalizable for coverage. The prose is still usable as manual
# review context, never as source-attributed coverage.
response_is_non_normalizable() {
    local response_file="$1"
    jq -e '((.metadata.response_quality // "unknown") == "fallback"
        or (.response.approach // "") == "unstructured-provider-response"
        or ((.response.findings // []) | length == 0))' "$response_file" >/dev/null 2>&1
}

# Add a complete local coverage_integrity record. This is robust to any valid
# JSON top level. It never leaves a raw malformed model payload as a reportable
# synthesis artifact.
annotate_coverage_integrity() {
    local synthesis_file="$1" expected_ids_json="$2" non_normalizable_json="$3" strategy="$4"
    local coverage_input_truncated="${5:-false}" truncated_consultants_json="${6:-[]}"
    local tmp_file
    tmp_file=$(mktemp "${synthesis_file}.integrity.XXXXXX")
    if jq --argjson expected "$expected_ids_json" \
        --argjson non_normalizable "$non_normalizable_json" --arg strategy "$strategy" \
        --argjson coverage_input_truncated "$coverage_input_truncated" \
        --argjson truncated_consultants "$truncated_consultants_json" '
        def audited_fields: ["summary", "pros", "cons", "alternatives", "caveats", "references"];
        def truncation_disclosure:
            if $coverage_input_truncated then
                " Usable non-normalizable fallback context was truncated at the configured Unicode-code-point limit for: "
                + ($truncated_consultants | join(", ")) + "."
            else "" end;
        def safe_partial_wording:
            if type != "string" then . else
                gsub("(?i)\\bnot[[:space:]]+comprehensive\\b"; "__NEGATED_COMPREHENSIVE__")
                | gsub("(?i)\\bcomprehensive\\b"; "partial")
                | gsub("__NEGATED_COMPREHENSIVE__"; "not comprehensive")
            end;
        def integrity_failure($error): {
            status: "FAILED", expected_count: ($expected | length), represented_count: 0,
            missing_ids: $expected, unknown_ids: [], duplicate_ids: [],
            non_normalizable_consultants: $non_normalizable, structural_errors: [$error],
            audited_fields: audited_fields, normalization_version: "1",
            disclosure: ("Coverage attribution is unusable; do not treat this synthesis as comprehensive." + truncation_disclosure)
        };
        def valid_source_ids: type == "array" and length > 0 and all(.[]?; type == "string" and length > 0);
        def structural_error:
            if (.coverage | type) != "array" then "coverage must be an array"
            elif any(.coverage[]?; type != "object") then "every coverage item must be an object"
            elif any(.coverage[]?; (.source_ids? | valid_source_ids | not)) then "every coverage item must contain source_ids as a non-empty string array"
            else "" end;
        if type != "object" then
            {synthesis_version: "3.0-integrity-failure", strategy: $strategy, consultants_analyzed: 0,
             coverage: [], weighted_recommendation: {approach: "manual_review", summary: "Automatic synthesis output was unusable.", detailed: "Consult individual responses."},
             risk_assessment: {overall_risk: "unknown", risks: []}, action_items: [], follow_up_questions: [], fallback: true}
            | .coverage_integrity = integrity_failure("synthesis top level must be an object")
            | .coverage_input_truncated = $coverage_input_truncated
            | .truncated_consultants = $truncated_consultants
        else
            .strategy = $strategy |
            .coverage_input_truncated = $coverage_input_truncated |
            .truncated_consultants = $truncated_consultants |
            (structural_error) as $structural_error |
            if $structural_error != "" then
                .coverage = [] |
                .coverage_integrity = integrity_failure($structural_error)
                | (.weighted_recommendation.summary? |= safe_partial_wording)
                | (.weighted_recommendation.detailed? |= safe_partial_wording)
            else
                [.coverage[]?.source_ids[]] as $represented |
                [$expected[] as $id | select(($represented | index($id)) == null) | $id] as $missing |
                ([$represented[] as $id | select(($expected | index($id)) == null) | $id] | unique) as $unknown |
                ([$represented | sort | group_by(.)[] | select(length > 1) | .[0]]) as $duplicates |
                ([$represented[] as $id | select(($expected | index($id)) != null) | $id] | unique) as $known_represented |
                (if ($unknown | length) > 0 then "FAILED"
                 elif ($strategy != "coverage" and $strategy != "union") then "NOT_APPLICABLE"
                 elif (($expected | length) == 0 or ($missing | length) > 0 or ($duplicates | length) > 0 or ($non_normalizable | length) > 0 or $coverage_input_truncated) then "DEGRADED"
                 else "MET" end) as $status |
                (if ($unknown | length) > 0 then
                    .coverage |= (map(.source_ids |= [.[] as $id | select(($expected | index($id)) != null) | $id]) | map(select((.source_ids | length) > 0)))
                 else . end) |
                .coverage_integrity = {status: $status, expected_count: ($expected | length), represented_count: ($known_represented | length),
                    missing_ids: $missing, unknown_ids: $unknown, duplicate_ids: $duplicates,
                    non_normalizable_consultants: $non_normalizable, structural_errors: [], audited_fields: audited_fields,
                    normalization_version: "1",
                    disclosure: ((if $status == "MET" then "Every normalized source ID from the audited fields is represented exactly once."
                        elif $status == "NOT_APPLICABLE" then "The selected strategy is not a coverage-union claim."
                        elif $status == "DEGRADED" then "Coverage is incomplete over the audited fields; do not treat this synthesis as comprehensive."
                        else "Coverage attribution contains unknown source IDs; do not treat this synthesis as comprehensive." end) + truncation_disclosure)}
                | if $status == "DEGRADED" or $status == "FAILED" or $coverage_input_truncated then
                    (.weighted_recommendation.summary? |= safe_partial_wording) | (.weighted_recommendation.detailed? |= safe_partial_wording)
                  else . end
            end
        end
    ' "$synthesis_file" > "$tmp_file" && [[ -s "$tmp_file" ]]; then
        mv "$tmp_file" "$synthesis_file"
    else
        rm -f "$tmp_file"
        return 1
    fi
}
