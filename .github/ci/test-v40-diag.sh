#!/bin/sh
# Why a v4.0 lower mount fails to re-export, with v4.1 as the control.
set -u
uname -r
B=/run/d4
mkdir -p $B
mount -t tmpfs -o mode=0777 tmpfs $B
mkdir $B/p
mount -t tmpfs -o mode=0777 tmpfs $B/p
mkdir -m 777 $B/p/sub
: > $B/p/sub/file
mount -t tmpfs tmpfs /var/lib/nfs
mkdir -p /var/lib/nfs/rpc_pipefs /var/lib/nfs/v4recovery
touch /var/lib/nfs/etab /var/lib/nfs/rmtab
mount -t rpc_pipefs sunrpc /var/lib/nfs/rpc_pipefs
mount -t nfsd nfsd /proc/fs/nfsd
rpcbind -w 2>/dev/null || true
opts=rw,sync,no_root_squash,insecure,no_subtree_check
exportfs -o $opts,fsid=0,crossmnt 127.0.0.1:$B
exportfs -o $opts,fsid=1 127.0.0.1:$B/p
rpc.mountd
echo 10 > /proc/fs/nfsd/nfsv4leasetime
echo 10 > /proc/fs/nfsd/nfsv4gracetime
rpc.nfsd 8
sleep 15
echo 1 > /sys/kernel/tracing/events/nfsd/nfsd_fh_verify_err/enable 2>/dev/null
echo 1 > /sys/kernel/tracing/events/nfsd/nfsd_compound_status/enable 2>/dev/null

f=20
for l in 4.1 4.0; do
	lo=$B/lo$l; up=$B/up$l; f=$((f + 1))
	mkdir $lo $up
	mount -t nfs -v -o vers=$l,nolock,actimeo=0 127.0.0.1:/p $lo 2>&1 | sed "s/^/DIAG $l lower: /"
	echo "DIAG $l: lower rc=$? ls: $(ls -la $lo/sub 2>&1 | tr '\n' ' ')"
	exportfs -o $opts,fsid=$f,crossmnt 127.0.0.1:$lo 2>&1 | sed "s/^/DIAG $l export: /"
	echo > /sys/kernel/tracing/trace
	mount -t nfs -v -o vers=4.2,nolock,actimeo=0 127.0.0.1:${lo#$B} $up 2>&1 | sed "s/^/DIAG $l upper42: /"
	echo "DIAG $l: ls up: $(ls -la $up 2>&1 | tr '\n' ' ')"
	echo "DIAG $l: ls up/sub: $(ls -la $up/sub 2>&1 | tr '\n' ' ')"
	touch $up/sub/new 2>&1 | sed "s/^/DIAG $l touch: /"
	stat -c '%a %i' $up/sub/file 2>&1 | sed "s/^/DIAG $l stat: /"
	grep -v '^#' /sys/kernel/tracing/trace | grep -v 'status=0\|error=0' | tail -12 | cut -c1-140 | sed "s/^/DIAG $l trace: /"
	mount -t nfs -v -o vers=3,nolock,actimeo=0 127.0.0.1:$lo $up 2>&1 | sed "s/^/DIAG $l upper3: /"
	umount $up 2>/dev/null
done
grep ' nfs' /proc/mounts | cut -c1-140 | sed 's/^/DIAG mounts: /'
exportfs -v 2>&1 | sed 's/^/DIAG exports: /'
dmesg | tail -15 | cut -c1-140 | sed 's/^/DIAG dmesg: /'
echo "PASS: diag"
