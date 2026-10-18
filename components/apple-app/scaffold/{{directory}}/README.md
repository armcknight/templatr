# {{inputs.app_name}}

The app. Its Xcode project, Gemfile and fastlane/ are in this directory, and fastlane runs here.

Run these from the repository's root:

* `make {{directory}} test` runs the tests.
* `make {{directory}} stage` builds an ad-hoc staging IPA. On a pull request, a `/build-staging` comment builds one in CI and posts an install link.
* `make {{directory}} deploy-beta` cuts a release candidate from `{{directory}}/CHANGELOG.md` and uploads it to TestFlight. Only the owner runs it, and `make {{directory}} patch`, `minor` and `major`.
* `brew bundle --file {{directory}}/Brewfile` installs the tools that these commands use, after `brew trust armcknight/tools`.
