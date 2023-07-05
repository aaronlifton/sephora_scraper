# SephoraScraper

## Requirements

- sqlite3
- ruby (3.2.2, see `.ruby-version`)
- bundler

## Installation

1. `./run`

## Usage

Install and run `~./run`

If you've already installed dependencies, run `~./bin/scraper` directly

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run
`rake spec` to run the tests. You can also run `bin/console` for an interactive
prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Research: Web scrapers

I searched Github for web scraping or headless browser libraries for Ruby, and
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

### 2. Research: Browser fingerprinting

Bot detectors also rely on browser fingerprinting: this usually involves
checking the browser type, browser version, IP address, geolocation data, WebGL
information, screen resolution, DOM dimensions (can be determined using an
iframe), and available fonts, among many other things. On mobile devices, other
information like gyroscope and sensor data may be available.

### 3. Research: What protection does Sephora use?

On sephora.com, heavily obfuscated javascript files are loaded, including
[this one](https://www.sephora.com/V2s28TSWEO64DuGwxhH252bAK20/1LXapct7uEE1/ChhnPnsWAg/S0/EWYEsSWgo),
which contains a variable named "bmak". In the javascript console, you can call
`bmak`, and it matches the "bmak" object that this
[example Akamai bypass](https://github.com/infecting/akamai/blob/master/akamai_1/bypass.js)
stubs. Therefore Sephora.com uses Akamai's Bot Manager. Looking at the bypass
code, you can see Akamai heavily obfuscates their code, which collects a very
thorough browser fingerprint.

However, because this scraper uses a real browser, we do not need to manually
overwrite any javascript variables loaded by the page. Bypasses can easily
become outdated as the source changes, and they rely on de-obfuscation, which
may not be possible in some cases.

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

## Proxy ideas

1. We could run this "non-headless" scraper on several VPS instances (Ubuntu
   desktops in AWS), connected to the internet via residential proxies, so they
   look like real user sessions. Windows S instances woulds. obably look more
   like real users. On a schedule, these instances would rotate proxies.
2. Port the script to one that can run on android devices (Can have 100 android
   devices hooked up to SIM cards), which are behind <https://proxidize.com/>
   proxies. Can use Playwright to automate android browsers.

## Further ideas

- Set `window.localStorage` so that `isFirstTimeChatMarketingMsg` is false,
  which might disable the chat popup. Try to disable login/signup modals by
  setting cookies oor values in local storage.
- Use residential proxies to appear more like real users. For ewxmaple, it's
  possible EC2 server IP addresses are recognizable.
- Expand random user inpuits to include random scrolling and smooth/rounded
  mouse moves using animation formulas rather than just moving the mouse up,
  down, left, and right.
- Use random server locations or randomize and mock locations
- Test if [Playwright](https://playwright.dev/) would make the code any simpler
  (it also supports CDP)
- Consider headless-chrome, now that is
  [apparently undetectable](https://antoinevastel.com/bot%20detection/2023/02/19/new-headless-chrome.html)
