#!/bin/bash

# Define the email address for notifications
EMAIL="your_email@example.com"

# Define the CSV file to store metrics
CSV_FILE="/home/kim/metrics.csv"

# Ensure the directory for the CSV file exists
mkdir -p "$(dirname "$CSV_FILE")"

# File to store the last run timestamp
LAST_RUN_FILE="/tmp/last_run_time"

# If the last run timestamp file does not exist, create it with the current time
if [ ! -f "$LAST_RUN_FILE" ]; then
    date +%s > "$LAST_RUN_FILE"
fi

# Get the last run timestamp
LAST_RUN_TIMESTAMP=$(cat "$LAST_RUN_FILE")

# Function to send email notification using msmtp
send_email() {
    SUBJECT="System Alert: High usage or issues detected"
    BODY="$1"
    echo -e "$BODY" | msmtp "$EMAIL"
}

# Collect system metrics
CPU_USAGE=$(mpstat 1 1 | grep "Average" | awk '{print 100 - $12}')
MEMORY_USAGE=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')

# System load (1, 5, 15 minute load averages)
SYSTEM_LOAD=$(uptime | awk -F'load average: ' '{ print $2 }')

# Firewall status check: Check if any rules exist in iptables
FIREWALL_STATUS=$(sudo iptables -L | grep -i "Chain" | wc -l)
if (( FIREWALL_STATUS > 0 )); then
    FIREWALL_STATUS="active"
else
    FIREWALL_STATUS="inactive"
fi

# Count failed login attempts (excluding SSH) since the last run
FAILED_LOGINS=$(sudo grep -i "Failed password" /var/log/auth.log | grep -v "sshd" | awk -v last_run="$LAST_RUN_TIMESTAMP" '$0 ~ last_run {print $0}' | wc -l)

# Count failed SSH login attempts since the last run
FAILED_SSH_LOGINS=$(sudo grep -i "Failed password" /var/log/auth.log | grep -i "sshd" | awk -v last_run="$LAST_RUN_TIMESTAMP" '$0 ~ last_run {print $0}' | wc -l)

# Network activity (bytes received and sent)
NET_STATS=$(cat /proc/net/dev | grep -i 'enp0s3' | awk '{print $2,$10}')

# Log the metrics to CSV file
echo "$(date),$CPU_USAGE,$MEMORY_USAGE,$DISK_USAGE,$SYSTEM_LOAD,$FIREWALL_STATUS,$FAILED_LOGINS,$FAILED_SSH_LOGINS,$NET_STATS" >> "$CSV_FILE"

# Display metrics in dialog box
dialog --title "System Metrics" --msgbox "CPU Usage: $CPU_USAGE%\nMemory Usage: $MEMORY_USAGE%\nDisk Usage: $DISK_USAGE%\nSystem Load (1, 5, 15 min): $SYSTEM_LOAD\nFirewall Status: $FIREWALL_STATUS\nFailed Logins: $FAILED_LOGINS\nFailed SSH Logins: $FAILED_SSH_LOGINS\nNetwork Activity (Received/Sent): $NET_STATS\nPress Ctrl+C to exit." 15 50

# Check if any metrics exceed thresholds and trigger email notifications
NOTIFY=""

if (( $(echo "$CPU_USAGE > 90" | bc -l) )); then
    NOTIFY="CPU usage is above 90%: $CPU_USAGE%"
fi

if (( $(echo "$MEMORY_USAGE > 90" | bc -l) )); then
    NOTIFY="Memory usage is above 90%: $MEMORY_USAGE%"
fi

if (( DISK_USAGE > 90 )); then
    NOTIFY="Disk usage is above 90%: $DISK_USAGE%"
fi

if [[ "$FIREWALL_STATUS" == "inactive" ]]; then
    NOTIFY="Firewall is inactive"
fi

if (( FAILED_LOGINS > 3 )); then
    NOTIFY="More than 3 failed login attempts: $FAILED_LOGINS"
fi

if (( FAILED_SSH_LOGINS > 3 )); then
    NOTIFY="More than 3 failed SSH login attempts: $FAILED_SSH_LOGINS"
fi

# If any condition triggered, send an email
if [[ -n "$NOTIFY" ]]; then
    send_email "$NOTIFY"
fi

# Weekly report generation
if [[ "$(date +%u)" -eq 7 ]]; then
    REPORT="Weekly System Report\n\nTop 10 Processes:\n$TOP_PROCESSES\n\nMetrics for the past week:\n$(cat "$CSV_FILE")"
    send_email "$REPORT"
fi

# Save the current timestamp as the last run time
date +%s > "$LAST_RUN_FILE"
