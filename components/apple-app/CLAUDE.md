# apple-app

This project is an Apple app built with the `apple-app` component from [armcknight/templatr](https://github.com/armcknight/templatr). `.templatr.toml` has the tag it is pinned to.

The app's files are in `apple/`: the Xcode project, the Gemfile, `fastlane/` and the app's `CHANGELOG.md`. fastlane and `bundle exec` run there, as `cd apple && bundle exec fastlane …`. The `make apple …` commands run from the repository's root.

The one Xcode project in `apple/` builds the app for each platform in `APPLE_APP_PLATFORMS` in `apple/component.mk`: `ios`, `tvos` or `mac`, as fastlane names them. A command for one platform names it after `apple`, as `make apple ios test`; a command without a platform is for every platform.

## Building and testing

* `make apple <platform> test`, or `bundle exec fastlane <platform> test` in `apple/`, runs the tests for one platform. `make apple test` runs them for every platform. CI runs the `ios` lane on each pull request through `ios-ci.yml` from [armcknight/workflows](https://github.com/armcknight/workflows).
* `make apple ios stage`, or `bundle exec fastlane ios stage` in `apple/`, builds an ad-hoc IPA for staging. Only `ios` has a staging build. A person asks CI for a staging build of a pull request by commenting `/build-staging` on it; CI then posts an install link.
* An iOS app's embedded watch app builds with `ios`.

## Rules

* Never run `make apple deploy-beta`, `make apple <platform> deploy-beta` or a `beta` lane. They upload a build to TestFlight, which only the owner does, by hand.
* Never change the version or the build number: do not run `make apple patch`, `minor` or `major`, and do not edit `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION`. A deploy-beta command raises the build number in the xcconfig and tags the commit. Each `Info.plist`'s `CFBundleVersion` must stay `$(CURRENT_PROJECT_VERSION)`.
* Add each change that testers can see to `apple/CHANGELOG.md`, under Unreleased. At the next TestFlight upload, those entries become TestFlight's "What to Test" text, so write them for testers.
* The `test`, `stage` and `beta` lanes come from the templatr repository; `apple/fastlane/Fastfile` imports them with `import_from_git`. Do not define lanes with those names in this project, and do not copy the shared lanes into it. To change them, change the templatr repository and move this project to its new tag.
* Settings for the shared lanes are the `APPLE_APP_*` values at the top of `apple/fastlane/Fastfile`.
* The CI workflows, `.github/workflows/apple-app-*.yml`, call armcknight/workflows at its major tag, with `working-directory: apple`. Do not point them at `main`.
* Signing uses fastlane match, read-only. Do not create or change certificates or profiles.
* Never print, log or commit a secret's value. The secrets are named in the "How this project is built" section of the root `README.md`, not `apple/README.md`.

## Further reading

* [TestFlight builds](https://github.com/armcknight/superlinear/blob/main/docs/builds.md#testflight)
* [Build numbers](https://github.com/armcknight/superlinear/blob/main/docs/builds.md#build-numbers)
