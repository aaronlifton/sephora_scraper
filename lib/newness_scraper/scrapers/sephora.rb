# frozen_string_literal: true

require "pry"
require "httparty"
require "ferrum"
require "nokogiri"
require "timeout"
require_relative "scraper"

module NewnessScraper
  module Scrapers
    class Sephora < Scraper
      attr_accessor :options, :browser

      # URL = "https://www.sephora.com"
      BRANDS_URL = "https://www.sephora.com/brands-list"
      MAKEUP_URL = "https://www.sephora.com/shop/makeup-cosmetics"
      TIMEOUT = 60 * 3

      def initialize(db:)
        super
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
        @source = Source[name: "Sephora"]
      end

      def scrape
        get_brands unless db[:brands].any?
        get_homepage
      end

      private

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
          sleep TIMEOUT # the timeout
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
          sleep TIMEOUT # the timeout
          if process_thread.alive?
            process_thread.kill
            warn "Timeout"
          end
        end
        process_thread.join
        timeout_thread.kill
      end

      def close_modal(browser)
        browser.at_css("[data-at='close_button']")&.click
      end

      def get_homepage
        viewport_height = 768
        @brands_body = nil
        @makeup_body = nil
        @browser = nil

        @requests = []
        @search_product_results = []
        @product_tiles = []
        @ingredients = {}
        @links = {}

        script = proc do
          @browser = Ferrum::Browser.new({ headless: false, timeout: TIMEOUT })
          browser.go_to(MAKEUP_URL)
          browser.network.wait_for_idle
          close_modal(browser)
          @makeup_body = browser.body
          height = browser.evaluate <<~JS
            Math.max(document.body.scrollHeight, document.body.offsetHeight, document.documentElement.clientHeight, document.documentElement.scrollHeight, document.documentElement.offsetHeight)
          JS
          y = 0
          # Sephora has lazy loading, so we must scroll down the page, collecting products as we go
          tiles = nil
          while y < height + viewport_height
            @makeup_body = browser.body
            document = Nokogiri::HTML(@makeup_body)
            # Sephora code has an extra space here
            tiles ||=  document.css("[data-comp='LazyLoad ProductTile ']").to_a
            # if tiles.none?
            #   # browser.refresh
            #   # close_modal(browser)
            #   sleep 2
            #   @makeup_body = browser.body
            #   document = Nokogiri::HTML(@makeup_body)
            #   tiles = browser.css("[data-comp='LazyLoad ProductTile ']").to_a
            # end
            if tiles.none?
              browser.refresh
              sleep 5
              close_modal(browser)
              browser.mouse.scroll_to(0, y)
              @makeup_body = browser.body
              document = Nokogiri::HTML(@makeup_body)
              tiles = document.css("[data-comp='LazyLoad ProductTile ']").to_a
            end
            raise StandardError, "Could not find tiles, please try again." unless tiles.any?

            tiles.each do |tile|
              @product_tiles << tile
            end
            y += viewport_height
            browser.mouse.scroll_to(0, y)
            puts "Scrolled to #{y}"
          end
        end

        custom_get(MAKEUP_URL, :@makeup_body, &script)

        document = Nokogiri::HTML(@makeup_body)
        data = @product_tiles.map do |tile|
          name_el = tile.css(".ProductTile-name").first

          {
            name: name_el.text,
            brand: name_el&.previous_sibling&.text,
            price: name_el.next_sibling.next_sibling.next_sibling.children.first&.text,
            link: tile.attribute("href").value
          }
        end

        data.each do |product|
          browser.go_to(product[:link])
          product[:ingredients] = []
          sleep 2
          browser.mouse.scroll_to(0, 1000)
          document = Nokogiri::HTML(browser.body)
          accordian = browser.at_xpath('//h2[contains(text(), "Ingredients")]')
          accordian_nokogiri = document.at_xpath('//h2[contains(text(), "Ingredients")]')
          accordian.click
          ingredients_html = accordian_nokogiri.parent.next_sibling.children.first.inner_html
          ingredients_string = ingredients_html.gsub("<div>", "").gsub("</div", "")
          parts = ingredients_string.split("<br>")
          # binding.pry unless parts.find_index { |part| part.include?("Clean at Sephora") }
          parts.each do |part|
            break unless part.strip[0] == "-"

            product[:ingredients] << part[1..-1].split(":").first
          end
          idx = parts.find_index { |part| part.include?("Clean at Sephora") }
          starting_idx = idx ? idx + 1 : 0
          full_ingredients = parts[starting_idx].split(",").map do |i|
            i = i.split("(").first
            i = i.gsub(" and derivatives", "").gsub(" and related compounds", "")
            i = i.gsub(/(under \d%)/, "")
            i.strip
          end.uniq

          product[:ingredients] += full_ingredients
        end
        binding.pry

        data.each do |product|
          next if Product[name: product[:name], source_id: @source.id]

          brand = Brand[name: product[:brand]]
          brand = Brand.create(name: product[:brand]) if brand.nil?

          p = Product.new({
                            name: product[:name],
                            brand_id: brand.id,
                            price: product[:price]&.gsub("$", "")&.to_f,
                            source_id: @source.id
                          })
          p.save
        end

        nil
        # browser.at_xpath('//*[contains(text(), "Abbot")]')
      end

      def get_brands
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
