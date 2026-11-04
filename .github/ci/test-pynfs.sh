#!/bin/sh
# Run pynfs against nfsd on tmpfs.  This measures conformance; a failing test is
# a line of the table, not a broken build, so the lines say PYNFS and not FAIL.
set -u
uname -r
P=$PWD/.pynfs
[ -d "$P" ] || { echo "PYNFS: not fetched"; exit 0; }

B=/run/pynfs
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
rpc.nfsd 8

for v in 4.0 4.1; do
	cd $P/nfs$v || continue
	echo "PYNFS: start $v"
	timeout 1200 ./testserver.py 127.0.0.1:/srv --maketree --rundeps all \
	    --json=/tmp/pynfs-$v.json > /tmp/pynfs-$v.txt 2>&1
	echo "PYNFS: rc $v $?"
	tail -5 /tmp/pynfs-$v.txt | sed 's/^/PYNFS: /'
	grep -E ': (FAILURE|WARNING)' /tmp/pynfs-$v.txt | sed "s/^/PYNFS $v: /"
done
exit 0
