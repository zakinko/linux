#!/bin/sh
# mode_umask against RFC 8275, by pynfs over NFSv4.2.  The lines are UMASKRFC so
# that trees can be compared; PASS only says that the run finished.
set -u
uname -r
P=$PWD/.pynfs
[ -d "$P" ] || { echo "FAIL: pynfs not fetched"; exit 1; }
B=/run/pynfsu
mkdir -p $B
mount -t tmpfs tmpfs $B
mkdir $B/srv
chmod 777 $B/srv
mount -t tmpfs tmpfs /var/lib/nfs
mkdir -p /var/lib/nfs/rpc_pipefs /var/lib/nfs/v4recovery
touch /var/lib/nfs/etab /var/lib/nfs/rmtab
mount -t rpc_pipefs sunrpc /var/lib/nfs/rpc_pipefs
mount -t nfsd nfsd /proc/fs/nfsd
rpcbind -w 2>/dev/null || true
opts=rw,sync,no_root_squash,insecure,no_subtree_check
exportfs -o $opts,fsid=0,crossmnt 127.0.0.1:$B
exportfs -o $opts,fsid=1 127.0.0.1:$B/srv
rpc.mountd
echo 10 > /proc/fs/nfsd/nfsv4leasetime
echo 10 > /proc/fs/nfsd/nfsv4gracetime
rpc.nfsd 8
sleep 15
cd $P/nfs4.1
timeout 300 ./testserver.py 127.0.0.1:/srv --minorversion 2 --maketree \
    umask > $B/out 2>&1
echo "UMASKRFC: rc $?"
cut -c1-170 $B/out | tail -60 | sed 's/^/UMASKRFC: /'
dmesg | grep -E 'WARNING|BUG:' | sed 's/^/UMASKRFC dmesg: /'
grep -q "0 Failed" $B/out || { echo "FAIL: umask rfc"; exit 1; }
echo "PASS: all mode_umask tests"
