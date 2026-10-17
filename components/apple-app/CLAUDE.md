# apple-app

This project is an Apple app built with the `apple-app` component from [armcknight/templatr](https://github.com/armcknight/templatr). `.superlinear/components.toml` has the tag it is pinned to.

## Building and testing

* `make test`, or `bundle exec fastlane <platform> test`, runs the tests. CI runs the same lane on each pull request through `ios-ci.yml` from [armcknight/workflows](https://github.com/armcknight/workflows).
* `make stage`, or `bundle exec fastlane ios stage`, builds an ad-hoc IPA for staging. A person asks CI for a staging build of a pull request by commenting `/build-staging` on it; CI then posts an install link.
* `<platform>` is `ios`, `tvos` or `mac`. An iOS app's embedded watch app builds with it.

## Rules

* Never run `make deploy-beta` or the `beta` lane. They upload a build to TestFlight, which only the owner does, by hand.
* Never change the version or the build number: do not run `make patch`, `minor` or `major`, and do not edit `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION`. `make deploy-beta` raises the build number in the xcconfig and tags the commit. Each `Info.plist`'s `CFBundleVersion` must stay `$(CURRENT_PROJECT_VERSION)`.
* Add each change that testers can see to `CHANGELOG.md`, under Unreleased. At the next TestFlight upload, those entries become TestFlight's "What to Test" text, so write them for testers.
* The `test`, `stage` and `beta` lanes come from the templatr repository; `fastlane/Fastfile` imports them with `import_from_git`. Do not define lanes with those names in this project, and do not copy the shared lanes into it. To change them, change the templatr repository and move this project to its new tag.
* Settings for the shared lanes are the `APPLE_APP_*` values at the top of `fastlane/Fastfile`.
* The CI workflows in `.github/workflows/` call armcknight/workflows at its major tag. Do not point them at `main`.
* Signing uses fastlane match, read-only. Do not create or change certificates or profiles.
* Never print, log or commit a secret's value. The secrets are named in the README's "How this project is built" section.

## Further reading

* [TestFlight builds](https://github.com/armcknight/superlinear/blob/main/docs/builds.md#testflight)
* [Build numbers](https://github.com/armcknight/superlinear/blob/main/docs/builds.md#build-numbers)
