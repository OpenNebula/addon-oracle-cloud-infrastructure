#!/bin/bash

HID=$2
HNAME=$3

STDIN=`cat -`

CLIENT_PID_FILE=/tmp/one-monitord-$HID.pid

(
[ -f $CLIENT_PID_FILE ] || exit 0

running_pid=$(cat $CLIENT_PID_FILE)
pids=$(ps axuwww | grep "/monitord-client.rb [^\s]* ${HID} ${HNAME}" | grep -v grep | \
    awk '{ print $2 }' | grep -v "^${running_pid}$")

if [ -n "$pids" ]; then
    kill $pids
fi

oned=`ps auxwww | grep oned | grep -v grep | wc -l`

if [ ${oned} -eq 0 ]; then
    kill ${running_pid}
fi

) > /dev/null

