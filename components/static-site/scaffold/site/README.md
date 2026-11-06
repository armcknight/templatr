# {{inputs.domain}}

The website at https://{{inputs.domain}}. Its sources are in this directory, and `make site build` writes it to `{{inputs.output}}/`, which `make site deploy` uploads. It is served from a private S3 bucket through CloudFront, with the certificate and the DNS records, all from one CloudFormation stack that `templatr bootstrap` makes.

Run these from the repository's root:

* `make site build` builds the site, and `make site serve` serves the build at `http://localhost:{{inputs.port}}`, as CloudFront serves it: a directory's address with a slash gets its `index.html`, one without redirects to the one with, and a page that does not exist gets `404.html`. `make site endserve` stops it.
* `make site deploy` uploads the build, clears CloudFront, and commits `DEPLOYED`, the commit that is live. Only the owner deploys, from a clean checkout. The commit is local: push it.
* `make site status` shows the bucket, the distribution and the certificate, and https://{{inputs.domain}}/DEPLOYED, what is live.
* `make site bust-cache PATHS="/ /index.html"` clears pages from CloudFront by hand, and `make site invalidations` shows whether a clear has finished.
* `make site stack` changes the hosting after a change to `component.mk`'s `STATIC_SITE_WITH_WWW` or `STATIC_SITE_PRICE_CLASS`, and `make site redirects` makes the stack of each old domain in `STATIC_SITE_REDIRECT_FROM`, which then redirects every address, with its www, to the same path here. Only the owner runs them.
* `brew bundle --file site/Brewfile` installs the tools these commands use.

## Before the first deploy

What a site needs before anyone sees it. `templatr check` checks the items marked with †.

**Pages**

- [ ] Every page has a `<title>` of its own, under 60 characters, with the site's name last, and a `<meta name="description">` of one or two sentences, under 160 characters. Search results show both.
- [ ] Every page has `<link rel="canonical" href="https://{{inputs.domain}}/…/">`, with the address the page should be found at: the directory form with the slash, never `index.html`.
- [ ] Every page has `<html lang="…">`, `<meta charset="utf-8">` and `<meta name="viewport" content="width=device-width, initial-scale=1">`.
- [ ] Every page has the Open Graph tags that a link preview reads: `og:type`, `og:site_name`, `og:title`, `og:description`, `og:url` (the canonical address) and `og:image`, a PNG or JPEG of 1200×630 pixels at an absolute `https://` address, with `og:image:width`, `og:image:height` and `og:image:alt`. Add `twitter:card` as `summary_large_image`, or `summary` for a square image. A page without an image of its own gets the site's.
- [ ] Headings are in order, one `<h1>` for each page, and every image has `alt` text.
- [ ] Structured data where it fits: a `<script type="application/ld+json">` with `WebSite` or `Person` on the home page, `BlogPosting` or `Article` on a post, with `datePublished` and `author`.
- [ ] The site works with JavaScript off, or has a `<noscript>` message. Crawlers read the HTML as it is served.

**Icons and colours**

- [ ] `/favicon.ico` or a `<link rel="icon">` to an SVG or PNG, and `<link rel="apple-touch-icon" href="/apple-touch-icon.png">` of 180×180 pixels. Check that the build copies them: a link to a file that is not in the output is the most common broken icon.
- [ ] `<meta name="theme-color">`, and `<meta name="color-scheme">` when the site has a dark mode.
- [ ] A `site.webmanifest` with the name, the icons and the colours, linked with `<link rel="manifest">`, when the site should be added to a home screen.

**Files every site has**

- [ ] † `404.html`, with the site's look, a link home and `<meta name="robots" content="noindex">`, kept out of the sitemap. CloudFront serves it, with a 404 status, for any address that has no file. Try it with `make site serve` and open `/nope`.
- [ ] † `robots.txt` with `User-agent: *`, `Allow: /` and `Sitemap: https://{{inputs.domain}}/sitemap.xml`. Add `Disallow` lines for the crawlers you do not want, such as `GPTBot`, `ClaudeBot`, `Google-Extended`, `CCBot` and `Bytespider` for AI training, with `Content-Signal: search=yes, ai-train=no` for the ones that read it.
- [ ] `sitemap.xml` with every page's canonical address: the `jekyll-sitemap` gem, Hugo's built-in sitemap, or a hand-written file for a site of a few pages.
- [ ] A feed, `feed.xml` or `atom.xml`, when the site has posts, linked from each page with `<link rel="alternate" type="application/rss+xml">`.
- [ ] A privacy page, when the site sets cookies, keeps anything in the browser or has analytics. Say so there, and link it from every page's footer.
- [ ] `humans.txt` or a colophon, if you like, with what the site is made with.

**Before you upload**

