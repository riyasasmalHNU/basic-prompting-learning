#!/bin/bash
# vm_health_check.sh
# Analyses the health of an Ubuntu virtual machine based on CPU, memory, and disk usage.
# Usage: ./vm_health_check.sh [Explain]
#   Explain  - optional argument (case-insensitive); when provided, prints the reason
#              for the health status along with the current utilization values.

THRESHOLD=60

# ---------- Gather metrics ----------

# CPU usage: extract the idle percentage from `top` using pattern matching on the
# field that contains "id" so the result is independent of field position.
CPU_IDLE=$(top -bn1 | grep -i "cpu" \
    | awk -F',' '{for(i=1;i<=NF;i++) if($i ~ /id/) {gsub(/[^0-9.]/, "", $i); print $i; exit}}')
if [ -z "$CPU_IDLE" ]; then
    echo "Warning: Could not determine CPU idle percentage; defaulting to 0." >&2
    CPU_IDLE=0
fi
CPU_USAGE=$(awk "BEGIN {printf \"%.1f\", 100 - ${CPU_IDLE}}")

# Memory usage: percentage of used memory relative to total memory
MEM_INFO=$(free | grep Mem)
MEM_TOTAL=$(echo "$MEM_INFO" | awk '{print $2}')
MEM_USED=$(echo "$MEM_INFO"  | awk '{print $3}')
if [ -z "$MEM_TOTAL" ] || [ "$MEM_TOTAL" -eq 0 ] 2>/dev/null; then
    echo "Warning: Could not determine memory usage; defaulting to 0." >&2
    MEM_USAGE=0
else
    MEM_USAGE=$(awk "BEGIN {printf \"%.1f\", ($MEM_USED/$MEM_TOTAL)*100}")
fi

# Disk usage: highest usage percentage across all local filesystems
DISK_USAGE=$(df -l --output=pcent 2>/dev/null | grep -v 'Use%' | tr -d '% ' | sort -n | tail -1)
# Fallback for systems where --output is unsupported
if [ -z "$DISK_USAGE" ]; then
    DISK_USAGE=$(df -l | grep -v 'Filesystem' | awk '{gsub(/%/,""); print $5}' | sort -n | tail -1)
fi
if [ -z "$DISK_USAGE" ]; then
    echo "Warning: Could not determine disk usage; defaulting to 0." >&2
    DISK_USAGE=0
fi

# ---------- Evaluate health ----------

IS_HEALTHY=true
REASONS=""

# Helper: returns true (exit 0) when the value exceeds the threshold
exceeds_threshold() {
    awk -v val="$1" -v thresh="$THRESHOLD" 'BEGIN { exit (val > thresh) ? 0 : 1 }'
}

if exceeds_threshold "$CPU_USAGE"; then
    IS_HEALTHY=false
    REASONS="${REASONS}  - CPU usage is ${CPU_USAGE}% (threshold: ${THRESHOLD}%)\n"
fi

if exceeds_threshold "$MEM_USAGE"; then
    IS_HEALTHY=false
    REASONS="${REASONS}  - Memory usage is ${MEM_USAGE}% (threshold: ${THRESHOLD}%)\n"
fi

if exceeds_threshold "$DISK_USAGE"; then
    IS_HEALTHY=false
    REASONS="${REASONS}  - Disk usage is ${DISK_USAGE}% (threshold: ${THRESHOLD}%)\n"
fi

# ---------- Report ----------

# Accept "Explain" in any capitalisation (e.g. explain / EXPLAIN / Explain)
EXPLAIN_ARG=$(echo "$1" | tr '[:upper:]' '[:lower:]')

if $IS_HEALTHY; then
    echo "VM Health Status: Healthy"
    if [ "$EXPLAIN_ARG" = "explain" ]; then
        echo ""
        echo "Reason: All resource utilization levels are within the acceptable limit (below ${THRESHOLD}%)."
        echo "  - CPU usage   : ${CPU_USAGE}%"
        echo "  - Memory usage: ${MEM_USAGE}%"
        echo "  - Disk usage  : ${DISK_USAGE}%"
    fi
else
    echo "VM Health Status: Not Healthy"
    if [ "$EXPLAIN_ARG" = "explain" ]; then
        echo ""
        echo "Reason: One or more resources have exceeded the ${THRESHOLD}% utilization threshold:"
        echo -e "$REASONS"
        echo "Current utilization:"
        echo "  - CPU usage   : ${CPU_USAGE}%"
        echo "  - Memory usage: ${MEM_USAGE}%"
        echo "  - Disk usage  : ${DISK_USAGE}%"
    fi
fi
