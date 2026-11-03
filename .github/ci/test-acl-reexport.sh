#!/bin/sh
# NFSv4.2 re-export: the ACL seen through the re-exporting server must match
# the ACL seen directly, and setting one through it must reach the server
# underneath.
set -u
uname -r

B=/run/nfst
mkdir -p $B
mount -t tmpfs tmpfs $B
mkdir $B/srv $B/a $B/b
mount -t tmpfs -o mode=0777 tmpfs $B/srv
: > $B/srv/f
: > $B/srv/ga
: > $B/srv/gb
chmod 0640 $B/srv/f $B/srv/ga $B/srv/gb
setfacl -m u:1234:rwx $B/srv/f

mount -t tmpfs tmpfs /var/lib/nfs
mkdir -p /var/lib/nfs/rpc_pipefs /var/lib/nfs/v4recovery
touch /var/lib/nfs/etab /var/lib/nfs/rmtab
mount -t rpc_pipefs sunrpc /var/lib/nfs/rpc_pipefs
mount -t nfsd nfsd /proc/fs/nfsd
rpcbind -w 2>/dev/null || true

# The guest's / is virtiofs, which cannot be exported, so make $B the NFSv4
# root rather than letting mountd build a pseudo root from /.
opts=rw,sync,no_root_squash,no_subtree_check
exportfs -o $opts,fsid=0,crossmnt 127.0.0.1:$B
exportfs -o $opts,fsid=1 127.0.0.1:$B/srv
rpc.mountd
rpc.nfsd 4
mount -t nfs -o vers=4.2,nolock 127.0.0.1:/srv $B/a || { echo "FAIL: mount a"; exit 1; }
exportfs -o $opts,fsid=2 127.0.0.1:$B/a
mount -t nfs -o vers=4.2,nolock 127.0.0.1:/a $B/b || { echo "FAIL: mount b"; exit 1; }

echo "--- server: getfacl f"
getfacl -n $B/srv/f
echo "--- a: nfs4_getfacl f"
nfs4_getfacl $B/a/f > /tmp/acl.a 2>&1
cat /tmp/acl.a
echo "--- b: nfs4_getfacl f"
nfs4_getfacl $B/b/f > /tmp/acl.b 2>&1
cat /tmp/acl.b

if grep -q ':1234:' /tmp/acl.a; then
	echo "PASS: a shows the ACE for 1234"
else
	echo "FAIL: a does not show the ACE for 1234; the rig cannot see ACLs"
fi
if cmp -s /tmp/acl.a /tmp/acl.b; then
	echo "PASS: b shows the same ACL as a"
else
	echo "FAIL: b shows a different ACL from a"
fi

for via in a b; do
	echo "--- $via: nfs4_setfacl -a A::1235:r g$via"
	nfs4_setfacl -a A::1235:r $B/$via/g$via
	echo "rc=$?"
	getfacl -n $B/srv/g$via
	if getfacl -n $B/srv/g$via | grep -q '^user:1235:r'; then
		echo "PASS: setting through $via reached the server"
	else
		echo "FAIL: setting through $via did not reach the server"
	fi
done

exportfs -u 127.0.0.1:$B/a
umount $B/b
umount $B/a
