# macOS iTerm2 setup

## Why this setup installs iTerm2

This repository installs `iTerm2` instead of relying on `Terminal.app` for the OpenCode workflow on macOS.

The practical issues seen with `Terminal.app` were:

- copying from OpenCode required pressing `Cmd+R` before copy would work as expected
- `Shift+Enter` did not insert a new line in OpenCode

This setup uses `iTerm2` because it provides a better path for the OpenCode workflow:

- `iTerm2` supports terminal-controlled clipboard access, which OpenCode and related shell utilities can use through standard escape-sequence behaviour
- this setup manages `AllowClipboardAccess=true`, which enables `Applications in terminal may access clipboard`
- in practice, moving to `iTerm2` resolved both of the issues above: copy no longer depended on pressing `Cmd+R`, and `Shift+Enter` worked again for new lines

`Terminal.app` is still usable, but it is not the managed default for this workflow because the OpenCode experience there was worse around copy and input behaviour.

## Managed settings

The repository currently manages these iTerm2 preferences from `config/iterm2/defaults.conf`:

- `AllowClipboardAccess=true`

That setting is applied by `scripts/macos/iterm2-configure` with macOS `defaults` under the `com.googlecode.iterm2` preference domain. This repository directly manages that clipboard setting in iTerm2; the broader improvement in OpenCode behaviour comes from using iTerm2 for this workflow instead of `Terminal.app`.

## Setup order

Run either:

1. `scripts/macos/brew-install`
2. `scripts/macos/brewfile-install`
3. `scripts/macos/brew-upgrade`
4. `scripts/macos/iterm2-configure`

or run `scripts/macos/bootstrap` to perform the full managed macOS setup-and-upgrade flow.

## Verification

Run `tests/macos/test-all.sh` to execute the repository shell checks in one command.
