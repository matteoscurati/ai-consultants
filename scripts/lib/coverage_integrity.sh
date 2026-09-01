#!/bin/bash
# coverage_integrity.sh - Local normalization and audit for coverage synthesis.

# Normalize one successful consultant envelope in place. Provider-supplied
# finding IDs are discarded: IDs are local, deterministic, and scoped to the
# consultant response.
normalize_coverage_response_file() {
    local response_file="$1" tmp_file

    _is_successful_consultant_response_file "$response_file" || return 0
    tmp_file=$(mktemp "${response_file}.coverage.XXXXXX")
    if jq '
        def text_items:
            if type == "array" then .[]? | select(type == "string" and test("\\S")) else empty end;
        def alternative_text:
            if type == "object" then
                [.name?, .reason_not_chosen? | select(type == "string" and test("\\S"))] | join(": ")
            else empty end;
        (.consultant | tostring | ascii_downcase) as $consultant |
        ((.metadata.response_quality // "unknown") == "fallback"
         or (.response.approach // "") == "unstructured-provider-response") as $non_normalizable |
        if $non_normalizable then
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

response_is_non_normalizable() {
    local response_file="$1"
    jq -e '(.metadata.response_quality // "unknown") == "fallback"
        or (.response.approach // "") == "unstructured-provider-response"' \
        "$response_file" >/dev/null 2>&1
}

# Add coverage_integrity to a synthesis file. Malformed coverage fails closed.
annotate_coverage_integrity() {
    local synthesis_file="$1" expected_ids_json="$2" non_normalizable_json="$3" strategy="$4"
    local tmp_file
    tmp_file=$(mktemp "${synthesis_file}.integrity.XXXXXX")
    if ! jq --argjson expected "$expected_ids_json" \
        --argjson non_normalizable "$non_normalizable_json" --arg strategy "$strategy" '
        def valid_source_ids: type == "array" and all(.[]?; type == "string" and length > 0);
        def structural_error:
            if (.coverage | type) != "array" then "coverage must be an array"
            elif any(.coverage[]?; type != "object") then "every coverage item must be an object"
            elif any(.coverage[]?; (.source_ids? | valid_source_ids | not)) then "every coverage item must contain source_ids as a non-empty string array"
            else "" end;
        def partial_wording: if type == "string" then gsub("(?i)comprehensive"; "partial") else . end;
        .strategy = (.strategy // $strategy) |
        (structural_error) as $structural_error |
        if $structural_error != "" then
            # Do not publish malformed model coverage as if it were a valid
            # coverage item. The failure is retained in integrity metadata.
            .coverage = [] |
            .coverage_integrity = {status: "FAILED", expected_count: ($expected | length), represented_count: 0,
                missing_ids: $expected, unknown_ids: [], duplicate_ids: [],
                non_normalizable_consultants: $non_normalizable, structural_errors: [$structural_error],
                disclosure: "Coverage attribution is unusable; do not treat this synthesis as comprehensive."}
            | (.weighted_recommendation.summary? |= partial_wording)
            | (.weighted_recommendation.detailed? |= partial_wording)
        else
            [.coverage[]?.source_ids[]] as $represented |
            [$expected[] as $id | select(($represented | index($id)) == null) | $id] as $missing |
            ([$represented[] as $id | select(($expected | index($id)) == null) | $id] | unique) as $unknown |
            ([$represented | sort | group_by(.)[] | select(length > 1) | .[0]]) as $duplicates |
            ([$represented[] as $id | select(($expected | index($id)) != null) | $id] | unique) as $known_represented |
            (if ($unknown | length) > 0 then "FAILED"
             elif ($strategy != "coverage" and $strategy != "union") then "NOT_APPLICABLE"
             elif (($missing | length) > 0 or ($duplicates | length) > 0 or ($non_normalizable | length) > 0) then "DEGRADED"
             else "MET" end) as $status |
            # Keep the emitted coverage contract closed even when a model
            # invents attribution: expose the bad IDs in integrity metadata,
            # but do not carry them forward as coverage source_ids.
            (if ($unknown | length) > 0 then
                .coverage |= (map(
                    .source_ids |= [.[] as $id | select(($expected | index($id)) != null) | $id]
                ) | map(select((.source_ids | length) > 0)))
             else . end) |
            .coverage_integrity = {status: $status, expected_count: ($expected | length),
                represented_count: ($known_represented | length), missing_ids: $missing, unknown_ids: $unknown,
                duplicate_ids: $duplicates, non_normalizable_consultants: $non_normalizable, structural_errors: [],
                disclosure: (if $status == "MET" then "Every normalized source ID is represented exactly once."
                    elif $status == "NOT_APPLICABLE" then "The selected strategy is not a coverage-union claim."
                    elif $status == "DEGRADED" then "Coverage is incomplete; do not treat this synthesis as comprehensive."
                    else "Coverage attribution contains unknown source IDs; do not treat this synthesis as comprehensive." end)}
            | if $status == "DEGRADED" or $status == "FAILED" then
                (.weighted_recommendation.summary? |= partial_wording) | (.weighted_recommendation.detailed? |= partial_wording)
              else . end
        end
    ' "$synthesis_file" > "$tmp_file"; then
        rm -f "$tmp_file"
        return 1
    fi
    mv "$tmp_file" "$synthesis_file"
}
