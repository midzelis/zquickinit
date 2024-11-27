#!/bin/bash
source /zquick/libexec/utils.sh

# Website to check for connectivity
WEBSITE="https://connectivitycheck.gstatic.com"
# Interval between checks (in seconds)
INTERVAL=60
# Minimum wait time before restarting (in seconds)
MIN_WAIT_TIME=3600

# Function to check connectivity
check_connectivity() {
    curl --silent --output /dev/null --write-out "%{http_code}" $WEBSITE
    return $?
}

# Function to restart the computer
restart_computer() {
    qinitlog "Network is down. Restarting the computer..."
    reboot
}

# Record the start time
start_time=$(date +%s)

# Run the script in the background
while true; do
    if ! check_connectivity; then
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))

        if [ $elapsed_time -ge $MIN_WAIT_TIME ]; then
            restart_computer
        else
            qinitlog "Network is down, but waiting for the minimum wait time before restarting..."
        fi
    else
        # Reset the start time if the network is up
        start_time=$(date +%s)
    fi

    sleep $INTERVAL
done
