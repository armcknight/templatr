# What this repository shells out to, for the Makefile targets, `templatr`
# itself, and the agents superlinear runs here. Install it all with `make init`.
#
# Not covered here: macOS 14+, and the Swift 6 toolchain that comes with Xcode.
# What a bootstrapped project needs, such as fastlane, xcodegen or the Supabase
# CLI, is in each component's scaffold Brewfile, not here.
#
# Two of these taps are third-party. Homebrew refuses to load formulae and casks
# from untrusted taps, and `brew bundle` aborts on the first one it meets
# without installing anything at all — so `make init` trusts them before it runs.

# vrsn, prepare-release and prepare-github-release: `make patch`, `make deploy`
# and the templates-* targets. Needs 5.1.0 or later, for --tag-prefix; a cask
# cannot pin a minimum, so `brew upgrade`.
tap "armcknight/tools"
cask "armcknight/tools/tools"

# `templatr bootstrap` reads and sets a project's secrets with gh, and the
# github-repo component checks the repository's settings with it.
brew "gh"

# `op`: `templatr bootstrap` reads secrets kept in 1Password with it.
cask "1password-cli"

# `make links`: the same check CI's links job runs.
brew "lychee"

# the agents' commands shell out to these once the agent runs
tap "dorkitude/linctl"
brew "dorkitude/linctl/linctl" # read and update Linear issues
brew "direnv"                  # supplies LINCTL_API_KEY from .envrc to linctl and to the linear-workspace steps
