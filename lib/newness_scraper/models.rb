# frozen_string_literal: true

require "sequel"

db = Sequel.connect("sqlite://newness.db")

module NewnessScraper
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
    end
  end

  class Source < Sequel::Model
    db_schema do
      primary_key :id
      String :name
      one_to_many :products
    end
  end
end
