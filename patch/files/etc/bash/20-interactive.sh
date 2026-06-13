HISTCONTROL=ignoreboth
HISTSIZE=1000
HISTFILESIZE=2000
shopt -s histappend
# iSH sessions are SIGKILLed on app switch/close, so bash never reaches the
# normal-exit hook that flushes history to disk. Append after every command.
PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND$'\n'}history -a"

alias ll='ls -alh'
alias la='ls -A'
