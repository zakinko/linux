#!/bin/sh
# overlayfs exported by nfsd, with and without a default ACL.
set -u
uname -r
B=/run/nfso
mkdir -p $B
mount -t tmpfs tmpfs $B
mkdir $B/l $B/u $B/w $B/o $B/m
mount -t overlay overlay -o lowerdir=$B/l,upperdir=$B/u,workdir=$B/w,index=on,nfs_export=on $B/o || { echo "FAIL: overlay"; exit 1; }
mkdir -m 0777 $B/o/acl $B/o/plain
setfacl -d -m u::rwx,g::rwx,o::rwx $B/o/acl
mount -t tmpfs tmpfs /var/lib/nfs
mkdir -p /var/lib/nfs/rpc_pipefs /var/lib/nfs/v4recovery
touch /var/lib/nfs/etab /var/lib/nfs/rmtab
mount -t rpc_pipefs sunrpc /var/lib/nfs/rpc_pipefs
mount -t nfsd nfsd /proc/fs/nfsd
rpcbind -w 2>/dev/null || true
exportfs -o rw,sync,no_root_squash,no_subtree_check,fsid=0 127.0.0.1:$B/o
rpc.mountd
rpc.nfsd 4
mount -t nfs -o vers=4.2,nolock 127.0.0.1:/ $B/m || { echo "FAIL: mount"; exit 1; }
c() { (umask 077; : > $B/m/$1/f; mkdir $B/m/$1/d); g=$(stat -c %a $B/o/$1/f); h=$(stat -c %a $B/o/$1/d)
  if [ "$g $h" = "$2" ]; then echo "PASS: overlay $1 $g $h"; else echo "FAIL: overlay $1 $g $h, want $2"; fi; }
c acl "666 777"
c plain "600 700"
umount $B/m
