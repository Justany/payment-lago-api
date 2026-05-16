# frozen_string_literal: true

module PaymentProviderCustomers
  class PawapayCreateJob < ApplicationJob
    queue_as :providers

    retry_on ActiveJob::DeserializationError

    def perform(pawapay_customer)
      result = PaymentProviderCustomers::PawapayService.new(pawapay_customer).create

      result.raise_if_error!
    end
  end
end
