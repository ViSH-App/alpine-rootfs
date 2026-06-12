// ssh-agent-bridge — bridges OpenSSH clients to iSH's host-backed
// /dev/ish-ssh-agent character device.
//
// The daemon is a pure byte pump: it never parses the agent protocol.
// That contract is what lets the rootfs (daemon) and the app (protocol
// server) update independently — do not add protocol awareness here.
// See docs/ssh-key-management.md in the ish repo.
//
// Lifecycle:
//   1. If /dev/ish-ssh-agent cannot be opened (bridge disabled in app
//      Settings, or pre-bridge app version), exit 0 silently.
//   2. Singleton probe: if connect(/tmp/ssh-agent.sock) succeeds, a live
//      daemon already owns the socket — exit 0. On ECONNREFUSED/ENOENT
//      the socket file is stale (iSH does not clear /tmp across restarts),
//      so unlink it and take over.
//   3. bind + listen first, daemonize after: when the foreground call from
//      profile.d returns, the socket is guaranteed usable — no polling.
//   4. accept loop; one forked child per connection.
//   5. Child opens its own device fd (one fd = one agent session) and pumps
//      bytes both ways until either side reaches EOF or errors.

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#define DEVICE_PATH "/dev/ish-ssh-agent"
#define SOCKET_PATH "/tmp/ssh-agent.sock"

static int write_all(int fd, const char *buf, size_t len) {
    while (len > 0) {
        ssize_t n = write(fd, buf, len);
        if (n < 0) {
            if (errno == EINTR)
                continue;
            return -1;
        }
        buf += n;
        len -= (size_t) n;
    }
    return 0;
}

// Copy one readable chunk from src to dst. Returns -1 when the session is
// over (EOF or error on either side), 0 otherwise.
static int pump_once(int src, int dst) {
    char buf[4096];
    ssize_t n = read(src, buf, sizeof(buf));
    if (n < 0)
        return errno == EINTR ? 0 : -1;
    if (n == 0)
        return -1;
    return write_all(dst, buf, (size_t) n);
}

static void serve(int conn) {
    int dev = open(DEVICE_PATH, O_RDWR);
    if (dev < 0)
        return;

    struct pollfd fds[2] = {
        { .fd = conn, .events = POLLIN },
        { .fd = dev,  .events = POLLIN },
    };
    for (;;) {
        if (poll(fds, 2, -1) < 0) {
            if (errno == EINTR)
                continue;
            break;
        }
        // POLLHUP/POLLERR fall through to read(), which reports EOF/error.
        if (fds[0].revents && pump_once(conn, dev) < 0)
            break;
        if (fds[1].revents && pump_once(dev, conn) < 0)
            break;
    }
    close(dev);
}

int main(void) {
    // Probe the device; each connection opens its own fd later.
    int dev = open(DEVICE_PATH, O_RDWR);
    if (dev < 0)
        return 0;
    close(dev);

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strcpy(addr.sun_path, SOCKET_PATH);

    // Singleton probe: a successful connect means a live daemon owns the
    // socket. Mere file existence is NOT liveness — app restarts kill the
    // daemon but leave the socket file behind.
    int probe = socket(AF_UNIX, SOCK_STREAM, 0);
    if (probe < 0)
        return 1;
    if (connect(probe, (struct sockaddr *) &addr, sizeof(addr)) == 0) {
        close(probe);
        return 0;
    }
    close(probe);
    unlink(SOCKET_PATH);

    int listener = socket(AF_UNIX, SOCK_STREAM, 0);
    if (listener < 0)
        return 1;
    umask(0177);  // socket mode 0600, applied atomically at bind
    if (bind(listener, (struct sockaddr *) &addr, sizeof(addr)) < 0)
        // EADDRINUSE: lost a startup race; the winner serves the socket.
        return errno == EADDRINUSE ? 0 : 1;
    if (listen(listener, 8) < 0)
        return 1;

    // Socket is live — now detach so the profile.d caller returns.
    pid_t pid = fork();
    if (pid < 0)
        return 1;
    if (pid > 0)
        return 0;
    setsid();
    int devnull = open("/dev/null", O_RDWR);
    if (devnull >= 0) {
        dup2(devnull, 0);
        dup2(devnull, 1);
        dup2(devnull, 2);
        if (devnull > 2)
            close(devnull);
    }
    signal(SIGCHLD, SIG_IGN);  // auto-reap connection children
    signal(SIGPIPE, SIG_IGN);

    for (;;) {
        int conn = accept(listener, NULL, NULL);
        if (conn < 0) {
            if (errno == EINTR || errno == ECONNABORTED)
                continue;
            return 1;
        }
        pid = fork();
        if (pid == 0) {
            close(listener);
            serve(conn);
            _exit(0);
        }
        close(conn);
    }
}
