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
      CLOSE_MODAL_TIMEOUT = 14
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
        script = proc do
          browser.go_to(BRANDS_URL)
          browser.network.wait_for_idle
          browser.body
        end
        brands_body = threaded_sephora_scraper(timeout: 20, &script)
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
        current_url = browser.current_url
        products = merge_with_data_from_detail_page(current_url, products, browser)

        puts "Created\t#{products.length} products\n\t#{Ingredient.count} ingredients\n\t#{ProductIngredient.count} " \
             "product ingredient relationships\n\t#{Brand.count} brands"
      end

      def get_tiles(browser, y)
        document = Nokogiri::HTML(@browser.body)
        tiles = Ferrum::Utils::Attempt.with_retry(errors: RuntimeError, max: 15, wait: 0.1) do
          raise RescuableNotNotFoundError, 'Product tiles not found' unless document.css(TILES_CSS).to_a

          document.css(TILES_CSS).to_a
        end
        if tiles.none?
          puts 'No tiles found, refreshing and trying again...'
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

      # Merges scraped product info with scraped ingredients and images
      #
      # @param data [Array<Hash>] data collected from index page
      # @param browser [Ferrum::Browser] instance of the ferrum browser
      # @return [Array<Hash>] full product data
      def merge_with_data_from_detail_page(current_url, data, browser)
        data.each do |product|
          url = product[:link][0] == '/' ? "#{BASE_URL}#{product[:link]}" : product[:link]
          browser.headers.add({ 'Referer' => current_url })
          browser.go_to(url)
          puts "Visited #{url}"
          product[:ingredients] = []
          product[:images] = []
          Util.random_mouse_move(browser)
          sleep 1 # Static sleep
          try_close_modal(browser)
          document = Nokogiri::HTML(browser.body)
          # Sephora has an extra space in the data attribute here
          carousel = document.at_css("[data-comp='Carousel ']")
          # On a rare occasion, carousel is nil
          product[:images] =
            if carousel
              carousel.css('button').map { |button| button.child.child.child.attribute('src')&.value }.compact
            else
              []
            end
          Util.random_mouse_move(browser)
          sleep 1
          # Scroll to ingredients accordian section
          browser.mouse.scroll_to(0, 1000)
          Util.random_keyboard_event(browser) if rand(10) == 1
          document = Nokogiri::HTML(browser.body)

          # Get ingredients
          begin
            accordian = browser.at_xpath('//h2[contains(text(), "Ingredients")]')
            accordian_nokogiri = document.at_xpath('//h2[contains(text(), "Ingredients")]')
            if accordian
              accordian.click
              ingredients_html = accordian_nokogiri.parent.next_sibling.children.first.inner_html
              ingredients_string = ingredients_html.gsub('<div>', '').gsub('</div>', '')
              ingredients_string = ingredients_string.gsub('<b>', '').gsub('</b>', '')
              parts = ingredients_string.split('<br>')
              top_level_ingredients = []
              parts.each do |part|
                break unless part.strip[0] == '-'

                ingredient_name = part[1..].split(':').first
                top_level_ingredients << ingredient_name
              end
              full_ingredients = cleanup_ingredient_parts(top_level_ingredients + parts)
              product[:ingredients] += full_ingredients
            end
          rescue Ferrum::NodeNotFoundError => e
            puts e
          end

          next if Product[name: product[:name], source_id: @source.id]

          create_models(product)
        end

        data
      end

      def try_close_modal(browser)
        # Relying on a class name generated by javscript or some precompilation
        # process doesn't seem as reliable as  selecting based on other HTML
        # attributes
        modal_close = browser.find_element(class: 'css-1g5e2rn')
        return unless modal_close

        modal_close.click
      rescue Selenium::WebDriver::Error::NoSuchElementError
        warn 'No modal to close'
      end

      def threaded_sephora_scraper(timeout: TIMEOUT, &script)
        return_value = nil
        # Run browser in seperate thread so script can continue
        process_thread = Thread.new(@browser_context) { return_value = script.call }
        close_modal_thread = Thread.new(@browser_context) { try_close_modal(browser) }
        timeout_thread = Thread.new do
          sleep timeout # the wsxsssxs
          if process_thread.alive?
            process_thread.kill
            warn 'Timeout'
          end
        end
        close_modal_timeout_thread = Thread.new do
          sleep CLOSE_MODAL_TIMEOUT # the timeout
          if close_modal_thread.alive?
            close_modal_thread.kill
            warn 'Killed the CloseModal thread'
          end
        end
        process_thread.join
        close_modal_thread.join
        timeout_thread.kill

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
        if js.nil? || js.empty?
          ''
        else
          js.gsub(%r{(\\|</|\r\n|\342\200\250|\342\200\251|[\n\r"']|[`]|[$])}u, js_escape_map)
        end
      end

      # This is a possible alternate way of fetching the image, using javascript via the CDP protocol:
      #
      # image_url = image_url.split('?').first # Remove size params, because we want the full size image
      # # Make sure cookies are sent with the request
      # image_base64 = Browser.evaluate_async(get_image_js(image_url, request.headers.to_json), 5)
      # File.write('test.jpg', Base64.decode64(image_base64))
      #
      # def get_image_js(image_url, headers_json)
      #   escaped_headers_json = escape_javascript(headers_json)
      #   <<~JS
      #     async function fetchImage() {
      #       const response = await fetch("#{image_url}", {
      #         headers: JSON.parse("#{escaped_headers_json}")
      #       });
      #       const blob = await response.blob();
      #       const imageBase64 = await new Promise((resolve, reject) => {
      #         const reader = new FileReader();
      #         reader.onloadend = () => resolve(reader.result);
      #         reader.onerror = reject;
      #         reader.readAsDataURL(blob);
      #       });

      #       return imageBase64;
      #     }

      #     return await fetchImage()
      #   JS
      # end

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
        product[:ingredients].each do |source_string_, ingredient_|
          db_ingredient = Ingredient[source_string: source_string_]
          db_ingredient ||= Ingredient.create(source_string: source_string_, name: ingredient_)

          # Associate ingredient with product
          db_product_ingredient = ProductIngredient[product_id: p.id, ingredient_id: db_ingredient.id]
          next if db_product_ingredient

          ProductIngredient.create(product_id: p.id, ingredient_id: db_ingredient.id)
        end

        images_path = "downloaded_images/#{p.id}-#{p.name}"
        FileUtils.mkdir_p(images_path)

        product[:images].each do |image_url|
          exchange = browser.network.traffic.find { |traffic_exchange| traffic_exchange.response&.url == image_url }
          next unless exchange

          # TODO: Try to use javascript via CDP to fetch the full size image,
          # because Akamai Image Manager does not like being accessed directly.
          # See documentation for #get_image_js above.
          image_url = image_url.split('?').first
          next unless image_url

          product_image = ProductImage[product_id: p.id, source_url: image_url]
          next if product_image

          image_binary = exchange.response.body
          extension = image_url.split('.').last
          filename = Base64.urlsafe_encode64("sephora#{[Time.now.to_f].pack('D*')}")
          tmp_path = "tmp/#{filename}.#{extension}"
          File.binwrite(File.join(Dir.pwd, tmp_path), image_binary)
          ProductImage.create(product_id: p.id, source_url: image_url, path: tmp_path)
        end
        puts 'Downloaded images and inserted into database.'

        p
      end

      # Cleans up the ingredients listed on a Sephora product detail page
      # Walks down the ingredient section of the accordian, and stop when we hit
      # the section with the actual ingedients list.
      # @param parts [Array<String>] The parts of the ingredients description split by a ","
      #
      # @return [Array<String>] Cleaned up ingredient strings, ready to be inserted into the DB
      def cleanup_ingredient_parts(parts)
        # Some products have a "Clean at Sephora" section, which we want to ignore
        idx = parts.find_index { |part| part.include?('Clean at Sephora') }
        starting_idx = idx ? idx + 1 : 0
        # 1,4-Dioxane has different spellings, and we are relying on each
        # ingredient not having any commas, so replace the comma.
        parts[starting_idx] = parts[starting_idx].gsub('1, 4, Dioxane', "1'4 Dioxane")
        # Clean up ingredients
        parts[starting_idx].split(',').map do |i|
          original_string = i
          i = i.split('(').first
          has_description = i.index(':')
          i = i.split(':').first if has_description
          has_brackets = i.index('[')
          i = i.split('[').first if has_brackets
          has_period = i.index('.')
          i = i.split('.').first if has_period
          i = i[1..] if i[0] == '-'
          i = i.gsub('<', '').gsub('>', '')
          i = i.gsub('&amp;', '&')
          i = i.gsub(' and derivatives', '').gsub(' and related compounds', '')
          i = i.gsub(/\(((\w+)( |))*\)/, '')
          i = i.gsub('(', '').gsub(')', '')
          i = i.gsub(/(under \d%)/, '')

          [original_string, i.strip]
        end.uniq
      end

      def random_sleep
        sleep [0.5, 0.6, 0.7, 0.8, 0.9].sample
      end
    end
  end
end
