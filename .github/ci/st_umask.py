"""The mode_umask attribute of NFSv4.2, RFC 8275 section 5 and RFC 8881
section 5.5.  Each test names the requirement it checks."""
from xdrdef.nfs4_const import *
from xdrdef.nfs4_type import mode_umask4, stateid4, createtype4
import nfs_ops
import nfs4lib
op = nfs_ops.NFS4ops()
from .environment import check, create_file, create_obj, do_getattrdict, \
    use_obj

GOOD = mode_umask4(mu_mode=0o666, mu_umask=0o022)
BAD = mode_umask4(mu_mode=0o666, mu_umask=0o1022)   # "other than those nine"
STATEID0 = stateid4(0, b'\0' * 12)

def _sess(t, env):
    return env.c1.new_client_session(env.testname(t))

def _mode(sess, fh):
    return do_getattrdict(sess, fh, [FATTR4_MODE])[FATTR4_MODE]

def _path(t, env):
    return env.c1.homedir + [env.testname(t)]

def testOpenApplies(t, env):
    """"mu_umask MUST be used to limit the mode" on OPEN, GUARDED4

    FLAGS: umask all
    CODE: UM1
    VERS: 2-
    """
    sess = _sess(t, env)
    res = create_file(sess, env.testname(t), attrs={FATTR4_MODE_UMASK: GOOD})
    check(res)
    mode = _mode(sess, res.resarray[-1].object)
    if mode != 0o644:
        t.fail("mode is 0%o, not 0644" % mode)

def testExcl41Applies(t, env):
    """"mu_umask MUST be used to limit the mode" on OPEN, EXCLUSIVE4_1

    FLAGS: umask all
    CODE: UM2
    VERS: 2-
    """
    sess = _sess(t, env)
    res = create_file(sess, env.testname(t), mode=EXCLUSIVE4_1,
                      attrs={FATTR4_MODE_UMASK: GOOD})
    check(res)
    mode = _mode(sess, res.resarray[-1].object)
    if mode != 0o644:
        t.fail("mode is 0%o, not 0644" % mode)

def testCreateApplies(t, env):
    """"mu_umask MUST be used to limit the mode" on CREATE

    FLAGS: umask all
    CODE: UM3
    VERS: 2-
    """
    sess = _sess(t, env)
    path = _path(t, env)
    res = create_obj(sess, path, NF4DIR, {FATTR4_MODE_UMASK:
                     mode_umask4(mu_mode=0o777, mu_umask=0o022)})
    check(res)
    mode = _mode(sess, path)
    if mode != 0o755:
        t.fail("mode is 0%o, not 0755" % mode)

def testOpenHighBits(t, env):
    """Bits other than the nine: MUST return NFS4ERR_INVAL, OPEN

    FLAGS: umask all
    CODE: UM4
    VERS: 2-
    """
    sess = _sess(t, env)
    res = create_file(sess, env.testname(t), attrs={FATTR4_MODE_UMASK: BAD})
    check(res, NFS4ERR_INVAL, "OPEN with mu_umask 01022")

def testCreateHighBits(t, env):
    """Bits other than the nine: MUST return NFS4ERR_INVAL, CREATE

    FLAGS: umask all
    CODE: UM5
    VERS: 2-
    """
    sess = _sess(t, env)
    res = create_obj(sess, _path(t, env), NF4DIR, {FATTR4_MODE_UMASK: BAD})
    check(res, NFS4ERR_INVAL, "CREATE with mu_umask 01022")

def testOpenBoth(t, env):
    """mode and mode_umask together: MUST return NFS4ERR_INVAL, OPEN

    FLAGS: umask all
    CODE: UM6
    VERS: 2-
    """
    sess = _sess(t, env)
    res = create_file(sess, env.testname(t),
                      attrs={FATTR4_MODE: 0o644, FATTR4_MODE_UMASK: GOOD})
    check(res, NFS4ERR_INVAL, "OPEN with mode and mode_umask")

def testCreateBoth(t, env):
    """mode and mode_umask together: MUST return NFS4ERR_INVAL, CREATE

    FLAGS: umask all
    CODE: UM7
    VERS: 2-
    """
    sess = _sess(t, env)
    res = create_obj(sess, _path(t, env), NF4DIR,
                     {FATTR4_MODE: 0o755, FATTR4_MODE_UMASK: GOOD})
    check(res, NFS4ERR_INVAL, "CREATE with mode and mode_umask")

def testSetattr(t, env):
    """Other operations taking fattr4: MUST reject with INVAL, SETATTR

    FLAGS: umask all
    CODE: UM8
    VERS: 2-
    """
    sess = _sess(t, env)
    res = sess.compound(use_obj(env.c1.homedir) +
                        [op.setattr(STATEID0, {FATTR4_MODE_UMASK: GOOD})])
    check(res, NFS4ERR_INVAL, "SETATTR with mode_umask")

def testVerify(t, env):
    """Other operations taking fattr4: MUST reject with INVAL, VERIFY

    FLAGS: umask all
    CODE: UM9
    VERS: 2-
    """
    sess = _sess(t, env)
    res = sess.compound(use_obj(env.c1.homedir) +
                        [op.verify({FATTR4_MODE_UMASK: GOOD})])
    check(res, NFS4ERR_INVAL, "VERIFY with mode_umask")

def testNverify(t, env):
    """Other operations taking fattr4: MUST reject with INVAL, NVERIFY

    FLAGS: umask all
    CODE: UM10
    VERS: 2-
    """
    sess = _sess(t, env)
    res = sess.compound(use_obj(env.c1.homedir) +
                        [op.nverify({FATTR4_MODE_UMASK: GOOD})])
    check(res, NFS4ERR_INVAL, "NVERIFY with mode_umask")

def testGetattr(t, env):
    """Getting a set-only attribute: MUST return INVAL, GETATTR

    FLAGS: umask all
    CODE: UM11
    VERS: 2-
    """
    sess = _sess(t, env)
    res = sess.compound(use_obj(env.c1.homedir) +
                        [op.getattr(nfs4lib.list2bitmap([FATTR4_MODE_UMASK]))])
    check(res, NFS4ERR_INVAL, "GETATTR of mode_umask")

def testReaddir(t, env):
    """Getting a set-only attribute: MUST return INVAL, READDIR

    FLAGS: umask all
    CODE: UM12
    VERS: 2-
    """
    sess = _sess(t, env)
    res = sess.compound(use_obj(env.c1.homedir) +
                        [op.readdir(0, b'', 4096, 8192,
                         nfs4lib.list2bitmap([FATTR4_MODE_UMASK]))])
    check(res, NFS4ERR_INVAL, "READDIR of mode_umask")
