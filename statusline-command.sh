#!/bin/bash
# Claude Code Statusline
# Segments: 🧬 Model | 💰 Session | 📊 Usage | 🧠 Context
#
# Install:
#   cp statusline.sh ~/.claude/statusline.sh && chmod +x ~/.claude/statusline.sh
#
# ~/.claude/settings.json:
#   { "statusLine": { "type": "command", "command": "~/.claude/statusline.sh", "padding": 0 } }
#
# Requires: jq

# ── ANSI ──────────────────────────────────────────────────────────────────────
R='\033[0m'
BOLD='\033[1m'

# Gruvbox dark palette (fg only, on terminal's native dark bg)
# bg0_h=#1d2021(232) bg0=#282828(235) bg1=#3c3836(237)
# fg=214(orange) fg=108(aqua) fg=142(yellow-green)
# fg=167(red) fg=175(purple) fg=246(gray)
# C_MODEL='[48;5;237m[38;5;108m'    # gruvbox bg1 + aqua
# C_SESSION='[48;5;237m[38;5;214m'  # gruvbox bg1 + orange
# C_USAGE='[48;5;237m[38;5;142m'    # gruvbox bg1 + yellow-green
# C_CONTEXT_OK='[48;5;235m[38;5;246m'   # gruvbox bg0 + gray    (< 70%)
# C_CONTEXT_WARN='[48;5;235m[38;5;214m' # gruvbox bg0 + orange  (70-89%)
# C_CONTEXT_HOT='[48;5;235m[38;5;167m'  # gruvbox bg0 + red     (≥ 90%)

SEP=' │ '

# ── Parse JSON input ──────────────────────────────────────────────────────────
input=$(cat)

MODEL=$(echo "$input"        | jq -r '.model.display_name                                              // "Claude"')
CTX_PCT=$(echo "$input"      | jq -r '.context_window.used_percentage                                // 0')
CTX_SIZE=$(echo "$input"     | jq -r '.context_window.context_window_size                           // 200000')
CACHE_READ=$(echo "$input"   | jq -r '.context_window.current_usage.cache_read_input_tokens         // 0')
CACHE_CREATE=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens     // 0')
INPUT_TOK=$(echo "$input"    | jq -r '.context_window.current_usage.input_tokens                    // 0')
COST=$(echo "$input"         | jq -r '.cost.total_cost_usd                                          // 0')
DURATION=$(echo "$input"     | jq -r '.cost.total_duration_ms                                       // 0')
LINES_ADD=$(echo "$input"    | jq -r '.cost.total_lines_added                                       // 0')
LINES_REM=$(echo "$input"    | jq -r '.cost.total_lines_removed                                     // 0')

# ── Helpers ───────────────────────────────────────────────────────────────────

fmt_cost() {
    local c=$1
    if awk "BEGIN{exit !($c > 0)}" 2>/dev/null; then
        env LC_ALL=C printf '$%.3f' "$c"   # locale-independent decimal point
    else
        # Literal dollar sign.
        # shellcheck disable=SC2016
        printf '$0'
    fi
}

fmt_duration() {
    local ms=$1
    if awk "BEGIN{exit !($ms >= 60000)}" 2>/dev/null; then
        printf '%dm%ds' "$(( ms / 60000 ))" "$(( (ms % 60000) / 1000 ))"
    else
        printf '%ds' "$(( ms / 1000 ))"
    fi
}

ctx_bar() {
    local pct=${1%.*}; pct=${pct:-0}
    local filled=$(( pct / 10 ))
    local bar=""
    for (( i=0; i<10; i++ )); do
        (( i < filled )) && bar="${bar}▓" || bar="${bar}░"
    done
    printf '%s' "$bar"
}

ctx_color() {
    local pct=$1
    if   awk "BEGIN{exit !($pct >= 90)}" 2>/dev/null; then printf '%s' "$C_CONTEXT_HOT"
    elif awk "BEGIN{exit !($pct >= 70)}" 2>/dev/null; then printf '%s' "$C_CONTEXT_WARN"
    else printf '%s' "$C_CONTEXT_OK"
    fi
}

# ── 🧬 Model ──────────────────────────────────────────────────────────────────
seg_model="${C_MODEL}${BOLD} 🧬 ${MODEL} ${R}"

# ── 💰 Session ────────────────────────────────────────────────────────────────
COST_FMT=$(fmt_cost "$COST")
DUR_FMT=$(fmt_duration "$DURATION")
seg_session="${C_SESSION}${BOLD} 💰 ${COST_FMT} ${DUR_FMT} ${R}"

# ── 📊 Usage ─────────────────────────────────────────────────────────────────
if (( LINES_ADD > 0 || LINES_REM > 0 )); then
    USAGE_STR="+${LINES_ADD}/-${LINES_REM}"
else
    USAGE_STR="no changes"
fi
seg_usage="${C_USAGE}${BOLD} 📊 ${USAGE_STR} ${R}"

# ── 🧠 Context ────────────────────────────────────────────────────────────────
CTX_INT=${CTX_PCT%.*}; CTX_INT=${CTX_INT:-0}
BAR=$(ctx_bar "$CTX_INT")
CTX_COL=$(ctx_color "$CTX_PCT")

# Cache hit rate
TOTAL_INPUT=$(( INPUT_TOK + CACHE_READ + CACHE_CREATE ))
if (( TOTAL_INPUT > 0 && CACHE_READ > 0 )); then
    CACHE_PCT=$(awk "BEGIN{printf \"%.0f\", ($CACHE_READ / $TOTAL_INPUT) * 100}")
    CACHE_STR=" 🏺${CACHE_PCT}%"
else
    CACHE_STR=""
fi

(( CTX_SIZE > 500000 )) && CTX_LABEL="1M" || CTX_LABEL="200k"

CTX_INFO="${CTX_INT}%/${CTX_LABEL}${CACHE_STR}"
seg_context="${CTX_COL}${BOLD} 🧠 ${BAR} ${CTX_INFO} ${R}"

# ── Output ────────────────────────────────────────────────────────────────────
printf '%b\n' "${seg_model}${SEP}${seg_session}${SEP}${seg_usage}${SEP}${seg_context}"
