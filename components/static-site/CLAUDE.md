# static-site

This project is a static website, served from an S3 bucket through CloudFront, with the `static-site` component from [armcknight/templatr](https://github.com/armcknight/templatr). `.templatr.toml` has the tag it is pinned to, and the component's inputs: the `domain`, the `build` command and the `output` directory.

The site's files are in `site/`: the generator's sources, its output directory, `component.mk`, `DEPLOYED` and the site's own `README.md`, which has the checklist of what the site needs before and after a deploy. The `make site …` commands run from the repository's root.

## Building and serving

* `make site build` runs the build command in `site/`, and writes the site into its output directory. `make site serve` serves that output at `http://localhost:<port>` as the distribution serves it, with directory indexes and the 404 page; it serves the build, not the sources, so build again after a change. `make site endserve` stops it.
* A page's address is its directory with a slash, such as `/blog/`: the distribution gives it the directory's `index.html`, and redirects `/blog` to `/blog/`, as `www.<domain>` redirects to the domain. Link to the form with the slash, and put it in `<link rel="canonical">`.
* Every page needs a title, a description, Open Graph tags and a canonical link, and the site needs `404.html`, `robots.txt` and a sitemap: `site/README.md` lists them, and `templatr check` checks for the 404 page and the robots file.

## Publishing

* A deploy uploads what `make site build` last made: build first. `make site deploy` refuses a working tree with uncommitted changes, so that the commit it records is what was uploaded.
* `site/DEPLOYED` is the commit and the time of the last deploy, and `https://<domain>/DEPLOYED` is the same file on the live site. The deploy commits it alone, as `deploy(site): <commit>`, and that commit is local until it is pushed. Never edit the stamp by hand.
* Pages are uploaded with `Cache-Control: no-cache`, and each deploy clears `/*` from CloudFront, so a deployed change is visible as soon as the invalidation finishes. When it is not, the browser has a copy: reload without the cache, and compare `https://<domain>/DEPLOYED` with the commit you expect.
* `make site bust-cache PATHS="/ /index.html"` clears paths by hand. A directory's address and its `index.html` are separate cache keys, so clear both; paths are separated by spaces, never commas.

## Rules

* Never deploy. Do not run `make site deploy`, `make site stack`, `aws s3 sync`, `aws cloudformation deploy` or `aws cloudfront create-invalidation`. Only the owner publishes, by hand.
* Do not change `site/component.mk`'s `STATIC_SITE_DOMAIN`, `STATIC_SITE_WITH_WWW` or `STATIC_SITE_PRICE_CLASS` without being asked: each changes the stack, the certificate or what it costs. The bucket, the distribution and the DNS records come from the component's CloudFormation template; `templatr check` compares the stack with it. Do not change them in the AWS console.
* The `static-site-*` targets come from the templatr repository; `site/component.mk` includes them from `make/static-site.mk`, and the root Makefile includes `site/component.mk`. Do not copy them into this project. To change them, change the templatr repository and move this project to its new tag.
* Put each page's address in its canonical link and every address in the sitemap, and keep `404.html` out of the sitemap, with `noindex`. When a page moves, keep the old address with a page that links to the new one, or a meta refresh to it: the distribution has no redirects of its own.
* The AWS profile in `site/component.mk` has the owner's credentials. Never print, log or commit a key, and never put credentials in a file that git tracks.

## Further reading

* [Steps that need a person](https://github.com/armcknight/superlinear/blob/main/docs/bootstrap.md#needs-human-steps)
* [The release rule](https://github.com/armcknight/superlinear/blob/main/docs/builds.md#release-rule)
