# frozen_string_literal: true

require 'cloud/azure/logging/logger'
require 'cloud/cpi_service/models/cpi_service_services_pb'

module Bosh
  module CpiService
    class CpiServerImpl < Bosh::CpiService::Service::CPI::Service
      def create_vm(req, _call)
        CPILogger.instance.info("create_vm, req: #{req}")
        begin
          # construct the cloud object to do the real job.
          # Bosh::AzureCloud::Cloud.new()
        rescue StandardError => e
        end
        Bosh::CpiService::Models::CreateVMResponse.new(vm_cid: "xx1vid")
      end
    end
  end
end
