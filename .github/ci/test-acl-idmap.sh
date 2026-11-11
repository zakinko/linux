#!/bin/sh
# NFSv4 ACL ids through an idmapped mount.  The reference is the owner: an ACE
# naming a uid must be mapped the way stat maps a file owned by that uid.
set -u
uname -r
B=/run/idm
mkdir -p $B/fs $B/m
echo 1 > /sys/module/kernel/parameters/shmem_nfs4acl
mount -t tmpfs -o mode=0777 tmpfs $B/fs
echo 0 > /sys/module/kernel/parameters/shmem_nfs4acl
mount --bind -o X-mount.idmap=b:0:100000:65536 $B/fs $B/m ||
	{ echo "FAIL: idmapped mount"; exit 1; }
grep " $B/m " /proc/self/mountinfo

# What the mount shows for fs uids 1234 and 1235.
: > $B/fs/o1; chown 1234:1234 $B/fs/o1
: > $B/fs/o2; chown 1235:1235 $B/fs/o2
v1=$(stat -c %u $B/m/o1)
v2=$(stat -c %u $B/m/o2)
g1=$(stat -c %g $B/m/o1)
echo "MEASURE: fs 1234 is $v1 through the mount, 1235 is $v2, gid 1234 is $g1"
[ "$v1" != 1234 ] || { echo "FAIL: the mount maps nothing"; exit 1; }

: > $B/fs/f; chmod 644 $B/fs/f
nfs4_setfacl -a A::1234:r $B/fs/f
nfs4_setfacl -a A:g:1234:r $B/fs/f
echo "--- fs"; nfs4_getfacl $B/fs/f
echo "--- mount"; nfs4_getfacl $B/m/f | tee $B/got
grep -q "^A::$v1:" $B/got && echo "PASS: read maps the uid as stat does" ||
	echo "FAIL: read does not show uid $v1"
grep -q "^A:g:$g1:" $B/got && echo "PASS: read maps the gid as stat does" ||
	echo "FAIL: read does not show gid $g1"

if nfs4_setfacl -a A::$v2:w $B/m/f; then
	echo "--- fs after set through the mount"; nfs4_getfacl $B/fs/f | tee $B/set
	grep -q '^A::1235:w' $B/set && echo "PASS: set maps the uid back" ||
		echo "FAIL: set did not store uid 1235"
	grep -q "^A::$v1:" $B/set && echo "FAIL: a mapped uid was stored as is" ||
		echo "PASS: no mapped uid stored"
else
	echo "FAIL: set through the idmapped mount refused"
fi
echo "PASS: idmap test finished"
