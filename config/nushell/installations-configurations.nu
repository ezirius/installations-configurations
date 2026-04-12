for path_entry in [
  "/usr/local/sbin"
  "/usr/local/bin"
  "/opt/homebrew/sbin"
  "/opt/homebrew/bin"
] {
  if ($env.path | any {|current| $current == $path_entry }) == false and ($path_entry | path exists) {
    $env.path = ($env.path | prepend $path_entry)
  }
}

$env.EDITOR = "micro"
$env.VISUAL = "micro"
$env.PAGER = "bat"
$env.BAT_CONFIG_PATH = ($"($__NUSHELL_DIR__ | path dirname)/bat/config")
$env.EZA_CONFIG_DIR = ($"($__NUSHELL_DIR__ | path dirname)/eza")
$env.STARSHIP_CONFIG = ($"($__NUSHELL_DIR__ | path dirname)/starship/starship.toml")
$env.ATUIN_CONFIG_DIR = ($"($__NUSHELL_DIR__ | path dirname)/atuin")
$env.FZF_DEFAULT_OPTS = "--height=60% --layout=reverse --border=rounded --info=inline --color=bg:#1a1b26,bg+:#24283b,fg:#c0caf5,fg+:#c0caf5,hl:#7aa2f7,hl+:#7dcfff,prompt:#7aa2f7,pointer:#bb9af7,marker:#9ece6a,spinner:#9ece6a,header:#e0af68"
$env._ZO_FZF_OPTS = "--height=60% --layout=reverse --border=rounded --info=inline --color=bg:#1a1b26,bg+:#24283b,fg:#c0caf5,fg+:#c0caf5,hl:#7aa2f7,hl+:#7dcfff,prompt:#7aa2f7,pointer:#bb9af7,marker:#9ece6a,spinner:#9ece6a,header:#e0af68"

source "__NUSHELL_DIR__/zoxide.nu"
source "__NUSHELL_DIR__/completions-jj.nu"
source "__NUSHELL_DIR__/atuin.nu"
source "__NUSHELL_DIR__/starship.nu"

$env.config = ($env.config
  | upsert show_banner false
  | upsert buffer_editor "micro"
  | upsert edit_mode vi
  | upsert history.file_format sqlite
  | upsert history.max_size 100_000
  | upsert history.sync_on_enter true)

$env.config = ($env.config | upsert hooks.env_change.PWD ((($env.config.hooks.env_change.PWD? | default []) | append { |_, _|
  if ((which direnv | length) > 0) {
    direnv export json | from json | default {} | load-env
  }
})))

alias cat = bat --paging=never --style=plain
alias j = jj
alias lg = lazygit
alias v = vim

def l [] {
  ^eza --group-directories-first --icons=auto
}

def ll [] {
  ^eza --all --long --header --git --group-directories-first --icons=auto
}

def la [] {
  ^eza --all --group-directories-first --icons=auto
}

def lt [] {
  ^eza --all --tree --level=3 --group-directories-first --icons=auto
}

def ff [] {
  ^fd --type file --hidden --follow --exclude .git
  | ^fzf --preview "bat --color=always --line-range=:300 {}"
}

def fcd [] {
  let target = (
    ^fd --type directory --hidden --follow --exclude .git
    | ^fzf
  )

  if $target != "" {
    cd $target
  }
}

def fe [] {
  let file = (ff)

  if $file != "" {
    ^micro $file
  }
}

def fh [] {
  let target = (
    history
    | get command
    | reverse
    | uniq
    | str join (char newline)
    | fzf
  )

  if $target != "" {
    commandline edit --replace $target
  }
}

def bj [filter?: string] {
  if ($filter | is-empty) {
    ^jq .
  } else {
    ^jq $filter
  }
}

def yj [filter?: string] {
  if ($filter | is-empty) {
    ^yq .
  } else {
    ^yq $filter
  }
}
