# Bash completion for the lilypond-toolkit command.
#
# Install once: drop (or symlink) this file into ~/.bash_completion.d/, or
# source it from ~/.bashrc:
#   source /path/to/lilypond-toolkit-completion.bash
#
# Only the subcommand (first argument) gets custom completion. Every
# argument after that falls through to bash's normal filename completion
# (via -o default) instead of a hand-rolled one — directories, spaces,
# and quoting all behave exactly like they do everywhere else.

_lilypond_toolkit() {
  local cur
  COMPREPLY=()

  if [[ $COMP_CWORD -eq 1 ]]; then
    cur="${COMP_WORDS[COMP_CWORD]}"
    local commands="compile play play-midi mp3"
    COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
  fi
}

complete -o default -o bashdefault -F _lilypond_toolkit lilypond-toolkit
