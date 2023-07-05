# frozen_string_literal: true

require 'pry'
require 'httparty'
require 'ferrum'
require 'nokogiri'
require 'timeout'
require 'open-uri'
require 'net/http'
require_relative 'scraper'

module SephoraScraper
  module Scrapers
    class Sephora < Scraper
      attr_accessor :options, :browser, :tiles

      class StandardError < ::StandardError; end
      class RuntimeError < ::RuntimeError; end
      class RescuableNotNotFoundError < RuntimeError; end

      BASE_URL = 'https://www.sephora.com'
      BRANDS_URL = 'https://www.sephora.com/brands-list'
      MAKEUP_URL = 'https://www.sephora.com/shop/makeup-cosmetics'
      TIMEOUT = 60
      # Sephora HTML has an extra space in the data attribute here
      TILES_CSS = "[data-comp='LazyLoad ProductTile ']"

      def initialize(db:)
        super
        @browser = Ferrum::Browser.new(@options.merge({ headless: false, timeout: TIMEOUT }))
        @browser_context = browser.contexts.create
        @options = {
          headers: {
            'User-Agent' => Util.user_agent,
            'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
            'Accept-Encoding' => 'gzip, deflate, br',
            'Accept-Language' => 'n-US,en;q=0.9'
          },
          # Don't use example proxy. Just placeholder for an actual proxy IP.
          proxy: Util.proxy[:host] == 'x.x.x.x' ? nil : Util.proxy,
          verify: false
        }
        @source = Source[name: 'Sephora']
      end

      def scrape
        scrape_brands unless db[:brands].any?
        scrape_products
      rescue RescuableNotNotFoundError => e
        puts e.message
      end

      private

      def scrape_brands
        brands_body = get(BRANDS_URL, timeout: 20)
        document = Nokogiri::HTML(brands_body)
        links = document.css("[data-at='brand_link']").to_enum
        brands = links.take(links.count).map { |link| link.children.first.text }

        puts "Found brands:\n\n\t#{brands.join("\n")}\nTotal # of brands: #{brands.count}\n\n"
        brands.each do |brand|
          next if Brand[name: brand]

          Brand.create(name: brand)
        end
      end

      def scrape_products
        viewport_height = 768

        @requests = []
        product_tiles = []
        @ingredients = {}
        @links = {}

        script = proc do
          browser = instance_eval { @browser }
          browser.go_to(MAKEUP_URL)
          # Wait 9 seconds for all network requests to finish
          # browser.network.wait_for_idle(timeout: 25)
          # Enter some user input so the signup modal is triggered
          Util.press_key(browser, 'a')
          Util.press_key(browser, :enter)
          random_sleep
          browser.mouse.scroll_to(0, 100)
          try_close_modal(browser)
          # Even though modal was closed, also press escape, which also triggers closing of the modal
          Util.press_key(browser, :escape)
          # At this point the modal should be closed. This part has been a bit tricky to automate.
          browser.mouse.scroll_to(0, 0)
          # @makeup_body = browser.body
          height = browser.evaluate <<~JS
            Math.max(document.body.scrollHeight, document.body.offsetHeight, document.documentElement.clientHeight, document.documentElement.scrollHeight, document.documentElement.offsetHeight)
          JS
          y = 0
          # Gets the product tiles displayed on a Sephora category page
          document = Nokogiri::HTML(browser.body)
          tiles = get_tiles(browser, y) || document.css(TILES_CSS).to_a
          if tiles&.none?
            browser.refresh
            browser.network.wait_for_idle
            try_close_modal(browser)
            browser.mouse.scroll_to(0, y)
            document = Nokogiri::HTML(browser.body)
            tiles = document.css(TILES_CSS).to_a
          end
          # On a rare occasian, the product tiles cannot be found by the javascript selector
          raise StandardError, 'Could not find tiles, please try again.' unless tiles&.any?

          # Sephora has lazy loading, so we must scroll down the page, collecting products as we go
          while y < height + viewport_height
            tiles = get_tiles(browser, y)
            tiles.each { |tile| instance_exec(tile) { product_tiles << tile } }

            y += viewport_height
            Util.random_mouse_move(browser)
            browser.mouse.scroll_to(0, y)
            puts "Scrolled to #{y}"
            try_close_modal(browser) # Sometimes the modal appears as we scroll down the page
            random_sleep
          end
          puts "\nScrolled to end of page, all products collected\n"
        end

        threaded_sephora_scraper(&script)
        Util.random_mouse_move(browser)
        Util.press_key(browser, :escape)
        try_close_modal(browser)

        products = data_from_product_tiles(product_tiles)
        final_makeup_category_url = browser.current_url
        products = merge_with_data_from_detail_page(final_makeup_category_url, products, browser)

        puts "Created\t#{products.length} products\n\t#{Ingredient.count} ingredients\n\t#{ProductIngredient.count} " \
             "product ingredient relationships\n\t#{Brand.count} brands"
      end

      def get_tiles(browser, y)
        document = Nokogiri::HTML(@browser.body)
        tiles = Ferrum::Utils::Attempt.with_retry(errors: RuntimeError, max: 15, wait: 0.1) do
          raise RescuableNotNotFoundError, 'Product tiles not found' unless document.css(TILES_CSS).to_a

          document.css(TILES_CSS).to_a
        end
        # Can delete this?
        if tiles.none?
          browser.refresh
          browser.network.wait_for_idle
          try_close_modal(browser)
          browser.mouse.scroll_to(0, y)
          document = Nokogiri::HTML(@browser.body)
          tiles = document.css(TILES_CSS).to_a
        end
        # On a rare occasian, the product tiles cannot be found by the javascript selector
        raise StandardError, 'Could not find tiles, please try again.' unless tiles&.any?

        tiles
      end

      # Visits a product's page and collects ingredients and images
      #
      # @param data [Array<Hash>] data collected from index page
      # @param browser [Ferrum::Browser] instance of the ferrum browser
      # @return [Array<Hash>] full product data
      def merge_with_data_from_detail_page(final_makeup_category_url, data, browser)
        data.each do |product|
          url = product[:link][0] == '/' ? "#{BASE_URL}#{product[:link]}" : product[:link]
          browser.headers.add({ 'Referer' => final_makeup_category_url })
          browser.go_to(url)
          puts "Visited #{url}"
          product[:ingredients] = []
          product[:images] = []
          # Arbitrary sleep
          Util.random_mouse_move(browser)
          sleep 1
          try_close_modal(browser)
          document = Nokogiri::HTML(browser.body)
          # Sephora has an extra space in the data attribute here
          carousel = document.at_css("[data-comp='Carousel ']")
          # On a rare occasion, carousel is nil
          product[:images] = carousel ? carousel.css('button').map do |button|
            button.child.child.child.attribute('src')&.value
          end.compact : []
          # Arbitrary sleep
          Util.random_mouse_move(browser)
          sleep 1
          # Scroll to ingredients accordian section
          browser.mouse.scroll_to(0, 1000)
          Util.random_keyboard_event(browser) if rand(10) == 1
          document = Nokogiri::HTML(browser.body)

          # Get ingredients
          accordian = browser.at_xpath('//h2[contains(text(), "Ingredients")]')
          accordian_nokogiri = document.at_xpath('//h2[contains(text(), "Ingredients")]')
          if accordian
            accordian.click
            ingredients_html = accordian_nokogiri.parent.next_sibling.children.first.inner_html
            ingredients_string = ingredients_html.gsub('<div>', '').gsub('</div', '')
            parts = ingredients_string.split('<br>')
            parts.each do |part|
              break unless part.strip[0] == '-'
  
              product[:ingredients] << part[1..].split(':').first
            end
            full_ingredients = cleanup_ingredient_parts(parts)
  
            product[:ingredients] += full_ingredients
          end

          next if Product[name: product[:name], source_id: @source.id]

          create_models(product)
        end

        data
      end

      def get(url, intercept: false, timeout: TIMEOUT, &block)
        return_value = nil
        script = proc do
          browser.network.intercept if intercept
          block.call(browser) if block_given?
          browser.go_to(url)
          browser.network.wait_for_idle
          return_value = browser.body
        end

        # Run browser in seperate tn continue
        process_thread = Thread.new(@browser_context) { script.call }
        timeout_thread = Thread.new do
          sleep TIMEOUT # the timeout
          if process_thread.alive?
            process_thread.kill
            warn 'Timeout'
          end
        end
        process_thread.join
        timeout_thread.kill

        return_value
      end

      def threaded_sephora_scraper(&script)
        return_value = nil
        # Run browser in seperate thread so script can continue
        process_thread = Thread.new(@browser_context) { return_value = script.call }
        close_modal_thread = Thread.new(@browser_context) { try_close_modal(browser) }
        timeout_thread = Thread.new do
          sleep TIMEOUT # the timeout
          if process_thread.alive?
            process_thread.kill
            warn 'Timeout'
          end
        end
        close_modal_timeout_thread = Thread.new do
          sleep 14 # the timeout
          if close_modal_thread.alive?
            close_modal_thread.kill
            warn 'Killed the CloseModal thread'
          end
        end
        process_thread.join
        close_modal_thread.join
        timeout_thread.kill
        close_modal_timeout_thread.kill

        return_value
      end

      def try_close_modal(browser, should_raise: false)
        close_button = Ferrum::Utils::Attempt.with_retry(errors: RuntimeError, max: 15, wait: 0.1) do
          if should_raise && !browser.at_css("[data-at='close_button']")
            raise RescuableNotNotFoundError, 'Modal not found'
          end
        end
        return unless close_button

        close_button&.click
        puts 'Closed modal'
      end

      # Gets base product data from product tiles on a Sephora category page
      # @param product_tiles [Array<Ferrum::NB=] <description>
      # @return [Array<Hash>] Array of hashes containing product name, brand, price, and a URL to its detail page
      def data_from_product_tiles(product_tiles)
        product_tiles.map do |tile|
          name_el = tile.css('.ProductTile-name').first

          {
            name: name_el.text,
            brand: name_el&.previous_sibling&.text,
            price: name_el.next_sibling.next_sibling.next_sibling.children.first&.text,
            link: tile.attribute('href').value
          }
        end
      end

      def js_escape_map
        @js_escape_map ||= {
          '\\' => '\\\\',
          '</' => '<\/',
          "\r\n" => '\n',
          "\n" => '\n',
          "\r" => '\n',
          '"' => '\\"',
          "'" => "\\'",
          '`' => '\\`',
          '$' => '\\$'
        }
      end

      # https://github.com/rails/rails/blob/2d6f523ba5d47a03ad3e3205c24a3fa13a3b8ad1/actionview/lib/action_view/helpers/javascript_helper.rb#L28
      def escape_javascript(js)
        js = js.to_s
        result = if js.nil? || js.empty?
                   ''
                 else
                   js.gsub(%r{(\\|</|\r\n|\342\200\250|\342\200\251|[\n\r"']|[`]|[$])}u, js_escape_map)
                 end
      end

      # This is a possible alternate way of fetching the image, using javascript via the CDP protocol:
      # Browser.evaluate_async(get_image_js(image_url, request.headers.to_json), 5)
      def get_image_js(image_url, headers_json)
        escaped_headers_json = escape_javascript(headers_json)
        <<~JS
          async function fetchImage() {
            const response = await fetch("#{image_url}", {
              headers: JSON.parse("#{escaped_headers_json}")
            });
            const blob = await response.blob();
            const imageBase64 = await new Promise((resolve, reject) => {
              const reader = new FileReader();
              reader.onloadend = () => resolve(reader.result);
              reader.onerror = reject;
              reader.readAsDataURL(blob);
            });

            return imageBase64;
          }

          return await fetchImage()
        JS
      end

      # Takes scraped product info and creates rows in the product,
      # ingredient, product_ingredient, and product_images tables
      # @param product [Hash] scraped product info
      #
      # @return [SephoraScraper::Product] the newly created product model
      def create_models(product)
        brand = Brand[name: product[:brand]]
        brand = Brand.create(name: product[:brand]) if brand.nil?

        p = Product.create(
          {
            name: product[:name],
            brand_id: brand.id,
            price: product[:price]&.gsub('$', '')&.to_f,
            source_id: @source.id
          }
        )
        product[:ingredients].each do |ingredient|
          db_ingredient = Ingredient[name: ingredient]
          db_ingredient ||= Ingredient.create(name: ingredient)

          db_product_ingredient = ProductIngredient[product_id: p.id, ingredient_id: db_ingredient.id]
          next if db_product_ingredient

          ProductIngredient.create(product_id: p.id, ingredient_id: db_ingredient.id)
        end

        images_path = "downloaded_images/#{p.id}-#{p.name}"
        FileUtils.mkdir_p(images_path)

        product[:images].each_with_index do |image_url, _i|
          exchange = browser.network.traffic.find { |exchange| exchange.response&.url == image_url }
          next unless exchange

          request = exchange&.request
          request_id = request&.id
          image_url = image_url.split('?').first # Remove size params, because we want the full size image
          extension = image_url.split('?').last
          next unless image_url

          product_image = ProductImage[product_id: p.id, source_url: image_url]
          next if product_image
          
          image_binary = exchange.response.body.inspect
          image_base64 = Base64.encode64(image_binary)

          filename = Base64.urlsafe_encode64("sephora#{[Time.now.to_f].pack('D*')}")
          path = "tmp/#{filename}"
          image_file = File.open(File.join(Dir.pwd, path), 'wb')
          image_file.write(Base64.decode64(image_base64))
          image_file.close

          ProductImage.create(product_id: p.id, source_url: image_url, path: path)
        end
        puts "Downloaded images and put into database."

        p
      end

      # Cleans up the ingredients listed on a Sephora product detail page
      # @param parts [Array<String>] The parts of the ingredients description split by a ","
      #
      # @return [Array<String>] Cleaned up ingredient strings, ready to be inserted into the DB
      def cleanup_ingredient_parts(parts)
        # Some products have a "Clean at Sephora" section, which we want to ignore
        idx = parts.find_index { |part| part.include?('Clean at Sephora') }
        starting_idx = idx ? idx + 1 : 0
        parts[starting_idx] = parts[starting_idx].gsub('1, 4, Dioxane', "1'4 Dioxane")
        # Clean up ingredients
        parts[starting_idx].split(',').map do |i|
          i = i.split('(').first
          i = i.gsub(' and derivatives', '').gsub(' and related compounds', '')
          i = i.gsub(/\(((\w+)( |))*\)/, '')
          i = i.gsub('(', '').gsub(')', '')
          i = i.gsub(/(under \d%)/, '')
          i.strip
        end.uniq
      end

      def random_sleep
        sleep [0.5, 0.6, 0.7, 0.8, 0.9].sample
      end
    end
  end
end