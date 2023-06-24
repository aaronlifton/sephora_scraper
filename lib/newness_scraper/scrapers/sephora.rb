# frozen_string_literal: true

require "pry"
require "httparty"
require "ferrum"
require "nokogiri"
require "timeout"

module NewnessScraper
  module Scrapers
    class Sephora
      attr_accessor :options, :browser

      # URL = "https://www.sephora.com"
      BRANDS_URL = "https://www.sephora.com/brands-list"
      MAKEUP_URL = "https://www.sephora.com/shop/makeup-cosmetics"

      def initialize
        @options = {
          headers: {
            # "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36"
            # Chrome
            "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36",
            "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
            "Accept-Encoding" => "gzip, deflate, br",
            "Accept-Language" => "n-US,en;q=0.9"
          },
          verify: false
        }
      end

      def scrape
        get_homepage
      end

      def get(url, var, intercept: false, &block)
        script = proc do
          @browser = Ferrum::Browser.new({ headless: false, timeout: 20 })
          browser.network.intercept if intercept
          block.call(browser) if block_given?
          browser.go_to(url)
          browser.network.wait_for_idle
          instance_variable_set(var, browser.body)
        end

        # Run browser in seperate thread so script can continue
        process_thread = Thread.new { script.call }
        timeout_thread = Thread.new do
          sleep 16 # the timeout
          if process_thread.alive?
            process_thread.kill
            warn "Timeout"
          end
        end
        process_thread.join
        timeout_thread.kill
      end

      def custom_get(_url, _var, &script)
        # Run browser in seperate thread so script can continue
        process_thread = Thread.new { script.call }
        timeout_thread = Thread.new do
          sleep 16 # the timeout
          if process_thread.alive?
            process_thread.kill
            warn "Timeout"
          end
        end
        process_thread.join
        timeout_thread.kill
      end

      def get_homepage
        viewport_height = 768
        @brands_body = nil
        @makeup_body = nil
        @browser = nil

        @requests = []
        @search_product_results = []
        @product_names = []

        script = proc do
          @browser = Ferrum::Browser.new({ headless: false, timeout: 20 })
          browser.go_to(MAKEUP_URL)
          # browser.network.wait_for_idle
          @makeup_body = browser.body
          document = Nokogiri::HTML(@makeup_body)
          height = browser.evaluate <<~JS
            Math.max(document.body.scrollHeight, document.body.offsetHeight, document.documentElement.clientHeight, document.documentElement.scrollHeight, document.documentElement.offsetHeight)
          JS
          y = 0

          puts({ height: height })
          while y < height
            @makeup_body = browser.body
            document = Nokogiri::HTML(@makeup_body)
            @product_names += document.css(".ProductTile-name").to_a
            # y = browser.evaluate <<~JS
            #   document.documentElement.scrollTop
            # JS
            y += viewport_height
            puts y
            browser.mouse.scroll_to(0, y)
          end
        end

        custom_get(MAKEUP_URL, :@makeup_body, &script)

        document = Nokogiri::HTML(@makeup_body)
        product_tiles = document.css("[data-comp='LazyLoad ProductTile']")
        product_names = document.css(".ProductTile-name").to_enum
        binding.pry

        return
        get(BRANDS_URL, :@brands_body)
        document = Nokogiri::HTML(@brands_body)

        links = document.css("[data-at='brand_link']").to_enum

        brands = links.take(links.count).map { |link| link.children.first.text }
        puts brands

        brands.each do |brand|
          next if Brand[name: brand]

          b = Brand.new(name: brand)
          b.save
        end

        # browser.at_xpath('//*[contains(text(), "Abbot")]')
      end

      def intercept_traffic
        # get(MAKEUP_URL, :@makeup_body) do |browser|
        #   browser.on(:request) do |request|
        #     @requests << request
        #     request.continue
        #   end
        # end
        @browser.network.traffic.select { |t| t.url.include?("browseSearchProduct") }
        @search_product_results = @requests.select do |r|
          @search_product_results << r.body if r.url.include?("browseSearchProduct")
        end
      end
    end
  end
end
