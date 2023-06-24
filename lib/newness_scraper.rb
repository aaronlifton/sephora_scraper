# frozen_string_literal: true

require_relative "newness_scraper/version"
require_relative "newness_scraper/scrapers/sephora"
require_relative "newness_scraper/models"
require "sequel"

module NewnessScraper
  class Runner
    class Error < StandardError; end

    def scrape
      setup_db
      sephora_scraper = Scrapers::Sephora.new
      sephora_scraper.scrape
      puts "Scraped Sephora"
      puts "\nDone"
    end

    private

    def setup_db
      db = Sequel.connect("sqlite://newness.db")
    end
  end

  class Error < StandardError; end
end
