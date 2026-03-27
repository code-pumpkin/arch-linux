# Powerlevel10k — slate/mist theme, no blue
'builtin' 'local' '-a' 'p10k_config_opts'
[[ ! -o 'aliases'         ]] || p10k_config_opts+=('aliases')
[[ ! -o 'sh_glob'         ]] || p10k_config_opts+=('sh_glob')
[[ ! -o 'no_brace_expand' ]] || p10k_config_opts+=('no_brace_expand')
'builtin' 'setopt' 'no_aliases' 'no_sh_glob' 'brace_expand'

() {
  emulate -L zsh -o extended_glob
  unset -m '(POWERLEVEL9K_*|DEFAULT_USER)~POWERLEVEL9K_GITSTATUS_DIR'

  typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(
    os_icon
    dir
    vcs
    command_execution_time
    newline
    prompt_char
  )

  typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
    status
    background_jobs
    virtualenv
    node_version
    rust_version
    context
  )

  typeset -g POWERLEVEL9K_MODE=nerdfont-v3
  typeset -g POWERLEVEL9K_ICON_PADDING=moderate
  typeset -g POWERLEVEL9K_PROMPT_ADD_NEWLINE=true
  typeset -g POWERLEVEL9K_TRANSIENT_PROMPT=same-dir
  typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet
  typeset -g POWERLEVEL9K_DISABLE_HOT_RELOAD=true

  # No background — clean inline style
  typeset -g POWERLEVEL9K_BACKGROUND=
  typeset -g POWERLEVEL9K_LEFT_SUBSEGMENT_SEPARATOR=' '
  typeset -g POWERLEVEL9K_RIGHT_SUBSEGMENT_SEPARATOR=' '
  typeset -g POWERLEVEL9K_LEFT_SEGMENT_SEPARATOR=''
  typeset -g POWERLEVEL9K_RIGHT_SEGMENT_SEPARATOR=''
  typeset -g POWERLEVEL9K_LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL=''
  typeset -g POWERLEVEL9K_RIGHT_PROMPT_FIRST_SEGMENT_START_SYMBOL=''
  typeset -g POWERLEVEL9K_LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL=''
  typeset -g POWERLEVEL9K_RIGHT_PROMPT_LAST_SEGMENT_END_SYMBOL=''
  typeset -g POWERLEVEL9K_EMPTY_LINE_LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL=

  # OS icon — sage green
  typeset -g POWERLEVEL9K_OS_ICON_FOREGROUND=108

  # Directory — sage green, no teal/blue
  typeset -g POWERLEVEL9K_DIR_FOREGROUND=108
  typeset -g POWERLEVEL9K_SHORTEN_STRATEGY=truncate_to_unique
  typeset -g POWERLEVEL9K_SHORTEN_DELIMITER=
  typeset -g POWERLEVEL9K_DIR_SHORTENED_FOREGROUND=242
  typeset -g POWERLEVEL9K_DIR_ANCHOR_FOREGROUND=108
  typeset -g POWERLEVEL9K_DIR_ANCHOR_BOLD=true
  typeset -g POWERLEVEL9K_DIR_MAX_LENGTH=60
  typeset -g POWERLEVEL9K_DIR_CLASSES=(
    '~/Desktop'   HOME_SUB  '󰍺'
    '~/Downloads'  HOME_SUB  '󰉍'
    '~'           HOME      '󰋜'
    '~/*'         HOME_SUB  '󰉋'
    '*'           DEFAULT   '󰉋'
  )
  typeset -g POWERLEVEL9K_DIR_HOME_FOREGROUND=108
  typeset -g POWERLEVEL9K_DIR_HOME_SUB_FOREGROUND=108
  typeset -g POWERLEVEL9K_DIR_DEFAULT_FOREGROUND=108

  # Git — sage green clean, warm sand modified, terracotta untracked, soft red conflict
  typeset -g POWERLEVEL9K_VCS_CLEAN_FOREGROUND=108
  typeset -g POWERLEVEL9K_VCS_MODIFIED_FOREGROUND=179
  typeset -g POWERLEVEL9K_VCS_UNTRACKED_FOREGROUND=179
  typeset -g POWERLEVEL9K_VCS_CONFLICTED_FOREGROUND=167
  typeset -g POWERLEVEL9K_VCS_LOADING_FOREGROUND=242
  typeset -g POWERLEVEL9K_VCS_BRANCH_ICON=' '

  # Prompt char — sage ok, terracotta error
  typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=108
  typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=167
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIINS_CONTENT_EXPANSION='❯'
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VICMD_CONTENT_EXPANSION='❮'
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIVIS_CONTENT_EXPANSION='V'
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIOWR_CONTENT_EXPANSION='▶'
  typeset -g POWERLEVEL9K_PROMPT_CHAR_OVERWRITE_STATE=true

  # Command execution time — warm sand
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD=3
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_PRECISION=0
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FOREGROUND=179
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FORMAT='d h m s'

  # Status — terracotta error
  typeset -g POWERLEVEL9K_STATUS_EXTENDED_STATES=true
  typeset -g POWERLEVEL9K_STATUS_OK=false
  typeset -g POWERLEVEL9K_STATUS_ERROR_FOREGROUND=167

  # Background jobs — muted teal
  typeset -g POWERLEVEL9K_BACKGROUND_JOBS_FOREGROUND=73

  # Virtualenv — warm sand
  typeset -g POWERLEVEL9K_VIRTUALENV_FOREGROUND=179
  typeset -g POWERLEVEL9K_VIRTUALENV_SHOW_WITH_PYENV=false
  typeset -g POWERLEVEL9K_VIRTUALENV_SHOW_PYTHON_VERSION=false

  # Node — sage green
  typeset -g POWERLEVEL9K_NODE_VERSION_FOREGROUND=108
  typeset -g POWERLEVEL9K_NODE_VERSION_PROJECT_ONLY=true

  # Rust — warm sand
  typeset -g POWERLEVEL9K_RUST_VERSION_FOREGROUND=179
  typeset -g POWERLEVEL9K_RUST_VERSION_PROJECT_ONLY=true

  # Context — only on SSH
  typeset -g POWERLEVEL9K_CONTEXT_{DEFAULT,SUDO}_CONTENT_EXPANSION=
  typeset -g POWERLEVEL9K_CONTEXT_ROOT_FOREGROUND=167
  typeset -g POWERLEVEL9K_CONTEXT_{REMOTE,REMOTE_SUDO}_CONTENT_EXPANSION='%n@%m'
  typeset -g POWERLEVEL9K_CONTEXT_{REMOTE,REMOTE_SUDO}_FOREGROUND=109
  typeset -g POWERLEVEL9K_CONTEXT_ROOT_TEMPLATE='%n@%m'

  (( ${#p10k_config_opts} )) && setopt ${p10k_config_opts[@]}
  'builtin' 'unset' 'p10k_config_opts'
}
