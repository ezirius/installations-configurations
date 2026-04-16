#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_FILE="$ROOT/scripts/macos/podman-configure"
HELPERS="$ROOT/lib/test/runtime-helpers.sh"
TMPDIR="$(mktemp -d)"
MOCK_BIN="$TMPDIR/bin"
STATE_DIR="$TMPDIR/state"
HOME_DIR="$TMPDIR/home"
mkdir -p "$MOCK_BIN" "$STATE_DIR" "$HOME_DIR/Documents/Ezirius/Systems/Installations and Configurations/Computers" "$HOME_DIR/.config/containers"
trap 'rm -rf "$TMPDIR"' EXIT
source "$HELPERS"

cat > "$MOCK_BIN/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF

cat > "$MOCK_BIN/scutil" <<'EOF'
#!/usr/bin/env bash
printf 'Maldoria\n'
EOF

cat > "$MOCK_BIN/xcode-select" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == -p ]]
printf '/Library/Developer/CommandLineTools\n'
EOF

cat > "$MOCK_BIN/brew" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  shellenv) ;;
  --prefix) printf '/opt/homebrew\n' ;;
  *) exit 0 ;;
esac
EOF

cat > "$MOCK_BIN/python3" <<'EOF'
#!/usr/bin/env perl
use strict;
use warnings;
use JSON::PP;

my $program = do { local $/; <STDIN> };

if (@ARGV && $ARGV[0] eq '-') {
  shift @ARGV;
}

sub read_file {
  my ($path) = @_;
  open my $fh, '<', $path or exit 1;
  local $/;
  return <$fh>;
}

if ($program =~ /configparser/ && @ARGV >= 2) {
  my ($config_file, $key) = @ARGV;
  my $contents = read_file($config_file);
  my $in_machine = 0;
  for my $line (split /\n/, $contents) {
    $line =~ s/\r$//;
    if ($line =~ /^\s*\[(.+)\]\s*$/) {
      $in_machine = $1 eq 'machine';
      next;
    }
    next unless $in_machine;
    next if $line =~ /^\s*[#;]/;
    if ($line =~ /^\s*\Q$key\E\s*=\s*(.*?)\s*$/) {
      print "$1\n";
      exit 0;
    }
  }
  exit 1;
}

if ($program =~ /json\.loads/ && @ARGV >= 1) {
  my $decoded = eval { decode_json($ARGV[0]) };
  exit 1 if $@;

  my $data = $decoded;
  if (ref($data) eq 'ARRAY') {
    exit 1 if !@$data;
    $data = $data->[0];
  }
  exit 1 if ref($data) ne 'HASH';

  if ($program =~ /summary = \{/s) {
    my $state = $data->{State};
    my $running;
    if (ref($state) eq 'HASH') {
      $running = $state->{Running};
    } elsif (!ref($state) && defined $state) {
      $running = lc($state) eq 'running' ? JSON::PP::true : JSON::PP::false;
    } else {
      $running = undef;
    }

    my %summary;
    if ($program =~ /"running"/) {
      $summary{running} = $running;
    }
    $summary{cpus} = exists $data->{cpus} ? $data->{cpus} : $data->{CPUs};
    $summary{memory} = exists $data->{memory} ? $data->{memory} : $data->{Memory};
    $summary{disk_size} = exists $data->{disk_size} ? $data->{disk_size} : exists $data->{diskSize} ? $data->{diskSize} : $data->{DiskSize};
    $summary{rootful} = exists $data->{rootful} ? $data->{rootful} : $data->{Rootful};
    print encode_json(\%summary), "\n";
    exit 0;
  }

  my $state = $data->{State};
  if (ref($state) eq 'HASH' && ref($state->{Running}) eq '') {
    exit($state->{Running} ? 0 : 1);
  }
  if (!ref($state) && defined $state) {
    exit(lc($state) eq 'running' ? 0 : 1);
  }
  exit 1;
}

if ($program =~ /summary = \{/s && @ARGV >= 4) {
  my %summary = (
    cpus => int($ARGV[0]),
    memory => int($ARGV[1]),
    disk_size => int($ARGV[2]),
    rootful => lc($ARGV[3]) eq 'true' ? JSON::PP::true : JSON::PP::false,
  );
  print encode_json(\%summary), "\n";
  exit 0;
}

exit 1;
EOF

cat > "$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${STATE_DIR:?}"
printf '%s\n' "$*" >> "$STATE_DIR/podman.log"
case "$1" in
  machine)
    case "$2" in
      inspect)
        if [[ -f "$STATE_DIR/machine.exists" ]]; then
          printf '[{"State":{"Running":false}}]\n'
          exit 0
        fi
        exit 1
        ;;
      set)
        if [[ "${3:-}" == --help ]]; then
          printf '%s\n' '--cpus --memory --disk-size --rootful'
          exit 0
        fi
        ;;
      init)
        if [[ "$3" != --cpus || "$5" != --memory || "$7" != --disk-size || "$9" != --rootful ]]; then
          printf 'missing init flags\n' >&2
          exit 1
        fi
        : > "$STATE_DIR/machine.exists"
        ;;
      start)
        ;;
      *) exit 1 ;;
    esac
    ;;
  info)
    printf '{}\n'
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/scutil" "$MOCK_BIN/xcode-select" "$MOCK_BIN/brew" "$MOCK_BIN/python3" "$MOCK_BIN/podman"

PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >/dev/null

test -f "$HOME_DIR/.config/containers/containers.conf"
cmp "$ROOT/config/podman/containers.conf" "$HOME_DIR/.config/containers/containers.conf"
assert_contains "$STATE_DIR/podman.log" 'machine init --cpus 4 --memory 8192 --disk-size 60 --rootful false podman-machine-default' 'podman machine is initialised with configured settings'
assert_contains "$STATE_DIR/podman.log" 'machine start podman-machine-default' 'podman machine is started'

STATE_DIR="$TMPDIR/state-existing"
mkdir -p "$STATE_DIR"
cat > "$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${STATE_DIR:?}"
printf '%s\n' "$*" >> "$STATE_DIR/podman.log"
case "$1" in
  machine)
    case "$2" in
      inspect)
        if [[ -f "$STATE_DIR/after-update" ]]; then
          printf '[{"State":"running","cpus":4,"memory":8192,"diskSize":60,"rootful":false}]\n'
        else
          printf '[{"State":"running","cpus":2,"memory":8192,"diskSize":60,"rootful":false}]\n'
        fi
        ;;
      set)
        if [[ "${3:-}" == --help ]]; then
          printf '%s\n' '--cpus --memory --disk-size --rootful'
          exit 0
        fi
        if [[ "$3" == --cpus || "$3" == --memory || "$3" == --disk-size || "$3" == --rootful ]]; then
          : > "$STATE_DIR/after-update"
        fi
        ;;
      stop)
        ;;
      start)
        ;;
      *) exit 1 ;;
    esac
    ;;
  info)
    if [[ -f "$STATE_DIR/after-update" ]]; then
      printf '{}\n'
    else
      exit 1
    fi
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$MOCK_BIN/podman"
printf 'y\n' | PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >"$STATE_DIR/out"
assert_contains "$STATE_DIR/podman.log" 'machine set --cpus 4 podman-machine-default' 'approved podman machine setting changes are applied'
assert_not_contains "$STATE_DIR/podman.log" 'machine set --memory 8192 podman-machine-default' 'unchanged podman memory setting is not reapplied'
assert_not_contains "$STATE_DIR/podman.log" 'machine set --disk-size 60 podman-machine-default' 'unchanged podman disk setting is not reapplied'
assert_not_contains "$STATE_DIR/podman.log" 'machine set --rootful false podman-machine-default' 'unchanged podman rootful setting is not reapplied'
assert_contains "$STATE_DIR/podman.log" 'machine stop podman-machine-default' 'running podman machine is stopped before applying mutable settings'
assert_contains "$STATE_DIR/podman.log" 'machine start podman-machine-default' 'running podman machine is restarted after applying mutable settings'

