# frozen_string_literal: true

module SephoraScraper
  module Scrapers
    # The base scraper class that specific scrapers can inherit from, that sets up options for making HTTP requests.
    class Scraper
      attr_accessor :db

      def initialize(db:)
        @db = db
        @options = {
          headers: {
            # Chrome
            'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
            'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Encoding' => 'br, gzip, deflate',
            'Accept-Language' => 'en-us'
          }
        }
      end

      # Implement this in your scraper class
      def scrape
        raise 'TODO: Implement me'
      end
    end
  end
end
