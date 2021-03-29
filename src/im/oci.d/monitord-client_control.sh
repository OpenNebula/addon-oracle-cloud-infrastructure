#!/bin/bash

#--------------------------------------------------------------------------- #
# Process Arguments
#--------------------------------------------------------------------------- #
ACTION="start"

if [ "$1" = "stop" ]; then
    shift
    ACTION="stop"
fi

ARGV=$*

HID=$2

STDIN=`cat -`

# Directory that contains this file
DIR=$(pwd)

# Basename
BASENAME=$(basename $0 _control.sh)

# Collectd client (Ruby)
CLIENT=$DIR/${BASENAME}.rb

# Collectd client PID
CLIENT_PID_FILE=/tmp/one-monitord-$HID.pid

# Launch the client
function start_client() {
    rm $CLIENT_PID_FILE >/dev/null 2>&1

    echo "$STDIN" | /usr/bin/env ruby $CLIENT $ARGV 2> /tmp/one-monitord-$HID.error &
    CLIENT_PID=$!

    sleep 1

    if [ -z "$CLIENT_PID" ] || ! ps -p $CLIENT_PID > /dev/null; then
        cat /tmp/one-monitord-$HID.error
        exit 1
   fi

   echo $CLIENT_PID > $CLIENT_PID_FILE
}

# Stop the client
function stop_client() {
    local pids=$(ps axuww | grep "$CLIENT $ARGV" | grep -v grep | awk '{print $2}')

    if [ -n "$pids" ]; then
        kill -9 $pids
        sleep 5
    fi

    rm -f $CLIENT_PID_FILE
}

case $ACTION in
start)
    stop_client
    start_client
    ;;

stop)
    stop_client
    ;;
esac
