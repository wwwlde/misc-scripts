#!/bin/bash

# This bash script is designed for memory analysis of a specific process identified by its PID (Process ID).
# This script takes a process PID as an argument, extracts the memory ranges with read-write permissions from the /proc/$1/maps 
# file, and then uses gdb to dump the memory content of those ranges into individual dump files. This can be useful for memory 
# analysis and debugging purposes. However, it should be used with caution, as debugging and memory analysis of running processes 
# can have potential security and stability implications.

if [ -z "$1" ]; then
    echo "You should provide process PID as the first argument"
fi

grep rw-p /proc/"$1"/maps |
    sed -n 's/^\([0-9a-f]*\)-\([0-9a-f]*\) .*$/\1 \2/p' |
    while read -r start stop; do
        gdb --batch --pid "$1" -ex \
            "dump memory $1-$start-$stop.dump 0x$start 0x$stop"
    done
