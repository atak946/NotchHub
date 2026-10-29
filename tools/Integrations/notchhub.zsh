# notchhub.zsh - notch alert when a long shell command finishes.
#
# Add ONE line to ~/.zshrc:   source /path/to/notchhub.zsh
#
#   ✓ dotnet build · 1m 12s              (exit 0  -> success, green)
#   ✗ npm test failed (exit 1) · 45s     (exit !0 -> urgent, red)
#
# The app formats the message from the raw command line, exit code and elapsed time.
#
# Configuration (environment, read on every command):
#   NOTCHHUB_MIN_SECONDS        minimum runtime before alerting (default 30)
#   NOTCHHUB_IGNORE             space separated list replacing the default ignore list;
#                               entries are a command ("vim") or command + subcommand ("docker attach")
#   NOTCHHUB_IGNORE_EXTRA       entries appended to the ignore list
#   NOTCHHUB_NOTIFY_INTERRUPTED set to 1 to also alert for Ctrl-C (exit 130)
#   NOTCHHUB_DISABLE            set to 1 to switch the hook off
#   NOTCHHUB_SOCKET             socket path override

[[ -o interactive ]] || return 0
(( ${+_notchhub_loaded} )) && return 0
typeset -g _notchhub_loaded=1

zmodload zsh/datetime 2>/dev/null || return 0
autoload -Uz add-zsh-hook

typeset -g _notchhub_default_ignore='vi vim nvim nano emacs micro hx less more most man info top htop btop atop
 ssh mosh telnet sftp tmux screen zellij watch tail fzf ranger lf nnn mc tig lazygit lazydocker k9s claude
 docker\ attach docker\ exec kubectl\ exec kubectl\ logs kubectl\ port-forward git\ log git\ diff'
# REPLs: ignored only when started without arguments (`python` yes, `python build.py` no).
typeset -g _notchhub_repls='python python3 ipython node deno bun irb ruby psql mysql sqlite3 redis-cli
 mongosh lua ghci swift dotnet-script'
typeset -g _notchhub_wrappers='sudo env time nice nohup command builtin exec noglob nocorrect caffeinate'
typeset -g _notchhub_cmd=''
typeset -g _notchhub_start=''

# Sets REPLY to "<command> <subcommand>" after skipping env assignments and wrapper words.
_notchhub_command_words() {
  emulate -L zsh
  setopt extended_glob
  local -a words wrappers
  words=(${(z)1})
  wrappers=(${=_notchhub_wrappers})
  local word cmd='' sub='' after_wrapper=0
  for word in $words; do
    if [[ -z $cmd ]]; then
      [[ $word == [A-Za-z_][A-Za-z0-9_]#=* ]] && continue
      (( after_wrapper )) && [[ $word == -* ]] && continue
      if (( ${wrappers[(Ie)${word:t}]} )); then
        after_wrapper=1
        continue
      fi
      cmd=${word:t}
    else
      sub=$word
      break
    fi
  done
  REPLY="$cmd${sub:+ $sub}"
}

_notchhub_is_ignored() {
  emulate -L zsh
  _notchhub_command_words "$1"
  local words=$REPLY cmd=${REPLY%% *}
  [[ -z $cmd ]] && return 0
  local -a ignore repls
  ignore=(${(z)${NOTCHHUB_IGNORE-$_notchhub_default_ignore}} ${(z)${NOTCHHUB_IGNORE_EXTRA:-}})
  ignore=(${(Q)ignore})
  repls=(${=_notchhub_repls})
  (( ${ignore[(Ie)$cmd]} )) && return 0
  (( ${ignore[(Ie)$words]} )) && return 0
  [[ $words == $cmd ]] && (( ${repls[(Ie)$cmd]} )) && return 0
  return 1
}

_notchhub_json_escape() {
  emulate -L zsh
  local s=${1//[$'\t\n\r']/ }
  s=${s//[[:cntrl:]]/}
  s=${s//\\/\\\\}
  REPLY=${s//\"/\\\"}
}

_notchhub_urlencode() {
  emulate -L zsh
  local LC_ALL=C s=$1 out='' c hex
  local -i i
  for (( i = 1; i <= ${#s}; i++ )); do
    c=${s[i]}
    if [[ $c == [A-Za-z0-9._~-] ]]; then
      out+=$c
    else
      printf -v hex '%%%02X' "'$c"
      out+=$hex
    fi
  done
  REPLY=$out
}

# $1 command line, $2 exit code, $3 elapsed seconds. Runs in the background.
_notchhub_post() {
  emulate -L zsh
  local socket=${NOTCHHUB_SOCKET:-$HOME/Library/Application Support/NotchHub/notchhub.sock}
  local subtitle="in ${PWD:t}"
  local command_json subtitle_json
  _notchhub_json_escape "$1"; command_json=$REPLY
  _notchhub_json_escape "$subtitle"; subtitle_json=$REPLY
  local json="{\"action\":\"alert\",\"command\":\"$command_json\",\"exit\":$2,\"elapsed\":$3,\"subtitle\":\"$subtitle_json\"}"

  if [[ -S $socket ]] && zmodload zsh/net/socket 2>/dev/null && zsocket "$socket" 2>/dev/null; then
    local fd=$REPLY reply=''
    print -r -u $fd -- "$json"
    # Wait for the reply: NotchHub may drop connections that close before they are accepted.
    read -t 2 -r -u $fd reply
    exec {fd}>&-
    return 0
  fi
  if [[ -S $socket ]] && (( ${+commands[nc]} )); then
    print -r -- "$json" | nc -U -w 2 "$socket" >/dev/null 2>&1 && return 0
  fi
  (( ${+commands[open]} )) || return 0
  local query=''
  _notchhub_urlencode "$1"; query+="command=$REPLY"
  query+="&exit=$2&elapsed=$3"
  _notchhub_urlencode "$subtitle"; query+="&subtitle=$REPLY"
  open -g "notchhub://alert?$query" >/dev/null 2>&1
}

_notchhub_preexec() {
  _notchhub_cmd=$1
  _notchhub_start=$EPOCHREALTIME
}

_notchhub_precmd() {
  local -i exit_code=$?
  [[ -n $_notchhub_start ]] || return 0
  local -F elapsed=$(( EPOCHREALTIME - _notchhub_start ))
  local cmd=$_notchhub_cmd
  _notchhub_start=''
  _notchhub_cmd=''

  [[ ${NOTCHHUB_DISABLE:-0} == 1 ]] && return 0
  local min=${NOTCHHUB_MIN_SECONDS:-30}
  [[ $min == <-> ]] || min=30
  (( elapsed >= min )) || return 0
  (( exit_code == 130 )) && [[ ${NOTCHHUB_NOTIFY_INTERRUPTED:-0} != 1 ]] && return 0
  _notchhub_is_ignored "$cmd" && return 0

  _notchhub_post "$cmd" $exit_code ${elapsed%.*} &!
}

add-zsh-hook preexec _notchhub_preexec
# Run first so `$?` is still the user's command status.
precmd_functions=(_notchhub_precmd ${precmd_functions:#_notchhub_precmd})
