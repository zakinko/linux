#!/bin/sh
# Teach pynfs the mode_umask attribute (RFC 8275 section 5) and add its tests.
# Run from the kernel tree, before pynfs is built.
set -eu
X=.pynfs/nfs4.1/xdrdef/nfs4.x
sed -i 's/^typedef bool            fattr4_xattr_support;/&\nstruct mode_umask4 {\n\tmode4 mu_mode;\n\tmode4 mu_umask;\n};\ntypedef mode_umask4 fattr4_mode_umask;/' $X
sed -i 's/^const FATTR4_XATTR_SUPPORT      = 82;/const FATTR4_MODE_UMASK         = 81;\n&/' $X
cp .github/ci/st_umask.py .pynfs/nfs4.1/server41tests/
sed -i 's/"st_courtesy.py",/&\n           "st_umask.py",/' .pynfs/nfs4.1/server41tests/__init__.py
grep -n 'mode_umask\|MODE_UMASK' $X
