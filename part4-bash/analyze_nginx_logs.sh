#!/usr/bin/env bash
# analyze_nginx_logs.sh — Nginx access log analyzer
# Usage: ./analyze_nginx_logs.sh [/path/to/access.log]
# Defaults to /var/log/nginx/access.log if no argument given.

set -euo pipefail

# ─── Config ───────────────────────────────────────────────────────────────────

LOG_FILE="${1:-/var/log/nginx/access.log}"
TOP_N=10

# ─── Validation ───────────────────────────────────────────────────────────────

if [[ ! -f "$LOG_FILE" ]]; then
    echo "ERROR: Log file not found: $LOG_FILE" >&2
    echo "Usage: $0 [/path/to/access.log]" >&2
    exit 1
fi

if [[ ! -r "$LOG_FILE" ]]; then
    echo "ERROR: Log file not readable (try sudo): $LOG_FILE" >&2
    exit 1
fi

# ─── Helper: print a separator line ──────────────────────────────────────────

separator() {
    printf '%0.s─' {1..60}
    echo
}

# ─── Pre-process: strip malformed lines ───────────────────────────────────────
# Nginx combined log format:
#   $remote_addr - $remote_user [$time_local] "$request" $status $bytes "$referer" "$user_agent"
# We filter lines that have at least 7 space-separated fields and a valid IP at field 1.

VALID_LOG=$(mktemp /tmp/nginx_valid.XXXXXX)
trap 'rm -f "$VALID_LOG"' EXIT

awk '
NF >= 7 && $1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$|^[0-9a-fA-F:]+$/ {
    print
}
' "$LOG_FILE" > "$VALID_LOG"

TOTAL_LINES=$(wc -l < "$LOG_FILE")
VALID_LINES=$(wc -l < "$VALID_LOG")
SKIPPED=$(( TOTAL_LINES - VALID_LINES ))

# ─── Metrics ──────────────────────────────────────────────────────────────────

# Total requests (valid lines only)
TOTAL_REQUESTS=$VALID_LINES

# Unique IPs — field 1
UNIQUE_IPS=$(awk '{print $1}' "$VALID_LOG" | sort -u | wc -l)

# Status code counts — field 9 (combined format) or field 7 (common format)
# We try field 9 first; fall back to field 7 if median value looks like a code.
detect_status_field() {
    # Sample first 100 valid lines, pick the field whose values are 3-digit HTTP codes
    for field in 9 7 8; do
        count=$(awk -v f="$field" 'NR<=100 && $f ~ /^[1-5][0-9]{2}$/ {c++} END {print c+0}' "$VALID_LOG")
        if [[ $count -gt 5 ]]; then
            echo "$field"
            return
        fi
    done
    echo "9"  # default
}
STATUS_FIELD=$(detect_status_field)

# 4xx and 5xx counts
ERRORS_4XX=$(awk -v f="$STATUS_FIELD" '$f ~ /^4[0-9]{2}$/ {c++} END {print c+0}' "$VALID_LOG")
ERRORS_5XX=$(awk -v f="$STATUS_FIELD" '$f ~ /^5[0-9]{2}$/ {c++} END {print c+0}' "$VALID_LOG")

# Percentages — use awk for float arithmetic
PCT_4XX=$(awk -v e="$ERRORS_4XX" -v t="$TOTAL_REQUESTS" \
    'BEGIN { if (t>0) printf "%.2f", (e/t)*100; else print "0.00" }')
PCT_5XX=$(awk -v e="$ERRORS_5XX" -v t="$TOTAL_REQUESTS" \
    'BEGIN { if (t>0) printf "%.2f", (e/t)*100; else print "0.00" }')

# ─── Top IPs ──────────────────────────────────────────────────────────────────

TOP_IPS=$(awk '{print $1}' "$VALID_LOG" \
    | sort \
    | uniq -c \
    | sort -rn \
    | head -"$TOP_N")

