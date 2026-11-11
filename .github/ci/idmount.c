/*
 * idmount <src> <dst> <fs-id> <mount-id> <count>
 * Bind <src> on <dst> as an idmapped mount: uid and gid <fs-id>+n on the
 * filesystem appear as <mount-id>+n through the mount.  Uses the syscalls
 * directly, so that the test does not depend on what libmount supports.
 */
#define _GNU_SOURCE
#include <fcntl.h>
#include <linux/mount.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

static void die(const char *what)
{
	perror(what);
	exit(1);
}

static void put(pid_t pid, const char *file, const char *text)
{
	char path[64];
	int fd;

	snprintf(path, sizeof(path), "/proc/%d/%s", pid, file);
	fd = open(path, O_WRONLY);
	if (fd < 0 || write(fd, text, strlen(text)) != (ssize_t)strlen(text))
		die(path);
	close(fd);
}

int main(int argc, char **argv)
{
	struct mount_attr attr = { .attr_set = MOUNT_ATTR_IDMAP };
	char map[64], path[64];
	int pipefd[2], ready[2], tree, ns;
	pid_t pid;
	char c;

	if (argc != 6) {
		fprintf(stderr, "usage: idmount src dst fs-id mount-id count\n");
		return 2;
	}
	if (pipe(pipefd) || pipe(ready))
		die("pipe");
	pid = fork();
	if (pid < 0)
		die("fork");
	if (pid == 0) {
		/* Hold a user namespace open until the parent has its fd. */
		if (unshare(CLONE_NEWUSER))
			die("unshare");
		close(pipefd[1]);
		close(ready[0]);
		close(ready[1]);
		if (read(pipefd[0], &c, 1) < 0)
			_exit(1);
		_exit(0);
	}
	close(pipefd[0]);
	/* The maps can be written only once the child has unshared. */
	close(ready[1]);
	if (read(ready[0], &c, 1) != 0)
		die("ready");
	/*
	 * uid_map lines are "inside outside count".  For an idmapped mount the
	 * inside id is the filesystem's and the outside one is what the mount
	 * shows: with "100000 0 65536" a file of uid 1234 appeared as the
	 * overflow uid.
	 */
	snprintf(map, sizeof(map), "%s %s %s\n", argv[3], argv[4], argv[5]);
	put(pid, "setgroups", "deny");
	put(pid, "uid_map", map);
	put(pid, "gid_map", map);
	snprintf(path, sizeof(path), "/proc/%d/ns/user", pid);
	ns = open(path, O_RDONLY | O_CLOEXEC);
	if (ns < 0)
		die(path);
	attr.userns_fd = ns;

	tree = syscall(SYS_open_tree, AT_FDCWD, argv[1],
		       OPEN_TREE_CLONE | OPEN_TREE_CLOEXEC);
	if (tree < 0)
		die("open_tree");
	if (syscall(SYS_mount_setattr, tree, "", AT_EMPTY_PATH, &attr,
		    sizeof(attr)))
		die("mount_setattr");
	if (syscall(SYS_move_mount, tree, "", AT_FDCWD, argv[2],
		    MOVE_MOUNT_F_EMPTY_PATH))
		die("move_mount");
	close(pipefd[1]);
	waitpid(pid, NULL, 0);
	return 0;
}
