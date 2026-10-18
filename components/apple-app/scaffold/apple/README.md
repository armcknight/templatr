# {{inputs.app_name}}

The app, for {{inputs.platforms}}. Its Xcode project, Gemfile and fastlane/ are in this directory, and fastlane runs here. The one Xcode project builds the app for each platform in `APPLE_APP_PLATFORMS` in `component.mk`.

Run these from the repository's root:

* `make apple test` runs the tests for every platform, and `make apple <platform> test`, such as `make apple ios test`, for one.
* `make apple ios stage` builds an ad-hoc staging IPA. On a pull request, a `/build-staging` comment builds one in CI and posts an install link.
* `make apple <platform> deploy-beta`, such as `make apple mac deploy-beta`, cuts a release candidate from `apple/CHANGELOG.md` and uploads it to TestFlight for that platform. `make apple deploy-beta` cuts one release candidate and uploads it for every platform. Only the owner runs it, and `make apple patch`, `minor` and `major`.
* `brew bundle --file apple/Brewfile` installs the tools that these commands use, after `brew trust armcknight/tools`.
