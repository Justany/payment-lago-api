# frozen_string_literal: true

module Mutations
  module PaymentProviders
    module Pawapay
      class Update < Base
        REQUIRED_PERMISSION = "organization:integrations:update"

        graphql_name "UpdatePawapayPaymentProvider"
        description "Update pawaPay payment provider"

        input_object_class Types::PaymentProviders::UpdateInput

        type Types::PaymentProviders::Pawapay
      end
    end
  end
end
