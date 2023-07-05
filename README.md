# SephoraScraper

## Research: Web scrapers

I searched Github for web scraping or headless browser libraries for Ruby. I
ultimately went with a library called "Ferrum" because it wasn't a wrapper
around Selenium, and used CDP directly, which would allow us to run arbitrary
JS, which should bypass fingerprint detection and allow reading of any network
request and any element on the page. Additionally, it can run chrome in "headed"
mode, which would prevent bot detection because an actual browser has an actual
fingerprint - there are no stubbed javascript values or headers. For example,
`navigator.webdriver` will always return false, there will be an actual screen
resolution, a real user agent (we may not want to overwrite the user agent
header with a headed browser, since that may trigger an abnormal fingerprint
that doesn't match the browser. Headers should all match those of a real user,
and if specific URLs are to be visited directly, we must set the "Referrer"
header to the previous page so it mimics user behavior. If we really wanted to
have a variable fingerprint, we could rotate the version of chrome that Ferrum
uses. Even better, we could try rotating browsers. If we have a legitimate
fingerprint, we should then focus on javascript-based bot detection. To defeat
this detection we could emulate real user mouse/keyboard behavior, send random
inputs, and use different browser window sizes. Bot/scraper detectors try to
determine if user behavior is "human" or not: for example, a scraper may lack
the "random" mouse movements that we sometimes make when reading a website, or
it may interact with elements on a page too quickly and too rigidly, or it may
scroll down too fast. Essentially we would want the scraping to send different
data to the bot detection code each time.

### 2. Browser fingerprinting

Bot detectors also rely on browser fingerprinting: this usually involves
checking the browser type, browser version, IP address, geolocation data, WebGL
information, screen resolution, DOM dimensions (can be determined using an
iframe), and available fonts, among many other things. On mobile devices, other
information like gyroscope and sensor data may be available.

### 3. What protection does Sephora use?

On sephora.com, heavily obfuscated javascript files are loaded, including
[this one](https://www.sephora.com/V2s28TSWEO64DuGwxhH252bAK20/1LXapct7uEE1/ChhnPnsWAg/S0/EWYEsSWgo),
which contains a variable named "bmak". In the javascript console, you can call
`bmak`, and it matches the "bmak" object that this
[example Akamai bypass](https://github.com/infecting/akamai/blob/master/akamai_1/bypass.js)
above stubs. Therefore Sephora.com uses Akamai's Bot Manager.

However, because this scraper uses a headed browser, we do not need to manually
overwrite any javascript variables loaded by the page.

Sephora also uses Akamai Image Manager to prevent direct access to its product
images. We can see this in the response headers of a product image request:

```json
{
  "date": "Tue, 04 Jul 2023 13:55:14 GMT",
  "strict-transport-security": "max-age=31536000",
  "last-modified": "Wed, 14 Jun 2023 02:22:45 GMT",
  "server": "Akamai Image Manager",
  "content-type": "image/webp",
  "cache-control": "no-transform, max-age=21600",
  "server-timing": "cdn-cache; desc=HIT, edge; dur=1, ak_p; desc=\"469021_388971212_846115625_7249_22446_42_0_-\";dur=1",
  "content-length": "5160",
  "expires": "Tue, 04 Jul 2023 19:55:14 GMT"
}
```

## Background (My thought process)

1. I found a way to operate a "non-headless" chrome via ruby, so I went as far
   as I could with that, thinking that scrapers don't necessarily need to be
   fast and that we could run a "non-headless" scraper on several VPS instances
   (Ubuntu desktops in AWS) on a schedule. These instances could each connect to
   the internet using different proxies.
   1. My thinking was that, since this script is not using a headless chrome
      driver, the scraping may appear close to actual user activity.
2. After pretty much completing every task, i felt my approach to bot detection
   was inadequate, so i started researching more. The google doc provided by
   Newness mentioned "undetected-chrome", which made me think that maybe I
   should have used Selenium after all...

   1. The ideas listed in the instructions were: mocking user agent, using
      proxies, and captcha detection and solving
   2. I also came up with sending random keyboard and mouse events, cookie
      fuzzing (could confuse the app, since marking modals as seen, or
      showing/hiding the support chat bubble depends on cookies or local
      storage)

## More Proxy ideas

1. Port the script to one that can run on android devices (Can have 100 android
   devices hooked up to SIM cards), which are behind <https://proxidize.com/>
   proxies. Can use Playwright to automate android browsers.

## Requirements

- sqlite3
- ruby (3.2.2, see `.ruby-version`)
- bundler

## Installation

1. `./run`

## Usage

Install and run `~./make_run`

Run `~./bin/scraper`

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run
`rake spec` to run the tests. You can also run `bin/console` for an interactive
prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Further ideas

- Run script on multiple VPS servers so that it can continue to run using a
  non-headless/headed chrome, which makes mimicing real user behavior easier
- Set `window.localStorage` so that `isFirstTimeChatMarketingMsg` is false,
  which should disable the chat popup
- Use real proxies
- Expand random movement to include random scrolling and smooth mouse moves,
  using unsmooth animation formulas
- Use random locations
- Test if Playwright would make the code any simpler (it also supports CDP )
- Consider headless-chrome, now that is apparently undetectable
  <https://antoinevastel.com/bot%20detection/2023/02/19/new-headless-chrome.html>
