# {{inputs.app_name}}

The app. Its Xcode project, Gemfile and fastlane/ are in this directory, and fastlane runs here.

Run these from the repository's root:

* `make apple test` runs the tests.
* `make apple stage` builds an ad-hoc staging IPA. On a pull request, a `/build-staging` comment builds one in CI and posts an install link.
* `make apple deploy-beta` cuts a release candidate from `apple/CHANGELOG.md` and uploads it to TestFlight. Only the owner runs it, and `make apple patch`, `minor` and `major`.
* `brew bundle --file apple/Brewfile` installs the tools that these commands use, after `brew trust armcknight/tools`.
