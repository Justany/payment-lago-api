# frozen_string_literal: true

module Types
  module PaymentProviders
    class Pawapay < Types::BaseObject
      graphql_name "PawapayProvider"

      field :api_key, String, null: true, permission: "organization:integrations:view"
      field :code, String, null: false
      field :default_correspondent, String, null: true, permission: "organization:integrations:view"
      field :default_country, String, null: true, permission: "organization:integrations:view"
      field :id, ID, null: false
      field :name, String, null: false
      field :sandbox, Boolean, null: true, permission: "organization:integrations:view"
      field :success_redirect_url, String, null: true, permission: "organization:integrations:view"

      # NOTE: Api key is a sensitive information. It should not be sent back to the
      #       front end application. Instead we send an obfuscated value
      def api_key
        key = object.api_key.to_s
        return "" if key.empty?

        "#{"•" * 8}…#{key[-3..]}"
      end
    end
  end
end
