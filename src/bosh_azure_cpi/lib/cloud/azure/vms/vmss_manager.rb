# frozen_string_literal: true

module Bosh::AzureCloud
  class VMSSManager < VMManagerBase
    def initialize(azure_config, registry_endpoint, disk_manager, disk_manager2, azure_client, storage_account_manager, stemcell_manager, stemcell_manager2, light_stemcell_manager, config_disk_manager)
      super(azure_config.use_managed_disks, azure_client, stemcell_manager, stemcell_manager2, light_stemcell_manager)

      @azure_config = azure_config
      @keep_failed_vms = @azure_config.keep_failed_vms
      @registry_endpoint = registry_endpoint
      @disk_manager = disk_manager
      @disk_manager2 = disk_manager2
      @azure_client = azure_client
      @storage_account_manager = storage_account_manager
      @stemcell_manager = stemcell_manager
      @stemcell_manager2 = stemcell_manager2
      @light_stemcell_manager = light_stemcell_manager
      @use_managed_disks = azure_config.use_managed_disks
      @config_disk_manager = config_disk_manager
      @vmss_batching_manager = VMSSBatchingManager.instance(azure_config, registry_endpoint, disk_manager, disk_manager2, azure_client, storage_account_manager, stemcell_manager, stemcell_manager2, light_stemcell_manager)
    end

    def create(bosh_vm_meta, vm_props, network_configurator, env)
      # steps:
      # 1. get or create the vmss.
      # 2. scale the vmss one node up or create it.
      # 3. prepare one config disk and then attach it.
      CPILogger.instance.logger.info("vmss_create(#{bosh_vm_meta}, #{location}, #{vm_props}, ..., ...)")

      request = VMSSBatchRequest.new(
        bosh_vm_meta,
        location,
        vm_props,
        network_configurator,
        env
      )
      vmss_batching_manager.execute(request)
    end

    def find(instance_id)
      CPILogger.instance.logger.info("vmss_find(#{instance_id})")
      resource_group_name = instance_id.resource_group_name
      vmss_name = instance_id.vmss_name
      instance_id = instance_id.vmss_instance_id
      @azure_client.get_vmss_instance(resource_group_name, vmss_name, instance_id)
    end

    def delete(instance_id)
      CPILogger.instance.logger.info("vmss_delete(#{instance_id})")
      resource_group_name = instance_id.resource_group_name
      vmss_name = instance_id.vmss_name
      vmss_instance_id = instance_id.vmss_instance_id
      vmss_instance = @azure_client.get_vmss_instance(resource_group_name, vmss_name, vmss_instance_id)
      @azure_client.delete_vmss_instance(resource_group_name, vmss_name, vmss_instance_id) if vmss_instance

      vmss_instance[:data_disks]&.each do |data_disk|
        if @config_disk_manager.config_disk?(data_disk[:name])
          CPILogger.instance.logger.info("deleting disk: #{data_disk[:managed_disk][:id]}")
          @disk_manager2.delete_disk(data_disk[:managed_disk][:resource_group_name], data_disk[:name])
          CPILogger.instance.logger.info("deleted disk: #{data_disk[:managed_disk][:id]}")
        end
      end
    end

    def reboot(instance_id)
      CPILogger.instance.logger.info("vmss_reboot(#{instance_id})")
      resource_group_name = instance_id.resource_group_name
      vmss_name = instance_id.vmss_name
      instance_id = instance_id.vmss_instance_id
      @azure_client.reboot_vmss_instance(resource_group_name, vmss_name, instance_id)
    end

    def set_metadata(instance_id, metadata)
      CPILogger.instance.logger.info("vmss_set_metadata(#{instance_id}, #{metadata})")
      resource_group_name = instance_id.resource_group_name
      vmss_name = instance_id.vmss_name
      instance_id = instance_id.vmss_instance_id
      @azure_client.set_vmss_instance_metadata(
        resource_group_name,
        vmss_name,
        instance_id,
        metadata.merge(AZURE_TAGS)
      )
    end

    def attach_disk(instance_id, disk_id)
      CPILogger.instance.logger.info("vmss_attach_disk(#{instance_id}, #{disk_id})")
      resource_group_name = instance_id.resource_group_name
      vmss_name = instance_id.vmss_name
      vmss_instance_id = instance_id.vmss_instance_id
      disk_params = _get_disk_params(disk_id, instance_id.use_managed_disks?)
      lun = _attach_disk(resource_group_name, vmss_name, vmss_instance_id, disk_params)
      raise Bosh::Clouds::CloudError, "Failed to attach disk: #{disk_id} to #{instance_id}." if lun.nil?

      lun.to_s
    end

    def detach_disk(instance_id, disk_id)
      CPILogger.instance.logger.info("vmss_detach_disk(#{instance_id}, #{disk_id})")
      @azure_client.detach_disk_from_vmss_instance(
        instance_id.resource_group_name,
        instance_id.vmss_name,
        instance_id.vmss_instance_id,
        disk_id.disk_name
      )
    end
  end
end
