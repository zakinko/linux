#!/bin/sh
# NFSv4.2 re-export: a file created through the re-exporting server must get
# the same mode as one created directly, with or without a default ACL on the
# directory underneath.
set -u
uname -r

B=/run/nfst
mkdir -p $B
mount -t tmpfs tmpfs $B
mkdir $B/srv $B/a $B/b
mount -t tmpfs -o mode=0777 tmpfs $B/srv
mkdir -m 0777 $B/srv/acl $B/srv/plain
setfacl -d -m u::rwx,g::rwx,o::rwx $B/srv/acl

mount -t tmpfs tmpfs /var/lib/nfs
mkdir -p /var/lib/nfs/rpc_pipefs /var/lib/nfs/v4recovery
mount -t rpc_pipefs sunrpc /var/lib/nfs/rpc_pipefs
mount -t nfsd nfsd /proc/fs/nfsd
rpcbind -w 2>/dev/null || true

opts=rw,sync,no_root_squash,no_subtree_check
exportfs -o $opts,fsid=1 127.0.0.1:$B/srv
rpc.mountd
rpc.nfsd 4
mount -t nfs -o vers=4.2 127.0.0.1:$B/srv $B/a || { echo "FAIL: mount a"; exit 1; }
exportfs -o $opts,fsid=2 127.0.0.1:$B/a
mount -t nfs -o vers=4.2 127.0.0.1:$B/a $B/b || { echo "FAIL: mount b"; exit 1; }

check() {
	path=$1 kind=$2 want=$3
	if [ $kind = file ]; then
		(umask 077; : > $path)
	else
		(umask 077; mkdir $path)
	fi
	got=$(stat -c %a $B/srv/${path#$B/?/})
	if [ "$got" = "$want" ]; then
		echo "PASS: $path $kind mode $got"
	else
		echo "FAIL: $path $kind mode $got, want $want"
	fi
}

for via in a b; do
	check $B/$via/acl/f.$via file 666
	check $B/$via/acl/d.$via dir 777
	check $B/$via/plain/f.$via file 600
	check $B/$via/plain/d.$via dir 700
done

umount $B/b
umount $B/a
