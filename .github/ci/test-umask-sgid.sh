#!/bin/sh
# Order of the setgid and umask stripping on tmpfs built without POSIX ACLs.
# The client is root and so keeps S_ISGID; root_squash makes the server a
# non-member of the directory's group, so the server decides.  Prints the modes
# for comparison between trees; only mode bits other than S_ISGID are judged.
set -u
uname -r
B=/run/nfsg
mkdir -p $B
mount -t tmpfs tmpfs $B
mkdir $B/srv $B/m
mount -t tmpfs -o mode=0777 tmpfs $B/srv
grep "POSIX_ACL" /proc/config.gz 2>/dev/null
chgrp 2000 $B/srv
chmod 2777 $B/srv

mount -t tmpfs tmpfs /var/lib/nfs
mkdir -p /var/lib/nfs/rpc_pipefs /var/lib/nfs/v4recovery
touch /var/lib/nfs/etab /var/lib/nfs/rmtab
mount -t rpc_pipefs sunrpc /var/lib/nfs/rpc_pipefs
mount -t nfsd nfsd /proc/fs/nfsd
rpcbind -w 2>/dev/null || true
exportfs -o rw,sync,root_squash,no_subtree_check,fsid=0 127.0.0.1:$B/srv
rpc.mountd
rpc.nfsd 4
mount -t nfs -o vers=4.2,nolock 127.0.0.1:/ $B/m || { echo "FAIL: mount"; exit 1; }

cat > $B/c.py <<'P'
import os, sys
d, um, want = sys.argv[1], int(sys.argv[2], 8), int(sys.argv[3], 8)
os.umask(um)
n = "%s/f.%03o" % (d, um)
os.close(os.open(n, os.O_CREAT | os.O_WRONLY, 0o2775))
got = os.stat(n.replace("/m/", "/srv/")).st_mode & 0o7777
print("MEASURE: umask %03o mode %04o" % (um, got))
print("%s: umask %03o perm %03o, want %03o" %
      ("PASS" if got & 0o777 == want else "FAIL", um, got & 0o777, want))
P
T=/sys/kernel/tracing
mount -t tracefs nodev $T 2>/dev/null
echo 'p:vc vfs_create mode=%dx:x32' > $T/kprobe_events
echo 'p:ec shmem_create mode=%cx:x32' >> $T/kprobe_events
echo 1 > $T/events/kprobes/enable
mkdir $B/srv/nog; chmod 0777 $B/srv/nog
tcpdump -q -i lo -s0 -w $B/p.cap port 2049 2>/dev/null &
TD=$!
sleep 1
python3 -I $B/c.py $B/m 000 775
python3 -I $B/c.py $B/m 022 755
python3 -I $B/c.py $B/m 010 765
python3 -I $B/c.py $B/m/nog 000 775
python3 -I $B/c.py $B/m/nog 010 765
echo 0 > $T/events/kprobes/enable
grep -E 'vc:|ec:' $T/trace | sed 's/^/TRACE: /'
sleep 1
kill $TD; sleep 1
tshark -r $B/p.cap -Y 'nfs' -T fields -e frame.number -e nfs.main_opcode -e nfs.opcode -e nfs.name -e nfs.mode3 -e nfs.attr 2>/dev/null | sed 's/^/WIRE: /' | head -60
tshark -r $B/p.cap -d tcp.port==2049,rpc -Y 'nfs.opcode == 18 || nfs.main_opcode == 18' -V 2>/dev/null | grep -E '^Frame |Status: |umask: |mode: 0|Name: f\.' | cut -c1-70 | sed 's/^/WIRE2: /' | head -260
umount $B/m
