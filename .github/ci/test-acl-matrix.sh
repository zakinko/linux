#!/bin/sh
# What ACLs do on each path.  A table to read, so the lines are MATRIX and a
# cell that does not work is not a broken build.
# R: an ACE set on the server is seen by the client.
# W: an ACE set by the client reaches the server.
# I: a file created under an inheritable ACE, umask 077, carries the ACE.
# U: the mode of that file (want 666), and of one with no inheritance (want 600).
set -u
uname -r
B=/run/mx
mkdir -p $B
mount -t tmpfs tmpfs /var/lib/nfs
mkdir -p /var/lib/nfs/rpc_pipefs /var/lib/nfs/v4recovery
touch /var/lib/nfs/etab /var/lib/nfs/rmtab
mount -t rpc_pipefs sunrpc /var/lib/nfs/rpc_pipefs
mount -t nfsd nfsd /proc/fs/nfsd
rpcbind -w 2>/dev/null || true
opts=rw,sync,no_root_squash,insecure,no_subtree_check
mkdir $B/p $B/n
mount -t tmpfs -o mode=0777 tmpfs $B/p
echo 1 > /sys/module/kernel/parameters/shmem_nfs4acl
mount -t tmpfs -o mode=0777 tmpfs $B/n
echo 0 > /sys/module/kernel/parameters/shmem_nfs4acl
exportfs -o $opts,fsid=0,crossmnt 127.0.0.1:$B
exportfs -o $opts,fsid=1 127.0.0.1:$B/p
exportfs -o $opts,fsid=2 127.0.0.1:$B/n
rpc.mountd
echo 10 > /proc/fs/nfsd/nfsv4leasetime
echo 10 > /proc/fs/nfsd/nfsv4gracetime
rpc.nfsd 8
sleep 15

fsid=10
seq=0

# Mount <vers> <export path> <mount point>
mnt() {
	mkdir -p $3
	case $1 in
	3) timeout 30 mount -t nfs -o vers=3,nolock,actimeo=0 127.0.0.1:$2 $3 ;;
	*) timeout 30 mount -t nfs -o vers=$1,nolock,actimeo=0 127.0.0.1:${2#$B} $3 ;;
	esac 2>/dev/null
}

# srv_set <fs> <file> <id> <flags>
srv_set() {
	if [ $1 = p ]; then
		if [ -n "${4:-}" ]; then
			setfacl -d -m u::rwx,g::rwx,o::rwx,u:$3:rwx $2
		else
			setfacl -m u:$3:rw $2
		fi
	else
		nfs4_setfacl -a A:${4:-}:$3:rw $2
		[ -z "${4:-}" ] || nfs4_setfacl -a A:$4:EVERYONE@:rwaxtTnNcCy $2
	fi
}
srv_has() {
	if [ $1 = p ]; then getfacl -cn $2 2>/dev/null | grep -q "user:$3:"
	else nfs4_getfacl $2 2>/dev/null | grep -q ":$3:"; fi
}
cl_has() {
	if [ $1 = 3 ]; then getfacl -cn $2 2>/dev/null | grep -q "user:$3:"
	else nfs4_getfacl $2 2>/dev/null | grep -q ":$3:"; fi
}
cl_set() {
	if [ $1 = 3 ]; then setfacl -m u:$3:rw $2 2>/dev/null
	else nfs4_setfacl -a A::$3:rw $2 2>/dev/null; fi
}

# cell <fs> <client vers> <client dir> <server dir> <label>
cell() {
	seq=$((seq + 1))
	d=t$seq
	mkdir -m 777 $4/$d $4/$d.i $4/$d.pl
	: > $4/$d/r; chmod 644 $4/$d/r
	: > $4/$d/w; chmod 644 $4/$d/w
	srv_set $1 $4/$d/r 1234
	srv_set $1 $4/$d.i 1234 fd
	R=no; cl_has $2 $3/$d/r 1234 && R=yes
	W=no; cl_set $2 $3/$d/w 1235 && srv_has $1 $4/$d/w 1235 && W=yes
	(umask 077; : > $3/$d.i/f; : > $3/$d.pl/f)
	I=no; srv_has $1 $4/$d.i/f 1234 && I=yes
	U=$(stat -c %a $4/$d.i/f 2>/dev/null)/$(stat -c %a $4/$d.pl/f 2>/dev/null)
	echo "MATRIX: $5 R=$R W=$W I=$I U=$U"
}

for fs in p n; do
	for v in 3 4.0 4.1 4.2; do
		m=$B/m.$fs.$v
		if mnt $v $B/$fs $m; then
			cell $fs $v $m $B/$fs "$fs direct v$v"
		else
			echo "MATRIX: $fs direct v$v no mount"
		fi
	done
	for l in 3 4.0 4.1 4.2; do
		for u in 3 4.2; do
			lo=$B/lo.$fs.$l.$u
			up=$B/up.$fs.$l.$u
			mnt $l $B/$fs $lo || { echo "MATRIX: $fs lower v$l no mount"; continue; }
			fsid=$((fsid + 1))
			exportfs -o $opts,fsid=$fsid,crossmnt 127.0.0.1:$lo
			if mnt $u $lo $up; then
				cell $fs $u $up $B/$fs "$fs reexport lower v$l upper v$u"
			else
				echo "MATRIX: $fs reexport lower v$l upper v$u no mount"
			fi
		done
	done
done

# overlayfs over a POSIX ACL tmpfs, exported.
mkdir $B/ov $B/ov/l $B/ov/u $B/ov/w $B/ov/m
mount -t tmpfs tmpfs $B/ov/u
mkdir $B/ov/u/u $B/ov/u/w
mount -t overlay overlay -o lowerdir=$B/ov/l,upperdir=$B/ov/u/u,workdir=$B/ov/u/w,nfs_export=on,index=on \
    $B/ov/m 2>/dev/null && {
	chmod 777 $B/ov/m
	exportfs -o $opts,fsid=90 127.0.0.1:$B/ov/m
	mnt 4.2 $B/ov/m $B/ov/c && cell p 4.2 $B/ov/c $B/ov/m "p overlay v4.2"
	mnt 3 $B/ov/m $B/ov/c3 && cell p 3 $B/ov/c3 $B/ov/m "p overlay v3"
} || echo "MATRIX: overlay did not mount"
echo "PASS: matrix finished"
