#!/bin/sh
# A DACL read over SMB from a file with an NFSv4 ACL, on the CI patch's tmpfs.
set -u
uname -r
B=/run/ksmb
mkdir -p $B
echo 1 > /sys/module/kernel/parameters/shmem_nfs4acl
mount -t tmpfs -o mode=0777 tmpfs $B
echo 0 > /sys/module/kernel/parameters/shmem_nfs4acl
: > $B/f
: > $B/g
chmod 644 $B/f $B/g
nfs4_setfacl -a A::1234:rw $B/f
nfs4_setfacl -a D::1235:r $B/f
nfs4_getfacl $B/f

C=/tmp/ksmbd.conf
P=/tmp/ksmbdpwd.db
: > $P
cat > $C <<EOF
[global]
	guest account = nobody
[s]
	path = $B
	read only = no
EOF
useradd -M ktest 2>/dev/null
ksmbd.adduser -P $P -C $C -a ktest -p ktestpw || echo "FAIL: adduser"
ksmbd.mountd -C $C -P $P || echo "FAIL: mountd"
tries=0
until smbclient -m SMB3 -L 127.0.0.1 -U ktest%ktestpw >/dev/null 2>&1 || [ $tries -gt 10 ]; do
	tries=$((tries + 1)); sleep 1
done
smbcacls -m SMB3 --numeric -U ktest%ktestpw //127.0.0.1/s f > /tmp/cacl.f 2>&1
smbcacls -m SMB3 --numeric -U ktest%ktestpw //127.0.0.1/s g > /tmp/cacl.g 2>&1
cat /tmp/cacl.f /tmp/cacl.g
grep -Eq 'ACL:S-1-.*-1234:0/0x0/0x00000003' /tmp/cacl.f && echo "PASS: allow ACE for 1234 over SMB" || echo "FAIL: no allow ACE for 1234"
grep -Eq 'ACL:S-1-.*-1235:1/0x0/0x00000001' /tmp/cacl.f && echo "PASS: deny ACE for 1235 over SMB" || echo "FAIL: no deny ACE for 1235"
grep -q 'ACL:' /tmp/cacl.g && echo "PASS: a file with no named ACE has a DACL" || echo "FAIL: g has no DACL"
