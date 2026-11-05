#!/bin/sh
# Order of the setgid and umask stripping on a filesystem without POSIX ACLs.
# The client is root and so keeps S_ISGID; root_squash makes the server a
# non-member of the directory's group, so the server decides.  Prints the modes
# for comparison between trees; only mode bits other than S_ISGID are judged.
set -u
uname -r
B=/run/nfsg
mkdir -p $B
mount -t tmpfs tmpfs $B
mkdir $B/srv $B/m
truncate -s 64M $B/img
mkfs.ext4 -q -F $B/img
mount -o loop,noacl $B/img $B/srv
grep " $B/srv " /proc/mounts
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
python3 -I $B/c.py $B/m 000 775
python3 -I $B/c.py $B/m 022 755
python3 -I $B/c.py $B/m 010 765
umount $B/m