# ─── Top Endpoints ────────────────────────────────────────────────────────────
# Request field is typically field 7 in combined format: "METHOD /path HTTP/x.x"
# We extract just the path portion.

detect_request_field() {
    for field in 7 6; do
        count=$(awk -v f="$field" 'NR<=100 && $f ~ /^"?(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)/ {c++} END {print c+0}' "$VALID_LOG")
        if [[ $count -gt 5 ]]; then
            echo "$field"
            return
        fi
    done
    echo "7"
}
REQUEST_FIELD=$(detect_request_field)

TOP_ENDPOINTS=$(awk -v f="$REQUEST_FIELD" '{
    # Strip surrounding quotes from the request field
    gsub(/"/, "", $f)
    # Field f = "METHOD", f+1 = "/path", f+2 = "HTTP/x.x"
    # But $f might be "GET" and $(f+1) is the path if they were separate fields
    # Handle both quoted combined ("GET /path HTTP/1.1") and split cases
    if ($f ~ /^(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)$/) {
        path = $(f+1)
    } else {
        # The whole request is one quoted token — split it
        split($f, parts, " ")
        path = parts[2]
    }
    if (path != "" && path != "-") print path
}' "$VALID_LOG" \
    | sort \
    | uniq -c \
    | sort -rn \
    | head -"$TOP_N")

# ─── Status Code Breakdown ────────────────────────────────────────────────────

STATUS_BREAKDOWN=$(awk -v f="$STATUS_FIELD" '$f ~ /^[1-5][0-9]{2}$/ {codes[$f]++} END {
    for (code in codes) print codes[code], code
}' "$VALID_LOG" | sort -rn | head -10)

# ─── Output ───────────────────────────────────────────────────────────────────

echo
echo "╔══════════════════════════════════════════════════════════╗"
echo "║          Nginx Log Analysis Report                       ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo
echo "Log file     : $LOG_FILE"
echo "Analyzed at  : $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "Total lines  : $TOTAL_LINES (skipped $SKIPPED malformed)"
separator

printf "%-30s %s\n" "Total Requests:"     "$TOTAL_REQUESTS"
printf "%-30s %s\n" "Unique IPs:"         "$UNIQUE_IPS"
printf "%-30s %s (%s%%)\n" "4xx Errors:"  "$ERRORS_4XX" "$PCT_4XX"
printf "%-30s %s (%s%%)\n" "5xx Errors:"  "$ERRORS_5XX" "$PCT_5XX"
separator

echo
echo "Top ${TOP_N} IP Addresses:"
separator
printf "  %-5s %-20s %s\n" "Rank" "IP Address" "Requests"
printf "  %-5s %-20s %s\n" "────" "──────────" "────────"

rank=1
while IFS= read -r line; do
    count=$(echo "$line" | awk '{print $1}')
    ip=$(echo "$line" | awk '{print $2}')
    printf "  %-5s %-20s %s\n" "${rank}." "$ip" "$count"
    (( rank++ ))
done <<< "$TOP_IPS"

echo
echo "Top ${TOP_N} Endpoints:"
separator
printf "  %-5s %-45s %s\n" "Rank" "Endpoint" "Requests"
printf "  %-5s %-45s %s\n" "────" "────────" "────────"

rank=1
while IFS= read -r line; do
    count=$(echo "$line" | awk '{print $1}')
    path=$(echo "$line" | awk '{print $2}')
    printf "  %-5s %-45s %s\n" "${rank}." "$path" "$count"
    (( rank++ ))
done <<< "$TOP_ENDPOINTS"

echo
echo "HTTP Status Code Breakdown:"
separator
printf "  %-10s %s\n" "Status" "Count"
printf "  %-10s %s\n" "──────" "─────"

while IFS= read -r line; do
    count=$(echo "$line" | awk '{print $1}')
    code=$(echo "$line" | awk '{print $2}')
    printf "  %-10s %s\n" "$code" "$count"
done <<< "$STATUS_BREAKDOWN"

separator
echo "Analysis complete."
echo