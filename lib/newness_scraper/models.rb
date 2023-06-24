# frozen_string_literal: true

require "sequel"

db = Sequel.connect("sqlite://newness.db")

module NewnessScraper
  class Brand < Sequel::Model
    db_schema do
      primary_key :id
      String :name
    end
  end
end
