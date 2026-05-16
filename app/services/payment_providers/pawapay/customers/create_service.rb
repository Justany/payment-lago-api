# frozen_string_literal: true

module PaymentProviders
  module Pawapay
    module Customers
      class CreateService < ::BaseService
        def initialize(customer:, payment_provider_id:, params:, async: true)
          @customer = customer
          @payment_provider_id = payment_provider_id
          @params = params || {}
          @async = async

          super
        end

        def call
          provider_customer = PaymentProviderCustomers::PawapayCustomer.find_by(customer_id: customer.id)
          provider_customer ||= PaymentProviderCustomers::PawapayCustomer.new(
            customer_id: customer.id,
            payment_provider_id:,
            organization_id: organization.id
          )

          if params.key?(:provider_customer_id)
            provider_customer.provider_customer_id = params[:provider_customer_id].presence
          end

          provider_customer.phone_number = params[:phone_number] if params.key?(:phone_number)
          provider_customer.country = params[:country] if params.key?(:country)
          provider_customer.correspondent = params[:correspondent] if params.key?(:correspondent)

          provider_customer.save!

          result.provider_customer = provider_customer
          result
        rescue ActiveRecord::RecordInvalid => e
          result.record_validation_failure!(record: e.record)
        end

        private

        attr_reader :customer, :payment_provider_id, :params, :async

        delegate :organization, to: :customer
      end
    end
  end
end
