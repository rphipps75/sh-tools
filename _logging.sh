# _logging.sh - Logging utility functions (sourced, not executed directly)
#
# Output:
#   2025-06-01 08:42:59.786 (UTC) [INFO] hello world
#
# Output (LOGGING_USE_EMOJI=true):
#   2025-06-01 08:42:59.786 (UTC) [INFO] ℹ️ hello world
#
# Output (LOGGING_USE_TYPE_PREFIX=false):
#   2025-06-01 08:42:59.786 (UTC) hello world
#
# Output (LOGGING_USE_TYPE_PREFIX=false, LOGGING_USE_EMOJI=true):
#   2025-06-01 08:42:59.786 (UTC) ℹ️ hello world

# Define colour codes
LOGGING_COLOUR_RESET="\033[0m"              # Reset to default colour
LOGGING_COLOUR_ORANGE="\033[33m"            # Orange (for [WARN])
LOGGING_COLOUR_YELLOW="\033[93m"            # Yellow
LOGGING_COLOUR_RED="\033[31m"               # Red (for [ERROR])
LOGGING_COLOUR_GREEN="\033[32m"             # Green
LOGGING_COLOUR_BLUE="\033[34m"              # Blue (for [INFO])
LOGGING_COLOUR_CYAN="\033[0;36m"            # Cyan
LOGGING_COLOUR_WHITE_ON_RED="\033[37;41m"   # White text on red background (for [FAIL])

LOGGING_USE_TYPE_PREFIX="${LOGGING_USE_TYPE_PREFIX:-true}"
LOGGING_USE_EMOJI="${LOGGING_USE_EMOJI:-false}"
LOGGING_EMOJI_WARN="⚠️"
LOGGING_EMOJI_ERROR="❌"
LOGGING_EMOJI_FAIL="💥"
LOGGING_EMOJI_SUCCESS="✅"
LOGGING_EMOJI_INFO="ℹ️"
LOGGING_EMOJI_DEBUG="🔧"
LOGGING_EMOJI_TRACE="🔍"

# Set default log level if not already set:
# 0=TRACE, 1=DEBUG, 2=INFO, 3=WARN, 4=ERROR, 5=FAIL, 6=OFF
LOGGING_LEVEL="${LOGGING_LEVEL:-2}"

# Outputs the current UTC timestamp in format: YYYY-MM-DD HH:MM:SS.mmm (UTC)
# Suffixes a trailing space
# Usage: $(_log_date)
_log_date () {
  if [ -n "${EPOCHREALTIME}" ]; then
    printf "%(%%Y-%%m-%%d %%H:%%M:%%S)T.%s (UTC) " -1 "${EPOCHREALTIME#*.00}" | cut -c1-29
  else
    # Better macOS compatibility gate check
    if date +%N | grep -q 'N'; then
      # macOS BSD date fallback - strip out the unparseable %3N token cleanly
      date -u +"%Y-%m-%d %H:%M:%S (UTC) "
    else
      date -u +"%Y-%m-%d %H:%M:%S.%3N (%Z) "
    fi
  fi
}

# Outputs the coloured [TYPE] label based on log level
# Suffixes a trailing space. Returns nothing if LOGGING_USE_TYPE_PREFIX is not "true"
# Usage: $(_log_type "INFO")
_log_type () {
  if [ "$LOGGING_USE_TYPE_PREFIX" != "true" ]; then return; fi
  case "$1" in
    WARN)    printf '%b ' "${LOGGING_COLOUR_ORANGE}[WARN]${LOGGING_COLOUR_RESET}" ;;
    ERROR)   printf '%b ' "${LOGGING_COLOUR_RED}[ERROR]${LOGGING_COLOUR_RESET}" ;;
    FAIL)    printf '%b ' "${LOGGING_COLOUR_WHITE_ON_RED}[FAIL]${LOGGING_COLOUR_RESET}" ;;
    SUCCESS) printf '%b ' "${LOGGING_COLOUR_GREEN}[SUCCESS]${LOGGING_COLOUR_RESET}" ;;
    INFO)    printf '%b ' "${LOGGING_COLOUR_BLUE}[INFO]${LOGGING_COLOUR_RESET}" ;;
    DEBUG)   printf '%b ' "${LOGGING_COLOUR_CYAN}[DEBUG]${LOGGING_COLOUR_RESET}" ;;
    TRACE)   printf '%b ' "${LOGGING_COLOUR_GREEN}[TRACE]${LOGGING_COLOUR_RESET}" ;;
  esac
}

# Outputs the emoji for a given log level with a trailing space
# Returns nothing if LOGGING_USE_EMOJI is not "true"
# Usage: $(_log_emoji "INFO")
_log_emoji () {
  if [ "$LOGGING_USE_EMOJI" != "true" ]; then return; fi
  case "$1" in
    WARN)    printf '%s ' "$LOGGING_EMOJI_WARN" ;;
    ERROR)   printf '%s ' "$LOGGING_EMOJI_ERROR" ;;
    FAIL)    printf '%s ' "$LOGGING_EMOJI_FAIL" ;;
    SUCCESS) printf '%s ' "$LOGGING_EMOJI_SUCCESS" ;;
    INFO)    printf '%s ' "$LOGGING_EMOJI_INFO" ;;
    DEBUG)   printf '%s ' "$LOGGING_EMOJI_DEBUG" ;;
    TRACE)   printf '%s ' "$LOGGING_EMOJI_TRACE" ;;
  esac
}

# Formats and prints a complete log line: date + type + emoji + message
# Usage: _log "INFO" "message text"
_log () {
  local level_name="$1"
  local message="$2"
  local level_value=2 # Default to INFO numeric value

  case "$level_name" in
    TRACE)   level_value=0 ;;
    DEBUG)   level_value=1 ;;
    INFO)    level_value=2 ;;
    WARN)    level_value=3 ;;
    ERROR)   level_value=4 ;;
    FAIL)    level_value=5 ;;
  esac

  # Drop the log if it doesn't meet the threshold
  if [ "$level_value" -lt "$LOGGING_LEVEL" ]; then
    return 0
  fi

  # %b so colour tokens inside the message variable render correctly
  printf '%b%b\n' "$(_log_date)$(_log_type "$level_name")$(_log_emoji "$level_name")" "$message"
}

log_info ()    { _log "INFO" "$1"; }
log_warn ()    { _log "WARN" "$1"; }
log_error ()   { _log "ERROR" "$1"; }
log_fail ()    { _log "FAIL" "$1"; }
log_debug ()   { _log "DEBUG" "$1"; }
log_success () { _log "SUCCESS" "$1"; }
log_trace ()   { _log "TRACE" "$1"; }

log_debug_cat () {
  local filepath="$1"
  if [ ! -f "$filepath" ]; then
    log_error "File ($filepath) does not exist or is not a regular file"
    return 1
  fi
  if [ ! -r "$filepath" ]; then
    log_error "Permission denied: Cannot read ($filepath)"
    return 1
  fi
  local filename
  filename=$(basename "$filepath")
  log_debug "$filename"
  cat "$filepath"
}

log_summary_header () {
  echo " "
  echo "============================================================"
  echo "# $1"
  echo "============================================================"
}
log_summary_footer () {
  echo "============================================================"
  echo " "
}
log_summary_kvp () {
  echo "# $1: $2"
}
log_summary_item () {
  echo "# $1"
}

log_sep () {
  echo "------------------------------------------------------------"
}
log_blank () {
  echo " "
}
