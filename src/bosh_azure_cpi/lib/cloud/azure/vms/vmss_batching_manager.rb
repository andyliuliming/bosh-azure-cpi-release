# frozen_string_literal: true

module Bosh::AzureCloud
  class VMSSBatchingManager < VMManagerBase
    @@singleton__instance__ = nil
    @@singleton__mutex__ = Mutex.new
    def self.instance(azure_config, registry_endpoint, disk_manager, disk_manager2, azure_client, storage_account_manager, stemcell_manager, stemcell_manager2, light_stemcell_manager)
      return @@singleton__instance__ if @@singleton__instance__
      @@singleton__mutex__.synchronize {
        return @@singleton__instance__ if @@singleton__instance__
        @@singleton__instance__ = new(azure_config, registry_endpoint, disk_manager, disk_manager2, azure_client, storage_account_manager, stemcell_manager, stemcell_manager2, light_stemcell_manager)
      }
      @@singleton__instance__
    end

    private

    def initialize(azure_config, registry_endpoint, disk_manager, disk_manager2, azure_client, storage_account_manager, stemcell_manager, stemcell_manager2, light_stemcell_manager)
      super(azure_config.use_managed_disks, azure_client, stemcell_manager, stemcell_manager2, light_stemcell_manager)

      batch_handler = lambda do |batch_request|
        # make assumption the items in the batch request are the same.
        begin
          bosh_vm_meta = batch_request.bosh_vm_meta
          vm_props = batch_request.vm_props
          network_configurator = batch_request.network_configurator
          env = batch_request.env

          resource_group_name = vm_props.resource_group_name
          vmss_name = _get_vmss_name(vm_props, env)
          _ensure_resource_group_exists(resource_group_name, location)

          existing_vmss = @azure_client.get_vmss_by_name(resource_group_name, vmss_name)
          vmss_params = {}
          stemcell_info = _get_stemcell_info(bosh_vm_meta.stemcell_cid, vm_props, nil)
          vmss_instance_id = nil # this is the instance id like '1', '2', concept in vmss.
          vm_name = nil
          vmss_instance_zone = nil

          # we should group the vmss operation by the vmss_name, stemcell_cid.
          # why we need group by the stemcell_info is that each instance
          # can use different stemcell.
          if existing_vmss.nil?
            vmss_params = {
              availability_zones: vm_props.vmss.availability_zones,
              vmss_name: vmss_name,
              location: location,
              instance_type: vm_props.instance_type
            }
            vmss_params[:image_id] = stemcell_info.uri
            vmss_params[:os_type] = stemcell_info.os_type

            raise ArgumentError, "Unsupported os type: #{vmss_params[:os_type]}" if stemcell_info.os_type != 'linux'

            vmss_params[:ssh_username]  = @azure_config.ssh_user
            vmss_params[:ssh_cert_data] = @azure_config.ssh_public_key
            # there's extra name field in os_disk and ephemeral_disk, will ignore it when creating vmss.
            vmss_params[:os_disk], vmss_params[:ephemeral_disk] = _build_vmss_disks(vmss_name, stemcell_info, vm_props)

            network_interfaces = []
            vmss_params[:initial_capacity] = 1
            networks = network_configurator.networks
            networks.each_with_index do |network, _|
              subnet = _get_network_subnet(network)
              network_security_group = _get_network_security_group(vm_props, network)
              network_interfaces.push(subnet: subnet, network_security_group: network_security_group)
            end
            # TODO: handle the application gateway, public ip too.
            unless vm_props.load_balancer.name.nil?
              load_balancer = @azure_client.get_load_balancer_by_name(vm_props.load_balancer.resource_group_name, vm_props.load_balancer.name)
              vmss_params[:load_balancer] = load_balancer
            end
            flock(vmss_name.to_s, File::LOCK_EX) do
              @azure_client.create_vmss(resource_group_name, vmss_params, network_interfaces)
              vmss_instances_result = @azure_client.get_vmss_instances(resource_group_name, vmss_name)
              first_instance = vmss_instances_result[0]
              vmss_instance_id = first_instance[:instanceId]
              vm_name = first_instance[:name]
              vmss_instance_zone = first_instance[:zones]
            end
          else
            vmss_params[:os_disk], vmss_params[:ephemeral_disk] = _build_vmss_disks(vmss_name, stemcell_info, vm_props)
            # TODO: create one task to batch the scale up.
            flock(vmss_name.to_s, File::LOCK_EX) do
              existing_instances = @azure_client.get_vmss_instances(resource_group_name, vmss_name)
              @azure_client.update_vmss_sku(resource_group_name, vmss_name, 1)
              updated_instances = @azure_client.get_vmss_instances(resource_group_name, vmss_name)
              vmss_instance_id, vm_name, vmss_instance_zone = _get_newly_created_instance(existing_instances, updated_instances)
            end
          end
          instance_id = _build_instance_id(bosh_vm_meta, vm_props, vmss_name, vmss_instance_id)
          meta_data_obj = Bosh::AzureCloud::BoshAgentUtil.get_meta_data_obj(
            instance_id.to_s,
            @azure_config.ssh_public_key
          )

          vmss_params[:name] = vm_name
          user_data_obj = Bosh::AzureCloud::BoshAgentUtil.get_user_data_obj(@registry_endpoint, instance_id.to_s, network_configurator.default_dns)

          config_disk_id, = @config_disk_manager.prepare_config_disk(
            resource_group_name,
            vm_name,
            vm_props.location,
            vmss_instance_zone.nil? ? nil : vmss_instance_zone[0],
            meta_data_obj,
            user_data_obj
          )

          disk_params = _get_disk_params(config_disk_id, instance_id.use_managed_disks?)

          _attach_disk(resource_group_name, vmss_name, vmss_instance_id, disk_params)
        rescue StandardError => e
          error_message = nil
          if !vmss_instance_id.nil?
            error_message = 'New instance in VMSS created, but probably config disk failed to attach.'
            error_message += "\t Resource Group: #{resource_group_name}\n"
            error_message += "\t Virtual Machine Scale Set: #{vmss_name}\n"
            error_message += "\t Instance Id: #{vmss_instance_id}\n"
          else
            error_message = 'Instance not created.'
          end
          if @keep_failed_vms
            error_message += 'You need to delete the vm instance created after finishing investigation.\n'
          else
            @azure_client.delete_vmss_instance(resource_group_name, vmss_name, vmss_instance_id) unless vmss_instance_id.nil?
          end
          raise Bosh::Clouds::VMCreationFailed.new(false), "#{error_message}\n#{e.backtrace.join("\n")}"
        end
      end
      group_key_func = lambda do |request|
        _get_vmss_name(request.vm_props, request.env)
      end
      @batch = Batch.new(batch_handler, group_key_func)
    end

    private_class_method :new

    def execute(request)
      @batch.execute(request)
    end

    private

    def _build_vmss_disks(vmss_name, stemcell_info, vm_props)
      # TODO: add support for the unmanaged disk.
      os_disk = @disk_manager2.os_disk(vmss_name, stemcell_info, vm_props.root_disk.size, vm_props.caching, vm_props.ephemeral_disk.use_root_disk)
      ephemeral_disk = @disk_manager2.ephemeral_disk(vmss_name, vm_props.instance_type, vm_props.ephemeral_disk.size, vm_props.ephemeral_disk.type, vm_props.ephemeral_disk.use_root_disk)
      [os_disk, ephemeral_disk]
    end

    # returns instance_id, name
    def _get_newly_created_instance(old, newly)
      old_instance_ids = old.map { |row| row[:instanceId] }
      new_instance_ids = newly.map { |row| row[:instanceId] }
      created_instance_ids = new_instance_ids - old_instance_ids
      CPILogger.instance.logger.info("old_instance_ids: #{old_instance_ids} new_instance_ids #{new_instance_ids}")
      raise Bosh::Clouds::CloudError, 'more instance found.' if created_instance_ids.length != 1

      insatnce_id = created_instance_ids[0]
      instance = newly.find { |i| i[:instanceId] == insatnce_id }
      [instance[:instanceId], instance[:name], instance[:zones]]
    end

    def _build_instance_id(bosh_vm_meta, vm_props, vmss_name, vmss_instance_id)
      # TODO: add support for the unmanaged disk.
      instance_id = VMSSInstanceId.create(vm_props.resource_group_name, bosh_vm_meta.agent_id, vmss_name, vmss_instance_id)
      instance_id
    end

    def _attach_disk(resource_group_name, vmss_name, vmss_instance_id, disk_params)
      CPILogger.instance.logger.info("attaching disk #{disk_params[:disk_id]} to #{resource_group_name} #{vmss_name} #{vmss_instance_id}")
      @azure_client.attach_disk_to_vmss_instance(resource_group_name, vmss_name, vmss_instance_id, disk_params)
    end

    def _get_vmss_name(vm_props, env)
      # use the bosh group as the vmss name.
      # this would be published, tracking issue here: https://github.com/cloudfoundry/bosh/issues/2034

      vm_props.vmss.name if !vm_props.vmss.nil? && !vm_props.vmss.name.nil?

      bosh_group_exists = env.nil? || env['bosh'].nil? || env['bosh']['group'].nil?
      if !bosh_group_exists
        vmss_name = env['bosh']['group']
        # max windows vmss name length 15
        # max linux vmss name length 63
        if vmss_name.size > 63
          md = Digest::MD5.hexdigest(vmss_name) # 32
          vmss_name = "vmss-#{md}-#{vmss_name[-31..-1]}"
        end
        vmss_name
      else
        cloud_error('currently the bosh group should be there, later will add the support without the group.')
      end
    end
  end
end
