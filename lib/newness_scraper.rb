# frozen_string_literal: true

require_relative "newness_scraper/version"
require_relative "newness_scraper/scrapers/sephora"
require "sequel"

module NewnessScraper
  class Runner
    attr_accessor :db

    DATABASE_URL = "sqlite://newness.db"
    class Error < StandardError; end

    def scrape
      setup_db
      sephora_scraper = Scrapers::Sephora.new(db: @db)
      sephora_scraper.scrape
      puts "Scraped Sephora"
      puts "\nDone"
    end

    private

    def setup_db
      @db = Sequel.connect(DATABASE_URL)
      db.drop_table(:product_ingredients) if db.tables.include?(:product_ingredients)
      db.drop_table(:products) if db.tables.include?(:products)
      db.drop_table(:brands) if db.tables.include?(:brands)
      db.drop_table(:sources) if db.tables.include?(:sources)
      db.drop_table(:ingredients) if db.tables.include?(:ingredients)

      unless db.tables.include?(:brands)
        db.create_table(:brands) do
          primary_key :id
          String :name
        end
      end

      unless db.tables.include?(:sources)
        db.create_table(:sources) do
          primary_key :id
          String :name
        end
      end

      unless db.tables.include?(:products)
        db.create_table(:products) do
          primary_key :id
          String :name
          BigDecimal :price, size: [8, 2]
          foreign_key :brand_id, :brands, key: :id, null: false
          foreign_key :source_id, :sources, key: :id, null: false
        end
      end

      unless db.tables.include?(:ingredients)
        db.create_table(:ingredients) do
          primary_key :id
          String :name
        end
      end

      unless db.tables.include?(:product_ingredients)
        db.create_table(:product_ingredients) do
          primary_key :id
          foreign_key :product_id, :products, key: :id, null: false
          foreign_key :ingredient_id, :ingredients, key: :id, null: false
        end
      end

      require_relative "newness_scraper/models"

      return if Source[name: "Sephora"]

      source = Source.new(name: "Sephora")
      source.save
    end
  end

  class Error < StandardError; end
end
