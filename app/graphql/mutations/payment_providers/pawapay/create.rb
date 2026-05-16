# frozen_string_literal: true

module Mutations
  module PaymentProviders
    module Pawapay
      class Create < Base
        REQUIRED_PERMISSION = "organization:integrations:create"

        graphql_name "AddPawapayPaymentProvider"
        description "Add pawaPay payment provider"

        input_object_class Types::PaymentProviders::PawapayInput

        type Types::PaymentProviders::Pawapay
      end
    end
  end
end
