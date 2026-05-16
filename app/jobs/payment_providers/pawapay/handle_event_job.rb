# frozen_string_literal: true

module PaymentProviders
  module Pawapay
    class HandleEventJob < ApplicationJob
      queue_as :providers

      def perform(organization:, event_json:)
        PaymentProviders::Pawapay::HandleEventService.call!(organization:, event_json:)
      end
    end
  end
end
