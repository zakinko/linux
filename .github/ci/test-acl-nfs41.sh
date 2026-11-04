#!/bin/sh
# dacl and sacl through an NFSv4.2 re-export, on a tmpfs the CI patch has given
# NFSv4 ACLs.  The checks are in the python below.
set -u
uname -r

B=/run/nfs41
mkdir -p $B
mount -t tmpfs tmpfs $B
mkdir $B/a $B/b $B/srv
echo 1 > /sys/module/kernel/parameters/shmem_nfs4acl
mount -t tmpfs -o mode=0777 tmpfs $B/srv
echo 0 > /sys/module/kernel/parameters/shmem_nfs4acl
: > $B/srv/f
: > $B/srv/g

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
mount -t nfs -o vers=4.2,nolock 127.0.0.1:/srv $B/a || { echo "FAIL: mount a"; exit 1; }
exportfs -o $opts,fsid=2 127.0.0.1:$B/a
mount -t nfs -o vers=4.2,nolock 127.0.0.1:/a $B/b || { echo "FAIL: mount b"; exit 1; }
cat > /run/acl41.py <<'PY'
import os, struct, sys
A, B = sys.argv[1] + '/a/', sys.argv[1] + '/b/'
def ace(t, f, m, who):
    w = who.encode()
    return struct.pack('>4I', t, f, m, len(w)) + w + b'\0' * (-len(w) % 4)
def val(flag, aces):
    return struct.pack('>2I', flag, len(aces)) + b''.join(aces)
def ok(d, c):
    print(('PASS: ' if c else 'FAIL: ') + d)
def refused(path, name, v):
    try:
        os.setxattr(path, name, v)
    except OSError as e:
        return True
    return False
def rd(path, name):
    try:
        return os.getxattr(path, name)
    except OSError as e:
        print('read', path, name, e)
        return None
D, S = 'system.nfs4_dacl', 'system.nfs4_sacl'
dacl = val(2, [ace(0, 0, 7, '1234'), ace(1, 0, 2, 'EVERYONE@')])
sacl = val(1, [ace(2, 0x10, 7, '1235')])
os.setxattr(B + 'f', D, dacl)
ok('dacl set through b reads back on a', rd(A + 'f', D) == dacl)
ok('dacl reads back on b with its flag', rd(B + 'f', D) == dacl)
os.setxattr(B + 'f', S, sacl)
ok('sacl set through b reads back on a', rd(A + 'f', S) == sacl)
ok('sacl reads back on b', rd(B + 'f', S) == sacl)
ok('dacl unchanged by the sacl', rd(B + 'f', D) == dacl)
ok('AUDIT refused in a dacl', refused(B + 'g', D, val(0, [ace(2, 0, 7, '1234')])))
ok('ALLOW refused in a sacl', refused(B + 'g', S, val(0, [ace(0, 0, 7, '1234')])))
ok('unknown flag refused', refused(B + 'g', D, val(8, [ace(0, 0, 7, '1234')])))
named = val(0, [ace(0, 0, 7, 'alice@nowhere')])
os.setxattr(B + 'g', D, named)
ok('unmapped name set through b survives', rd(A + 'g', D) == named)
ok('unmapped name reads back on b', rd(B + 'g', D) == named)
named = struct.pack('>I', 1) + ace(0, 0, 7, 'alice@nowhere')
os.setxattr(B + 'f', 'system.nfs4_acl', named)
ok('unmapped name in the acl attribute', rd(A + 'f', 'system.nfs4_acl') == named)
spc = struct.pack('>I', 1) + ace(0, 0x40, 7, 'EVERYONE@')
os.setxattr(B + 'g', 'system.nfs4_acl', spc)
ok('group flag dropped from EVERYONE@',
   rd(A + 'g', 'system.nfs4_acl') == struct.pack('>I', 1) + ace(0, 0, 7, 'EVERYONE@'))
inh = struct.pack('>I', 1) + ace(0, 0x80, 7, '1234')
ok('INHERITED refused in the acl attribute', refused(B + 'g', 'system.nfs4_acl', inh))
PY
python3 /run/acl41.py $B
umount $B/b
umount $B/a
