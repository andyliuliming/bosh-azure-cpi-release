

cpi.storage_account_manager.get_storage_account_from_resource_pool(cpi.options['azure'], 'eastasia')

stemcell_properties = {
  "name" => "fake-name",
  "version" => "fake-version",
  "infrastructure" => "azure",
  "hypervisor" => "hyperv",
  "disk" => "30720",
  "disk_format" => "vhd",
  "container_format" => "bare",
  "os_type" => "linux",
  "os_distro" => "ubuntu",
  "architecture" => "x86_64",
  # "image" => {"publisher"=>"Canonical", 
  #   "offer"=>"UbuntuServer", 
  #   "sku"=>"16.04-LTS", 
  #   "version"=>"16.04.201611220"
  # }
}
stempCellName = cpi.create_stemcell(
  '~/Downloads/bosh-stemcell-2222.22-azure-hyperv-ubuntu-xenial-go_agent/image',
  stemcell_properties)

puts stempCellName
# "bosh-stemcell-e412edaf-3a44-46fa-9cac-c667dd232ce8"
# Test create_vm with a valid stemcell_id
agent_id = SecureRandom.uuid
stemcell_id = stempCellName
resource_pool = {
  "instance_type"=>"Standard_A1_v2"
}
networks = JSON('{"private":{"cloud_properties":{"subnet_name":"andliu-performance-bosh-subnet","virtual_network_name":"andliu-performance-vnet"},"default":["dns","gateway"],"dns":["168.63.129.16","8.8.8.8"],"gateway":"10.0.0.1","ip":"10.0.0.42","netmask":"255.255.255.0","type":"manual"}}')
instance_id = cpi.create_vm(agent_id, stemcell_id, resource_pool, networks)
puts instance_id