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
chown ktest $B/f
mkdir $B/d; chown ktest $B/d
nfs4_setfacl -a A::1234:rw $B/d
smbcacls -m SMB3 --numeric -U ktest%ktestpw //127.0.0.1/s f > /tmp/cacl.f 2>&1
smbcacls -m SMB3 --numeric -U ktest%ktestpw //127.0.0.1/s g > /tmp/cacl.g 2>&1
cat /tmp/cacl.f /tmp/cacl.g
grep -Eq 'ACL:S-1-.*-1234:0/0x0/0x00000003' /tmp/cacl.f && echo "PASS: allow ACE for 1234 over SMB" || echo "FAIL: no allow ACE for 1234"
grep -Eq 'ACL:S-1-.*-1235:1/0x0/0x00000001' /tmp/cacl.f && echo "PASS: deny ACE for 1235 over SMB" || echo "FAIL: no deny ACE for 1235"
grep -q 'ACL:' /tmp/cacl.g && echo "PASS: a file with no named ACE has a DACL" || echo "FAIL: g has no DACL"

D=${C%/*}
pfx=$(sed -n 's/^ACL:\(S-1-.*\)-1234:.*/\1/p' $D/cacl.f | head -1)
sc() { smbcacls -m SMB3 --numeric -U ktest%ktestpw //127.0.0.1/s "$@"; }
mode0=$(stat -c %a $B/f)
ls -ln $B/f $B/d; id ktest
sc f
echo all > /sys/class/ksmbd-control/debug
dmesg -C
sc f -a "ACL:$pfx-1236:ALLOWED/0x0/0x00000001"
dmesg | grep -E 'ksmbd|smb' | tail -40 | cut -c1-120 | sed 's/^/KDBG: /'
echo none > /sys/class/ksmbd-control/debug 2>/dev/null
nfs4_getfacl $B/f | tee $D/w.f
grep -q 'A::1236:r' $D/w.f && echo "PASS: ACE written over SMB" || echo "FAIL: no ACE for 1236"
grep -q 'D::1235:' $D/w.f && echo "PASS: deny ACE kept" || echo "FAIL: deny ACE lost"
grep -q 'A::1234:' $D/w.f && echo "PASS: other ACE kept" || echo "FAIL: ACE 1234 lost"
[ "$(stat -c %a $B/f)" = "$mode0" ] && echo "PASS: mode not forced" || echo "MEASURE: mode $mode0 to $(stat -c %a $B/f)"
sc f -a "ACL:S-1-5-21-9-9-9-1000:ALLOWED/0x0/0x00000001" && echo "FAIL: unmappable SID accepted" || echo "PASS: unmappable SID refused"
nfs4_getfacl $B/f > $D/w2.f; cmp -s $D/w.f $D/w2.f && echo "PASS: refused set changed nothing" || echo "FAIL: ACL changed by a refused set"
sc d -a "ACL:$pfx-1237:ALLOWED/0x3/0x00000001"
nfs4_getfacl $B/d | tee $D/w.d
grep -Eq 'A:[a-z]*f[a-z]*:1237:|A:[a-z]*d[a-z]*:1237:' $D/w.d && echo "PASS: inherit flags written" || echo "FAIL: inherit flags lost"
