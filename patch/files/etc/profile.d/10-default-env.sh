export SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"
# bash self-initializes TERM=dumb when the spawner leaves it unset, so treat
# dumb as "not provided" too. xterm-direct has no terminfo entry in
# ncurses-terminfo-base; truecolor is signaled via COLORTERM, not TERM.
if [ -z "${TERM:-}" ] || [ "$TERM" = dumb ]; then
  export TERM=xterm-256color
fi
export EDITOR="${EDITOR:-nano}"
export VISUAL="${VISUAL:-$EDITOR}"
if [ -z "${HOME:-}" ] || [ ! -d "$HOME" ]; then
  export HOME=/root
fi
# iSH passes these dirs in PATH via execve, but login(1) strips that PATH and
# /etc/profile resets it to the standard six; re-prepend to match the app.
for _d in "$HOME/.bun/bin" "$HOME/.local/bin"; do
  case ":$PATH:" in
    *":$_d:"*) ;;
    *) if [ -d "$_d" ]; then PATH="$_d:$PATH"; fi ;;
  esac
done
unset _d
export PATH