STATE_DIR="$TMPDIR/state-declined"
mkdir -p "$STATE_DIR"
cat > "$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${STATE_DIR:?}"
printf '%s\n' "$*" >> "$STATE_DIR/podman.log"
case "$1" in
  machine)
    case "$2" in
      inspect)
        printf '[{"State":"running","cpus":2,"memory":4096,"diskSize":60,"rootful":true}]\n'
        ;;
      set)
        if [[ "${3:-}" == --help ]]; then
          printf '%s\n' '--cpus --memory --disk-size --rootful'
          exit 0
        fi
        ;;
      stop|start)
        ;;
      *) exit 1 ;;
    esac
    ;;
  info)
    printf '{}\n'
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$MOCK_BIN/podman"
printf 'n\n' | PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >"$STATE_DIR/out"
assert_not_contains "$STATE_DIR/podman.log" 'machine stop podman-machine-default' 'declined approval does not stop running podman machine'
assert_not_contains "$STATE_DIR/podman.log" 'machine set --cpus 4 podman-machine-default' 'declined approval does not apply podman cpu settings'
assert_not_contains "$STATE_DIR/podman.log" 'machine start podman-machine-default' 'declined approval does not restart podman machine'
assert_contains "$STATE_DIR/out" 'Podman machine reconciliation bypassed by user' 'declined approval reports that podman reconciliation was bypassed'
assert_contains "$STATE_DIR/out" 'cpus: 2 -> 4' 'declined approval reports differing podman cpu config'
assert_contains "$STATE_DIR/out" 'memory: 4096 -> 8192' 'declined approval reports differing podman memory config'
assert_contains "$STATE_DIR/out" 'rootful: true -> false' 'declined approval reports differing podman rootful config'

STATE_DIR="$TMPDIR/state-noop"
mkdir -p "$STATE_DIR"
cat > "$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${STATE_DIR:?}"
printf '%s\n' "$*" >> "$STATE_DIR/podman.log"
case "$1" in
  machine)
    case "$2" in
      inspect)
        printf '[{"State":{"Running":false},"cpus":4,"memory":8192,"diskSize":60,"rootful":false}]\n'
        ;;
      set)
        if [[ "${3:-}" == --help ]]; then
          printf '%s\n' '--cpus --memory --disk-size --rootful'
          exit 0
        fi
        ;;
      start|stop)
        printf 'unexpected lifecycle action\n' >&2
        exit 1
        ;;
      *) exit 1 ;;
    esac
    ;;
  info)
    printf '{}\n'
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$MOCK_BIN/podman"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >/dev/null
if grep -Fq -- 'machine start podman-machine-default' "$STATE_DIR/podman.log" || grep -Fq -- 'machine stop podman-machine-default' "$STATE_DIR/podman.log"; then
  printf 'assertion failed: existing healthy podman machine should not be restarted when unchanged machine matches 8192 memory and 60 disk settings\n' >&2
  exit 1
fi

STATE_DIR="$TMPDIR/state-running-noop"
mkdir -p "$STATE_DIR"
cat > "$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${STATE_DIR:?}"
printf '%s\n' "$*" >> "$STATE_DIR/podman.log"
case "$1" in
  machine)
    case "$2" in
      inspect)
        printf '[{"State":{"Running":true},"cpus":4,"memory":8192,"diskSize":60,"rootful":false}]\n'
        ;;
      set)
        if [[ "${3:-}" == --help ]]; then
          printf '%s\n' '--cpus --memory --disk-size --rootful'
          exit 0
        fi
        ;;
      start|stop)
        printf 'unexpected lifecycle action\n' >&2
        exit 1
        ;;
      *) exit 1 ;;
    esac
    ;;
  info)
    printf '{}\n'
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$MOCK_BIN/podman"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >/dev/null
assert_not_contains "$STATE_DIR/podman.log" 'machine stop podman-machine-default' 'running unchanged machine should not be stopped before applying settings'
assert_not_contains "$STATE_DIR/podman.log" 'machine start podman-machine-default' 'running unchanged machine should not be restarted after applying settings'

