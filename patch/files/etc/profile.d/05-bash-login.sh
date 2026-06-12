# Rootfs patch: land interactive logins in bash on roots deployed before
# /etc/passwd switched root's shell to /bin/bash. The overlay can only write
# whole files (editing passwd would clobber user-added accounts), so exec
# bash from the ash login shell instead. No-op under bash or when bash is
# missing; non-interactive shells are untouched.
if [ -z "${BASH_VERSION:-}" ] && [ -x /bin/bash ]; then
  case "$-" in
    *i*) exec /bin/bash -l ;;
  esac
fi
