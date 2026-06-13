export SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"
export EDITOR="${EDITOR:-nano}"
export VISUAL="${VISUAL:-$EDITOR}"
# iSH passes these dirs in PATH via execve, but login(1) strips that PATH and
# /etc/profile resets it to the standard six; re-prepend to match the app.
# Unconditional: installers (pip, uv, bun) create these dirs mid-session, and
# a not-yet-existing PATH entry is harmless.
for _d in "$HOME/.bun/bin" "$HOME/.local/bin"; do
  case ":$PATH:" in
    *":$_d:"*) ;;
    *) PATH="$_d:$PATH" ;;
  esac
done
unset _d
export PATH
