# >>> installations-and-configurations homebrew path >>>
let brew_bin = "/var/folders/6z/d9fnfwts7dg2cr8vw0h5mk2r0000gn/T/tmp.7SGMsBIXip/fake-bin"
let brew_sbin = "/var/folders/6z/d9fnfwts7dg2cr8vw0h5mk2r0000gn/T/tmp.7SGMsBIXip/sbin"

if ($env.PATH | describe | str starts-with "list<") {
  if $brew_sbin not-in $env.PATH {
    $env.PATH = ($env.PATH | prepend $brew_sbin)
  }
  if $brew_bin not-in $env.PATH {
    $env.PATH = ($env.PATH | prepend $brew_bin)
  }
}
# <<< installations-and-configurations homebrew path <<<
