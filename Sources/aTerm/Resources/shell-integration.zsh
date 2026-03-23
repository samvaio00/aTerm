# aTerm shell integration
# OSC 133 prompt/command markers for semantic scrollback
# OSC 7 working directory reporting

__aterm_prompt_start() {
  printf '\033]133;A\a'
}

__aterm_prompt_end() {
  printf '\033]133;B\a'
}

__aterm_command_output_start() {
  printf '\033]133;C\a'
}

__aterm_command_finished() {
  printf '\033]133;D;%s\a' "$?"
}

__aterm_report_cwd() {
  local host_name path title
  host_name=${HOST:-localhost}
  path=${PWD// /%20}
  title=${PWD:t}
  printf '\033]7;file://%s%s\a' "$host_name" "$path"
  printf '\033]0;%s\a' "$title"
}

# Track command start time
typeset -g __aterm_cmd_start
__aterm_preexec() {
  __aterm_cmd_start=$EPOCHREALTIME
  __aterm_command_output_start
}

__aterm_precmd() {
  local exit_code=$?
  __aterm_command_finished
  __aterm_report_cwd

  # Report command duration if available
  if [[ -n "$__aterm_cmd_start" ]]; then
    local duration=$(( EPOCHREALTIME - __aterm_cmd_start ))
    printf '\033]133;E;%s;%s\a' "$exit_code" "$duration"
    unset __aterm_cmd_start
  fi

  __aterm_prompt_start
}

# Install hooks
autoload -Uz add-zsh-hook
add-zsh-hook precmd __aterm_precmd
add-zsh-hook preexec __aterm_preexec
add-zsh-hook chpwd __aterm_report_cwd

# Emit initial prompt marker
__aterm_report_cwd
__aterm_prompt_start
