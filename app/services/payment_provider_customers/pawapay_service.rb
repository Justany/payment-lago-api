# frozen_string_literal: true

module PaymentProviderCustomers
  class PawapayService < BaseService
    def initialize(pawapay_customer = nil)
      @pawapay_customer = pawapay_customer

      super(nil)
    end

    def create
      result.pawapay_customer = pawapay_customer
      result
    end

    def update
      result
    end

    private

    attr_reader :pawapay_customer

    delegate :customer, to: :pawapay_customer
  end
end