STATE_DIR="$TMPDIR/state-noop-start"
mkdir -p "$STATE_DIR"
cat > "$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${STATE_DIR:?}"
printf '%s\n' "$*" >> "$STATE_DIR/podman.log"
case "$1" in
  machine)
    case "$2" in
      inspect)
        printf '[{"State":{"Running":false},"cpus":4,"memory":8192,"diskSize":60,"rootful":false}]\n'
        ;;
      set)
        if [[ "${3:-}" == --help ]]; then
          printf '%s\n' '--cpus --memory --disk-size --rootful'
          exit 0
        fi
        ;;
      start)
        ;;
      stop)
        printf 'unexpected stop\n' >&2
        exit 1
        ;;
      *) exit 1 ;;
    esac
    ;;
  info)
    if [[ -f "$STATE_DIR/started.flag" ]]; then
      printf '{}\n'
    else
      : > "$STATE_DIR/started.flag"
      exit 1
    fi
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$MOCK_BIN/podman"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >/dev/null
assert_contains "$STATE_DIR/podman.log" 'machine start podman-machine-default' 'podman-configure starts an unchanged machine when podman info still fails'

STATE_DIR="$TMPDIR/state-irrelevant"
mkdir -p "$STATE_DIR"
cat > "$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${STATE_DIR:?}"
printf '%s\n' "$*" >> "$STATE_DIR/podman.log"
case "$1" in
  machine)
    case "$2" in
      inspect)
        if [[ -f "$STATE_DIR/second-inspect" ]]; then
          printf '[{"State":{"Running":false},"cpus":4,"memory":8192,"diskSize":60,"rootful":false,"LastUp":"later"}]\n'
        else
          printf '[{"State":{"Running":false},"cpus":4,"memory":8192,"diskSize":60,"rootful":false,"LastUp":"earlier"}]\n'
          : > "$STATE_DIR/second-inspect"
        fi
        ;;
      set)
        if [[ "${3:-}" == --help ]]; then
          printf '%s\n' '--cpus --memory --disk-size --rootful'
          exit 0
        fi
        ;;
      start|stop)
        printf 'unexpected lifecycle action\n' >&2
        exit 1
        ;;
      *) exit 1 ;;
    esac
    ;;
  info)
    printf '{}\n'
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$MOCK_BIN/podman"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >/dev/null
assert_not_contains "$STATE_DIR/podman.log" 'machine stop podman-machine-default' 'irrelevant inspect-field changes should not trigger machine stop'
assert_not_contains "$STATE_DIR/podman.log" 'machine start podman-machine-default' 'irrelevant inspect-field changes should not trigger machine restart'

STATE_DIR="$TMPDIR/state-unsupported"
mkdir -p "$STATE_DIR"
cat > "$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${STATE_DIR:?}"
printf '%s\n' "$*" >> "$STATE_DIR/podman.log"
case "$1" in
  machine)
    case "$2" in
      inspect)
        printf '[{"State":{"Running":true},"cpus":2}]\n'
        ;;
      set)
        if [[ "${3:-}" == --help ]]; then
          printf '%s\n' '--cpus --memory'
          exit 0
        fi
        ;;
      stop)
        printf 'unsupported settings should be rejected before stopping\n' >&2
        exit 1
        ;;
      *) exit 1 ;;
    esac
    ;;
  info)
    printf '{}\n'
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$MOCK_BIN/podman"
if printf 'y\n' | PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >"$STATE_DIR/unsupported.out" 2>&1; then
  printf 'assertion failed: podman-configure should fail when a required machine set flag is unsupported\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/unsupported.out" 'does not support required machine setting' 'podman-configure reports unsupported required settings clearly'
assert_not_contains "$STATE_DIR/unsupported.out" 'unsupported settings should be rejected before stopping' 'podman-configure validates unsupported settings before stopping the machine'

