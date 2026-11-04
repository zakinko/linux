/* SPDX-License-Identifier: GPL-2.0 */
/*
 * An NFSv4 ACL as the VFS sees it.  Filesystems include this without what
 * linux/nfs4.h brings in for the protocol.
 */
#ifndef _LINUX_NFS4_ACL_H
#define _LINUX_NFS4_ACL_H

#include <linux/types.h>
#include <linux/uidgid.h>

enum nfs4_acl_whotype {
	NFS4_ACL_WHO_NAMED = 0,
	NFS4_ACL_WHO_OWNER,
	NFS4_ACL_WHO_GROUP,
	NFS4_ACL_WHO_EVERYONE,
	NFS4_ACL_WHO_STRING,	/* a principal with no local id */
};

enum nfs4_acl_type {
	NFS4ACL_NONE = 0,
	NFS4ACL_ACL,
	NFS4ACL_DACL,
	NFS4ACL_SACL,
};

/* RFC 8881 6.4.3.2: the flag of a dacl or sacl */
#define NFS4_ACL_AUTO_INHERIT	0x00000001
#define NFS4_ACL_PROTECTED	0x00000002
#define NFS4_ACL_DEFAULTED	0x00000004
#define NFS4_ACL_FLAGS		(NFS4_ACL_AUTO_INHERIT | NFS4_ACL_PROTECTED | \
				 NFS4_ACL_DEFAULTED)

struct nfs4_ace {
	uint32_t	type;
	uint32_t	flag;
	uint32_t	access_mask;
	int		whotype;
	union {
		kuid_t	who_uid;
		kgid_t	who_gid;
		struct {
			const char	*who_str;
			u32		who_strlen;
		};
	};
};

struct nfs4_acl {
	uint32_t	flag;		/* dacl and sacl only */
	uint32_t	naces;
	struct nfs4_ace	aces[];
};

#endif /* _LINUX_NFS4_ACL_H */