- [ ] `make site build`, then `make site serve`: every page, every link, a directory's address without its slash (`/blog` redirects to `/blog/`), and the 404 page.
- [ ] Check the links: `lychee {{inputs.output}}` (`brew install lychee`) finds the broken ones, inside the site and out.
- [ ] Images are no larger than their largest display size, compressed, and without EXIF data that gives away a location: `exiftool -all= <file>`, and ImageOptim or `squoosh`.
- [ ] Hashed assets: when the generator names files by their contents, as Vite does under `assets/`, put the directory in `STATIC_SITE_IMMUTABLE` in `component.mk`, so they are cached for a year.
- [ ] † The hosting stack is complete, `templatr check` passes, and the working tree is committed: `make site deploy` refuses uncommitted changes.

## Each deploy

1. `make site build`. A deploy uploads what the last build made, and does not build.
2. Commit everything. `make site deploy` refuses a dirty working tree.
3. `make site deploy`. It uploads the output with `--delete`, so a page that is no longer built is gone from the site; clears `/*` from CloudFront; writes `DEPLOYED` into the upload; then commits `DEPLOYED` here as `deploy(site): <commit>`.
4. Push the commit.
5. Open the site and compare https://{{inputs.domain}}/DEPLOYED with `git rev-parse HEAD~`. The stamp names the commit before the one that records it.
6. When a change is not visible: the invalidation is still running (`make site invalidations`), or your browser has a copy. Reload without the cache before you look further.
7. When a page's address changed, keep the old address with a page that links to the new one, or a `<meta http-equiv="refresh">` to it, and change the canonical links and the sitemap. The distribution has no redirects of its own.

## After the first deploy

One time, after the site answers at https://{{inputs.domain}}.

**Search engines**

- [ ] [Google Search Console](https://search.google.com/search-console): add the domain as a Domain property, verify it with the TXT record Google gives, added to the hosted zone in Route 53, then submit the sitemap under Sitemaps and ask for indexing of the home page under URL inspection. Come back in a week for the Pages report: what was indexed, and what was not and why.
- [ ] [Bing Webmaster Tools](https://www.bing.com/webmasters): import the site from Search Console, which verifies it and submits the sitemap in one step. Bing feeds DuckDuckGo and others.
- [ ] Check `https://{{inputs.domain}}/robots.txt` and `https://{{inputs.domain}}/sitemap.xml` in the browser: both answer, the sitemap's addresses are the canonical ones with `https://`, and none is a 404.

**Link previews**

- [ ] `opengraph.xyz`: paste the home page and one inner page, and look at the previews for Facebook, X, LinkedIn, Slack and Discord. A missing image usually means the `og:image` address is relative, or the file is not in the output.
- [ ] [Facebook's Sharing Debugger](https://developers.facebook.com/tools/debug/): paste each page whose tags changed and press "Scrape again", because Facebook keeps the first preview it saw. Also for Instagram and WhatsApp.
- [ ] [LinkedIn's Post Inspector](https://www.linkedin.com/post-inspector/) does the same for LinkedIn.
- [ ] Paste a link into a Slack or iMessage message to yourself; both show what a reader sees.

**Quality**

- [ ] [PageSpeed Insights](https://pagespeed.web.dev): the Lighthouse scores for performance, accessibility, best practices and SEO, on mobile and desktop. Fix what it names: image sizes, contrast, missing labels and tap targets.
- [ ] [validator.w3.org](https://validator.w3.org/nu/) on the home page and one of each kind of page: a crawler forgives less than a browser.
- [ ] [securityheaders.com](https://securityheaders.com): the distribution's managed policy gives an A; a Content-Security-Policy is the one header it does not set.
- [ ] [SSL Labs](https://www.ssllabs.com/ssltest/): the certificate and TLS 1.2 or later, an A.
- [ ] `curl -sI https://www.{{inputs.domain}}/` redirects to the apex when `with_www` is true, and `curl -sI http://{{inputs.domain}}/` redirects to HTTPS. `templatr check` checks both, and that each old domain in `redirect_from` redirects here.
- [ ] When an old domain redirects here, tell Search Console with its Change of Address tool, under the old domain's property, so that its ranking moves with the pages; keep the redirect for at least a year.

**Keep**

- [ ] Save the home page in the [Wayback Machine](https://web.archive.org/save), and again after a redesign.
- [ ] Watch the site: an uptime check of https://{{inputs.domain}}/DEPLOYED every few minutes from a free service, which also tells you when a deploy went wrong.
- [ ] Put the search console's address, the AWS account and the registrar in your password manager's note for the domain, with the renewal dates of the domain and the hosted zone. The certificate renews itself while the stack's validation records stay in the zone.
- [ ] Every few months: Search Console's Pages and Core Web Vitals reports, broken links with `lychee`, and the deploy log in `logs/` for a sync that did not finish.
