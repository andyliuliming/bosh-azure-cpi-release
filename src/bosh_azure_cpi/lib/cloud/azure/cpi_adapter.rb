# frozen_string_literal: true

module Bosh::AzureCloud
  class CPIAdapter < Bosh::Cloud
    def initialize(context)
      @cloud_local = Bosh::AzureCloud::Cloud.new
      @cloud_remote = _build_cpi_service_client if @cloud_local.config.azure.cpi_service_config.enabled
      @context = context
    end

    ##
    # Returns information about the CPI to help the Director to make decisions
    # on which CPI to call for certain operations in a multi CPI scenario.
    #
    # @return [Hash] Only one key 'stemcell_formats' is supported, which are stemcell formats supported by the CPI.
    #                Currently used in combination with create_stemcell by the Director to determine which CPI to call when uploading a stemcell.
    #
    # @See https://www.bosh.io/docs/cpi-api-v1-method/info/
    #
    def info
      @cloud_local.info
    end

    ##
    # Creates a reusable VM image in the IaaS from the stemcell image. It's used later for creating VMs.
    #
    # @param [String] image_path       Path to the stemcell image extracted from the stemcell tarball on a local filesystem.
    # @param [Hash]   cloud_properties Cloud properties hash extracted from the stemcell tarball.
    #
    # @return [String] stemcell_cid Cloud ID of the created stemcell. It's used later by create_vm and delete_stemcell.
    #
    # @See https://www.bosh.io/docs/cpi-api-v1-method/create-stemcell/
    #
    def create_stemcell(image_path, cloud_properties)
      @cloud_local.create_stemcell(image_path, cloud_properties)
    end

    ##
    # Deletes previously created stemcell. Assume that none of the VMs require presence of the stemcell.
    #
    # @param [String] stemcell_cid Cloud ID of the stemcell to delete; returned from create_stemcell.
    #
    # @return [void]
    #
    # @See https://www.bosh.io/docs/cpi-api-v1-method/delete-stemcell/
    #
    def delete_stemcell(stemcell_cid)
      @cloud_local.delete_stemcell(stemcell_cid)
    end

    ##
    # Creates a new VM based on the stemcell.
    # Created VM must be powered on and accessible on the provided networks.
    # Waiting for the VM to finish booting is not required because the Director waits until the Agent on the VM responds back.
    # Make sure to properly delete created resources if VM cannot be successfully created.
    #
    # @param [String]           agent_id         ID selected by the Director for the VM's agent
    # @param [String]           stemcell_cid     Cloud ID of the stemcell to use as a base image for new VM,
    #                                            which was once returned by {#create_stemcell}
    # @param [Hash]             cloud_properties Cloud properties hash specified in the deployment manifest under VM's resource pool.
    #                                            https://bosh.io/docs/azure-cpi/#resource-pools
    # @param [Hash]             networks         Networks hash that specifies which VM networks must be configured.
    # @param [Array of strings] disk_cids        Array of disk cloud IDs for each disk that created VM will most likely be attached;
    #                                            they could be used to optimize VM placement so that disks are located nearby.
    # @param [Hash]             environment      Resource pool's env hash specified in deployment manifest including initial properties added by the BOSH director.
    #
    # @return [String] vm_cid Cloud ID of the created VM. Later used by {#attach_disk}, {#detach_disk} and {#delete_vm}.
    #
    # @See https://www.bosh.io/docs/cpi-api-v1-method/create-vm/
    #
    def create_vm(agent_id, stemcell_cid, cloud_properties, networks, disk_cids = nil, environment = nil)
      if @cloud_local.config.azure.cpi_service_config.enabled
        begin
          CPILogger.instance.warn("########### creating vm1. #{JSON.dump(environment)}")
          req = Bosh::CpiService::Models::CreateVMRequest.new(
            context: {
              context_str: JSON.dump(@context)
            },
            agent_id: agent_id,
            stemcell_cid: stemcell_cid,
            cloud_properties: JSON.dump(cloud_properties),
            networks: JSON.dump(networks),
            disk_cids: disk_cids,
            environment: JSON.dump(environment)
          )
          CPILogger.instance.warn("########### creating vm.")
          create_vm_response = @cloud_remote.create_vm(req)
          CPILogger.instance.warn("########### created vm.")
          # cloud_properties_str = JSON.dump(cloud_properties)
          # optional :agent_id, :string, 1
          # optional :stemcell_cid, :string, 2
          # repeated :dick_cids, :string, 3
          # map :env, :string, :string, 4
          # optional :cloud_properties, :string, 5
          # optional :networks, :string, 6
          # Cloud::CpiService::Models::CreateVMRequest.new()
          CPILogger.instance.info("########## create vm response: #{create_vm_response}.")
        rescue StandardError => e
          CPILogger.instance.error("##### #{e}")
        end
        @cloud_local.create_vm(agent_id, stemcell_cid, cloud_properties, networks, disk_cids, environment)
      else
        @cloud_local.create_vm(agent_id, stemcell_cid, cloud_properties, networks, disk_cids, environment)
      end
    end

    ##
    # Deletes the VM.
    # This method will be called while the VM still has persistent disks attached.
    # It's important to make sure that IaaS behaves appropriately in this case and properly disassociates persistent disks from the VM.
    # To avoid losing track of VMs, make sure to raise an error if VM deletion is not absolutely certain.
    #
    # @param [String] vm_cid Cloud ID of the VM to delete; returned from create_vm.
    #
    # @return [void]
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/delete-vm/
    #
    def delete_vm(vm_cid)
      @cloud_local.delete_vm(vm_cid)
    end

    ##
    # Checks for VM presence in the IaaS.
    # This method is mostly used by the consistency check tool (cloudcheck) to determine if the VM still exists.
    #
    # @param [String] vm_cid Cloud ID of the VM to check; returned from create_vm.
    #
    # @return [Boolean] exists True if VM is present.
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/has-vm/
    #
    def has_vm?(vm_cid)
      @cloud_local.has_vm?(vm_cid)
    end

    ##
    # Reboots the VM. Assume that VM can be either be powered on or off at the time of the call.
    # Waiting for the VM to finish rebooting is not required because the Director waits until the Agent on the VM responds back.
    #
    # @param [String] vm_cid Cloud ID of the VM to reboot; returned from create_vm.
    #
    # @return [void]
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/reboot-vm/
    #
    def reboot_vm(vm_cid)
      @cloud_local.reboot_vm(vm_cid)
    end

    ##
    # Sets VM's metadata to make it easier for operators to categorize VMs when looking at the IaaS management console.
    #
    # @param [String] vm_cid   Cloud ID of the VM to modify; returned from create_vm.
    # @param [Hash]   metadata Collection of key-value pairs. CPI should not rely on presence of specific keys.
    #
    # @return [void]
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/set-vm-metadata/
    #
    def set_vm_metadata(vm_cid, metadata)
      @cloud_local.set_vm_metadata(vm_cid, metadata)
    end

    ##
    # Returns a hash that can be used as VM cloud_properties when calling create_vm; it describes the IaaS instance type closest to the arguments passed.
    #
    # @param  [Hash] desired_instance_size Parameters of the desired size of the VM consisting of the following keys:
    #                                      cpu [Integer]: Number of virtual cores desired
    #                                      ram [Integer]: Amount of RAM, in MiB (i.e. 4096 for 4 GiB)
    #                                      ephemeral_disk_size [Integer]: Size of ephemeral disk, in MB
    #
    # @return [Hash] cloud_properties an IaaS-specific set of cloud properties that define the size of the VM.
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/calculate-vm-cloud-properties/
    #
    def calculate_vm_cloud_properties(desired_instance_size)
      @cloud_local.calculate_vm_cloud_properties(desired_instance_size)
    end

    ##
    # Creates disk with specific size. Disk does not belong to any given VM.
    #
    # @param [Integer]          size             Size of the disk in MiB.
    # @param [Hash]             cloud_properties Cloud properties hash specified in the deployment manifest under the disk pool.
    #                                            https://bosh.io/docs/azure-cpi/#disk-pools
    # @param [optional, String] vm_cid           Cloud ID of the VM created disk will most likely be attached;
    #                                            it could be used to .optimize disk placement so that disk is located near the VM.
    #
    # @return [String] disk_cid Cloud ID of the created disk. It's used later by attach_disk, detach_disk, and delete_disk.
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/create-disk/
    #
    def create_disk(size, cloud_properties, vm_cid = nil)
      @cloud_local.create_disk(size, cloud_properties, vm_cid)
    end

    ##
    # Deletes disk. Assume that disk was detached from all VMs.
    # To avoid losing track of disks, make sure to raise an error if disk deletion is not absolutely certain.
    #
    # @param [String] disk_cid Cloud ID of the disk to delete; returned from create_disk.
    #
    # @return [void]
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/delete-disk/
    #
    def delete_disk(disk_cid)
      @cloud_local.delete_disk(disk_cid)
    end

    ##
    # Resizes disk with IaaS-native methods. Assume that disk was detached from all VMs.
    # Set property director.enable_cpi_resize_disk to true to have the Director call this method.
    # Depending on the capabilities of the underlying infrastructure, this method may raise an
    # Bosh::Clouds::NotSupported error when the new_size is smaller than the current disk size.
    # The same error is raised when the method is not implemented.
    # If Bosh::Clouds::NotSupported is raised, the Director falls back to creating a new disk and copying data.
    #
    # @param [String]  disk_cid Cloud ID of the disk to check; returned from create_disk.
    # @param [Integer] new_size New disk size in MiB.
    #
    # @return [void]
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/resize-disk/
    #
    def resize_disk(disk_cid, new_size)
      @cloud_local.resize_disk(disk_cid, new_size)
    end

    ##
    # Checks for disk presence in the IaaS.
    # This method is mostly used by the consistency check tool (cloudcheck) to determine if the disk still exists.
    #
    # @param [String] disk_cid Cloud ID of the disk to check; returned from create_disk.
    #
    # @return [Boolean] True if disk is present.
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/has-disk/
    #
    def has_disk?(disk_cid)
      @cloud_local.has_disk?(disk_cid)
    end

    ##
    # Attaches disk to the VM.
    # Typically each VM will have one disk attached at a time to store persistent data;
    # however, there are important cases when multiple disks may be attached to a VM.
    # Most common scenario involves persistent data migration from a smaller to a larger disk.
    # Given a VM with a smaller disk attached, the operator decides to increase the disk size for that VM,
    # so new larger disk is created, it is then attached to the VM.
    # The Agent then copies over the data from one disk to another, and smaller disk subsequently is detached and deleted.
    # Agent settings should have been updated with necessary information about given disk.
    #
    # @param [String] vm_cid   Cloud ID of the VM.
    # @param [String] disk_cid Cloud ID of the disk.
    #
    # @return [void]
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/attach-disk/
    #
    def attach_disk(vm_cid, disk_cid)
      @cloud_local.attach_disk(vm_cid, disk_cid)
    end

    ##
    # Detaches disk from the VM.
    # If the persistent disk is attached to a VM that will be deleted, it's more likely delete_vm CPI
    # method will be called without a call to detach_disk with an expectation that delete_vm will
    # make sure disks are disassociated from the VM upon its deletion.
    # Agent settings should have been updated to remove information about given disk.
    #
    # @param [String] vm_cid   Cloud ID of the VM.
    # @param [String] disk_cid Cloud ID of the disk.
    #
    # @return [void]
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/detach-disk/
    #
    def detach_disk(vm_cid, disk_cid)
      @cloud_local.detach_disk(vm_cid, disk_cid)
    end

    ##
    # Sets disk's metadata to make it easier for operators to categorize disks when looking at the IaaS management console.
    # Disk metadata is written when the disk is attached to a VM. Metadata is not removed when disk is detached or VM is deleted.
    #
    # @param [String] disk_cid Cloud ID of the disk to modify; returned from create_disk.
    # @param [Hash]   metadata Collection of key-value pairs. CPI should not rely on presence of specific keys.
    #
    # @return [void]
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/set-disk-metadata/
    #
    def set_disk_metadata(disk_cid, metadata)
      @cloud_local.set_disk_metadata(disk_cid, metadata)
    end

    ##
    # Returns list of disks currently attached to the VM.
    # This method is mostly used by the consistency check tool (cloudcheck) to determine if the VM has required disks attached.
    #
    # @param [String] vm_cid Cloud ID of the VM.
    #
    # @return [Array of strings] disk_cids Array of disk_cid that are currently attached to the VM.
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/get-disks/
    #
    def get_disks(vm_cid)
      @cloud_local.get_disks(vm_cid)
    end

    ##
    # Takes a snapshot of the disk.
    #
    # @param [String] disk_cid Cloud ID of the disk.
    # @param [Hash]   metadata Collection of key-value pairs. CPI should not rely on presence of specific keys.
    #
    # @return [String] snapshot_cid Cloud ID of the disk snapshot.
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/snapshot-disk/
    #
    def snapshot_disk(disk_cid, metadata = {})
      @cloud_local.snapshot_disk(disk_cid, metadata)
    end

    ##
    # Deletes the disk snapshot.
    #
    # @param [String] snapshot_cid Cloud ID of the disk snapshot.
    #
    # @return [void]
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/delete-snapshot/
    #
    def delete_snapshot(snapshot_cid)
      @cloud_local.delete_snapshot(snapshot_cid)
    end

    ##
    # The recommended implementation is to raise Bosh::Clouds::NotSupported error. This method will be deprecated in API v2.
    # After the Director received NotSupported error, it will delete the VM (via delete_vm) and create a new VM with desired network configuration (via create_vm).
    #
    # @param [String] vm_cid   Cloud ID of the VM to modify; returned from create_vm.
    # @param [Hash]   networks Network hashes that specify networks VM must be configured.
    #
    # @return [void]
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/configure-networks/
    #
    def configure_networks(vm_cid, networks)
      @cloud_local.configure_networks(vm_cid, networks)
    end

    ##
    # Determines cloud ID of the VM executing the CPI code. Currently used in combination with get_disks by the Director to determine which disks to self-snapshot.
    # Do not implement; this method will be deprecated and removed.
    #
    # @return [String] vm_cid Cloud ID of the VM.
    #
    # @See https://bosh.io/docs/cpi-api-v1-method/current-vm-id/
    #
    def current_vm_id
      @cloud_local.current_vm_id
    end

    private

    def _load_certs(cpi_service_config)
      files = [
        cpi_service_config.cpi_service_ca_path,
        cpi_service_config.cpi_service_client_private_key,
        cpi_service_config.cpi_service_client_certificate
      ]
      files.map { |f| File.open(f).read }
    end

    def _build_cpi_service_client
      certs = _load_certs(@cloud_local.config.azure.cpi_service_config)

      creds = GRPC::Core::ChannelCredentials.new(certs[0], certs[1], certs[2])
      # p "localhost:#{config.azure.cpi_service_config.port}"

      stub = Bosh::CpiService::Service::CPI::Stub.new(
        "localhost:#{@cloud_local.config.azure.cpi_service_config.port}", creds)
      stub
    end
  end
end
