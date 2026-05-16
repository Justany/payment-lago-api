# frozen_string_literal: true

module Types
  module PaymentProviders
    class PawapayInput < BaseInputObject
      description "pawaPay input arguments"

      argument :api_key, String, required: true
      argument :code, String, required: true
      argument :default_correspondent, String, required: false
      argument :default_country, String, required: false
      argument :name, String, required: true
      argument :sandbox, Boolean, required: false
      argument :success_redirect_url, String, required: false
    end
  end
end
