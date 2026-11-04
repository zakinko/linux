#!/bin/sh
# NFSv4.2 re-export with idmapping: the server names 1234 alice@test, and the
# client has no way to turn that into an id (rpc.idmapd -S serves only the
# server, and there is no nfsidmap).  The re-exporting server must hand the name
# on as it came.
set -u
uname -r

B=/run/nfsi
mkdir -p $B
mount -t tmpfs tmpfs $B
mkdir $B/srv $B/a $B/b
mount -t tmpfs -o mode=0777 tmpfs $B/srv
: > $B/srv/f
chmod 0640 $B/srv/f
setfacl -m u:1234:rwx $B/srv/f

cp /etc/passwd $B/passwd
echo 'alice:x:1234:1234::/:/bin/sh' >> $B/passwd
mount --bind $B/passwd /etc/passwd
printf '[General]\nDomain = test\n' > $B/idmapd.conf

echo 0 > /sys/module/nfs/parameters/nfs4_disable_idmapping
echo 0 > /sys/module/nfsd/parameters/nfs4_disable_idmapping

mount -t tmpfs tmpfs /var/lib/nfs
mkdir -p /var/lib/nfs/rpc_pipefs /var/lib/nfs/v4recovery
touch /var/lib/nfs/etab /var/lib/nfs/rmtab
mount -t rpc_pipefs sunrpc /var/lib/nfs/rpc_pipefs
mount -t nfsd nfsd /proc/fs/nfsd
rpcbind -w 2>/dev/null || true
opts=rw,sync,no_root_squash,no_subtree_check
exportfs -o $opts,fsid=0,crossmnt 127.0.0.1:$B
exportfs -o $opts,fsid=1 127.0.0.1:$B/srv
rpc.mountd
rpc.nfsd 4
rpc.idmapd -S -c $B/idmapd.conf
mount -t nfs -o vers=4.2,nolock 127.0.0.1:/srv $B/a || { echo "FAIL: mount a"; exit 1; }
exportfs -o $opts,fsid=2 127.0.0.1:$B/a
mount -t nfs -o vers=4.2,nolock 127.0.0.1:/a $B/b || { echo "FAIL: mount b"; exit 1; }

nfs4_getfacl $B/a/f > /run/string.a 2>&1
cat /run/string.a
nfs4_getfacl $B/b/f > /run/string.b 2>&1
cat /run/string.b

# The rig has to prove itself: a numeric id would map and test nothing.
if grep -q ':alice@test:' /run/string.a; then
	echo "PASS: string a shows the name"
else
	echo "FAIL: string a does not show alice@test; the rig has no name to carry"
fi
if cmp -s /run/string.a /run/string.b; then
	echo "PASS: string b shows the same ACL as a"
else
	echo "FAIL: string b shows a different ACL from a"
fi

# Back through the re-export as a name: the set must reach the server.
nfs4_getfacl $B/b/f | nfs4_setfacl -S - $B/b/f
echo "PASS-INFO: set back rc=$?"
if [ "$(nfs4_getfacl $B/a/f | grep -c ':alice@test:')" -ge 1 ]; then
	echo "PASS: string survives being set back"
else
	echo "FAIL: string lost when set back"
fi

umount $B/b
umount $B/a
