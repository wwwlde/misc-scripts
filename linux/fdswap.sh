#!/bin/bash

#
# fdswap.sh
#
# In summary, this script is designed to redirect the file descriptors of one or more running processes specified by their PIDs from a source file (src) 
# to a destination file (dst) using the GNU Debugger (gdb). This could be useful for tasks like log file rotation or other situations where you need to 
# switch a process from writing to one file to another without stopping the process itself.
#
# https://www.redpill-linpro.com/sysadvent/2015/12/04/changing-a-process-file-descriptor-with-gdb.html
#

if [ "$2" = "" ]; then
    echo "
    Usage: $0 /path/to/oldfile /path/to/newfile [pids]
    Example: $0 /var/log/daemon.log /var/log/newvolume/daemon.log 1234
    Example: $0 /dev/pts/53 /dev/null 2345"
    exit 0
fi

if gdb --version >/dev/null 2>&1; then
    true
else
    echo "Unable to find gdb."
    exit 1
fi

src="$1"
dst="$2"
shift
shift
pids=$*

for pid in ${pids:=$(/sbin/fuser $src | cut -d ':' -f 2)}; do
    echo "src=$src, dst=$dst"
    echo "$src has $pid using it"
    (
        echo "attach $pid"
        echo 'call open("'$dst'", 66, 0666)'
        for ufd in $(LANG=C ls -l /proc/$pid/fd |
            grep "$src"\$ | awk ' { print $9; } '); do echo 'call dup2($1,'"$ufd"')'; done
        echo 'call close($1)'
        echo 'detach'
        echo 'quit'
        sleep 5
    ) | gdb -q -x -
done
