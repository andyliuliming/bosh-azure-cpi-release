# frozen_string_literal: true

module Bosh::AzureCloud
  class VMSSBatchRequest
    attr_reader :bosh_vm_meta, :location, :vm_props, :network_configurator, :env
    def initialize(bosh_vm_meta, location, vm_props, network_configurator, env)
      @bosh_vm_meta = bosh_vm_meta
      @location = location
      @vm_props = vm_props
      @network_configurator = network_configurator
      @env = env
    end
  end
end
