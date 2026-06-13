export SSH_AUTH_SOCK=/tmp/ssh-agent.sock

[ -x /usr/sbin/ssh-agent-bridge ] && /usr/sbin/ssh-agent-bridge >/dev/null 2>&1
