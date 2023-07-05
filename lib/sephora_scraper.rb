# frozen_string_literal: true

require_relative 'sephora_scraper/version'
require_relative 'sephora_scraper/scrapers/util'
require_relative 'sephora_scraper/scrapers/sephora'
require 'sequel'

module SephoraScraper
  class Runner
    attr_accessor :db

    DATABASE_URL = 'sqlite://sephora.db'
    class Error < StandardError; end

    def scrape
      setup_db
      sephora_scraper = Scrapers::Sephora.new(db: @db)
      sephora_scraper.scrape
      puts 'Scraped Sephora'
      puts "\nDone"
    end

    private

    def setup_db(reset_db: true)
      @db = Sequel.connect(DATABASE_URL)
      # For testing purposes
      if reset_db
        %i[product_ingredients product_images products brands sources ingredients settings].each do |table_name|
          db.drop_table(table_name) if db.tables.include?(table_name)
        end
      end

      # Make sure tables are created on first run
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
          String :source_string
        end
      end

      unless db.tables.include?(:product_ingredients)
        db.create_table(:product_ingredients) do
          primary_key :id
          foreign_key :product_id, :products, key: :id, null: false
          foreign_key :ingredient_id, :ingredients, key: :id, null: false
        end
      end

      unless db.tables.include?(:product_images)
        db.create_table(:product_images) do
          primary_key :id
          String :source_url
          String :path
          foreign_key :product_id, :products, key: :id, null: false
        end
      end

      unless db.tables.include?(:settings)
        db.create_table(:settings) do
          primary_key :id
          Integer :user_agent_index
          Integer :proxy_index
          String :fingerprint, text: true
        end
      end

      require_relative 'sephora_scraper/models'

      # Initialize settings
      Scrapers::Util.initialize_settings

      return if Source[name: 'Sephora']

      Source.create(name: 'Sephora')
    end
  end

  class Error < StandardError; end
end
