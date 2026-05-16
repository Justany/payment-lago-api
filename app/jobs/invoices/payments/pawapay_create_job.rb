# frozen_string_literal: true

module Invoices
  module Payments
    class PawapayCreateJob < ApplicationJob
      queue_as do
        if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_PAYMENTS"])
          :payments
        else
          :providers
        end
      end

      unique :until_executed

      retry_on Faraday::ConnectionFailed, wait: :polynomially_longer, attempts: 6

      def perform(invoice)
        result = Invoices::Payments::PawapayService.new(invoice).create
        result.raise_if_error!
      end
    end
  end
end