STATE_DIR="$TMPDIR/state-disk-grow"
mkdir -p "$STATE_DIR"
cat > "$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${STATE_DIR:?}"
printf '%s\n' "$*" >> "$STATE_DIR/podman.log"
case "$1" in
  machine)
    case "$2" in
      inspect)
        if [[ -f "$STATE_DIR/after-update" ]]; then
          printf '[{"State":{"Running":false},"cpus":4,"memory":8192,"diskSize":60,"rootful":false}]\n'
        else
          printf '[{"State":{"Running":false},"cpus":4,"memory":8192,"diskSize":40,"rootful":false}]\n'
        fi
        ;;
      set)
        if [[ "${3:-}" == --help ]]; then
          printf '%s\n' '--cpus --memory --disk-size --rootful'
          exit 0
        fi
        if [[ "$3" == --disk-size && "$4" == 60 ]]; then
          : > "$STATE_DIR/after-update"
        fi
        ;;
      start|stop)
        printf 'unexpected lifecycle action\n' >&2
        exit 1
        ;;
      *) exit 1 ;;
    esac
    ;;
  info)
    printf '{}\n'
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$MOCK_BIN/podman"
printf 'y\n' | PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >"$STATE_DIR/out"
assert_contains "$STATE_DIR/podman.log" 'machine set --disk-size 60 podman-machine-default' 'smaller existing podman disk grows to the managed size'

STATE_DIR="$TMPDIR/state-disk-shrink"
mkdir -p "$STATE_DIR"
cat > "$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${STATE_DIR:?}"
printf '%s\n' "$*" >> "$STATE_DIR/podman.log"
case "$1" in
  machine)
    case "$2" in
      inspect)
        printf '[{"State":{"Running":false},"cpus":4,"memory":8192,"diskSize":80,"rootful":false}]\n'
        ;;
      set)
        if [[ "${3:-}" == --help ]]; then
          printf '%s\n' '--cpus --memory --disk-size --rootful'
          exit 0
        fi
        ;;
      start|stop)
        printf 'unexpected lifecycle action\n' >&2
        exit 1
        ;;
      *) exit 1 ;;
    esac
    ;;
  info)
    printf '{}\n'
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$MOCK_BIN/podman"
printf 'y\n' | PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >"$STATE_DIR/out"
assert_not_contains "$STATE_DIR/podman.log" 'machine set --disk-size 60 podman-machine-default' 'larger existing podman disk is not shrunk'
assert_contains "$STATE_DIR/out" 'disk_size: 80 -> 60 cannot be applied automatically' 'podman-configure reports managed disk shrink drift clearly'

STATE_DIR="$TMPDIR/state-custom-name"
mkdir -p "$STATE_DIR"
cat > "$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${STATE_DIR:?}"
printf '%s\n' "$*" >> "$STATE_DIR/podman.log"
case "$1" in
  machine)
    case "$2" in
      inspect) exit 1 ;;
      set)
        if [[ "${3:-}" == --help ]]; then
          printf '%s\n' '--cpus --memory --disk-size --rootful'
          exit 0
        fi
        ;;
      init|start) ;;
      *) exit 1 ;;
    esac
    ;;
  info)
    printf '{}\n'
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$MOCK_BIN/podman"
PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" custom-machine >/dev/null
assert_contains "$STATE_DIR/podman.log" 'machine init --cpus 4 --memory 8192 --disk-size 60 --rootful false custom-machine' 'podman-configure honours explicit machine names'

STATE_DIR="$TMPDIR/state-bad-inspect"
mkdir -p "$STATE_DIR"
cat > "$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${STATE_DIR:?}"
printf '%s\n' "$*" >> "$STATE_DIR/podman.log"
case "$1" in
  machine)
    case "$2" in
      inspect)
        printf 'not-json\n'
        ;;
      set)
        if [[ "${3:-}" == --help ]]; then
          printf '%s\n' '--cpus --memory'
          exit 0
        fi
        ;;
      *) exit 1 ;;
    esac
    ;;
  info)
    printf '{}\n'
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$MOCK_BIN/podman"
if PATH="$MOCK_BIN:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" STATE_DIR="$STATE_DIR" "$SCRIPT_FILE" >/dev/null 2>"$STATE_DIR/bad.err"; then
  printf 'assertion failed: podman-configure should fail on malformed machine inspect data\n' >&2
  exit 1
fi

echo "Podman machine runtime checks passed"
