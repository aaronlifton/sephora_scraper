# frozen_string_literal: true
module SephoraScraper
  module Scrapers
    class Util
      class << self
        def settings
          @settings ||= Setting.last
        end

        # If the script errors out, we store the error message in the settings
        # table. By also storing browser fingerprints in the settings table, we
        # can determine which fingerprints lead to unsuccessfl scraping
        # attempts.
        #
        # def get_fingerprint(browser)
        #   browser_plugins = browser.evaluate <<~JS
        #    window.getFingerprint() // some function that returns a browser fingerprint object as a json string
        #   JS
        # end

        # Create the first setting, or increment the rotating proxy and user agent.
        def initialize_settings
          return Setting.create(proxy_index: 0, user_agent_index: 0) if settings.nil?

          new_user_agent_index = settings.user_agent_index + 1
          new_user_agent_index = 0 if new_user_agent_index > max_user_agent_index
          new_proxy_index = settings.proxy_index + 1
          new_proxy_index = 0 if new_proxy_index > max_proxy_index
          Setting.create(proxy_index: new_proxy_index, user_agent_index: new_user_agent_index)
        end

        def random_mouse_move(browser)
          (0..10).to_a.sample do |x|
            y = (0..10).to_a.sample
            browser.mouse.move(x:, y:, steps: (3..5).to_a.sample)
          end
          puts 'Random mouse movement...'
        end

        def random_keyboard_event(browser)
          3.times do
            key = ('a'..'z').to_a.sample
            browser.keyboard.down(key)
            browser.keyboard.up(key)
          end
          puts 'Random keyboard events'
        end

        def press_key(browser, key)
          browser.keyboard.down(key)
          browser.keyboard.up(key)
          puts "Pressed #{key}"
        end

        # Just an idea, and not tested. My idea to defeat captchas is to use a
        # paid service. Alternatively, I've always considered using Amazon's
        # MechanicalTurk API to defeat captchas. If an AI-based solver exists,
        # use CDP to take a screenshot of the captcha and on the server send it
        # to an API running a Tensorflow-based captcha solver.
        def solve_captcha(browser)
          require 'api-2captcha'
          client = Api2Captcha.new('YOUR_API_KEY')
          image = browser.screenshot(path: 'captcha.png')
          captcha_type = :recaptcha_v2
          result =
            case captcha_type
            when :normal
              client.normal({ image: 'captcha.jpg' })
            when :recaptcha_v2
              client.recaptcha_v2({
                                    googlekey: '6Le-wvkSVVABCPBMRTvw0Q4Muexq1bi0DJwx_mJ-',
                                    pageurl: 'https://mysite.com/page/with/recaptcha_v2',
                                    invisible: 1
                                  })
            when :recaptcha_v3
              client.recaptcha_v3({
                                    googlekey: '6Le-wvkSVVABCPBMRTvw0Q4Muexq1bi0DJwx_mJ-',
                                    pageurl: 'https://mysite.com/page/with/recaptcha_v3',
                                    version: 'v3',
                                    score: 0.3,
                                    action: 'verify'
                                  })
            else
              raise "Unknown captcha type: #{captcha_type}"
            end
        end

        def user_agent
          @user_agent ||= user_agents[settings.user_agent_index]
        end

        def proxy
          @proxy ||= proxies[settings.proxy_index]
        end

        def max_user_agent_index
          user_agents.length - 1
        end

        def max_proxy_index
          proxies.length - 1
        end

        def user_agents
          [
            # Personal chrome
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
            # https://www.zenrows.com/blog/user-agent-web-scraping#what-is-a-user-agent
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36',
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36',
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.0.0 Safari/537.36',
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.0.0 Safari/537.36',
            'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.0.0 Safari/537.36',
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.1 Safari/605.1.15',
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 13_1) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.1 Safari/605.1.15'
          ]
        end

        def proxies
          [
            { host: 'x.x.x.x', port: '8800', user: 'user', password: 'pa$$' }
            # Example of a proxy
            # { host: "184.170.245.148", port: "4145" }
          ]
        end
      end
    end
  end
end
