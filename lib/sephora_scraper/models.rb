# frozen_string_literal: true

require 'sequel'
module SephoraScraper
  class Brand < Sequel::Model
    db_schema do
      primary_key :id
      String :name
      one_to_many :products
    end
  end

  class Product < Sequel::Model
    db_schema do
      primary_key :id
      String :name
      BigDecimal :price, size: [10, 2]
      many_to_one :brand
      many_to_one :source
      many_to_one :product_ingredients
    end
  end

  # Source is the website where the product was found
  class Source < Sequel::Model
    db_schema do
      primary_key :id
      String :name
      one_to_many :products
    end
  end

  class Ingredient < Sequel::Model
    db_schema do
      primary_key :id
      String :name
      String :source_string
      one_to_many :products
      many_to_one :product_ingredients
    end
  end

  class ProductIngredient < Sequel::Model
    db_schema do
      primary_key :id
      one_to_many :products
      one_to_many :ingredients
    end
  end

  class ProductImage < Sequel::Model
    db_schema do
      primary_key :id
      String :source_url
      String :path
      one_to_many :products
    end
  end

  # Settings helps us keep track of the user agent and proxy we are using to
  # scrape the product data, so that we can associate errors with certain
  # settings and avoid them in the future.
  class Setting < Sequel::Model
    db_schema do
      primary_key :id
      Integer :user_agent_index
      Integer :proxy_index
    end
  end
end
