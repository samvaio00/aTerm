# aTerm shell integration
function aterm_shell_integration_precmd() {
  local host_name path title
  host_name=${HOST:-localhost}
  path=${PWD// /%20}
  title=${PWD:t}
  printf '\033]7;file://%s%s\a' "$host_name" "$path"
  printf '\033]0;%s\a' "$title"
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd aterm_shell_integration_precmd
add-zsh-hook chpwd aterm_shell_integration_precmd
aterm_shell_integration_precmd
