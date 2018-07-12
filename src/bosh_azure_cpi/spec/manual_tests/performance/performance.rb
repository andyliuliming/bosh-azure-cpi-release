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
  "image" => {"publisher"=>"Canonical", "offer"=>"UbuntuServer", "sku"=>"16.04-LTS", "version"=>"16.04.201611220"}
}
cpi.create_stemcell('', stemcell_properties)

# Test create_vm with a valid stemcell_id
agent_id = "<GUID>"
stemcell_id = "<a-valid-stemcell-id>"
resource_pool = JSON('{"instance_type":"Standard_F1"}')
networks = JSON('{"private":{"cloud_properties":{"subnet_name":"Bosh","virtual_network_name":"boshvnet-crp"},"default":["dns","gateway"],"dns":["168.63.129.16","8.8.8.8"],"gateway":"10.0.0.1","ip":"10.0.0.42","netmask":"255.255.255.0","type":"manual"}}')
instance_id = cpi.create_vm(agent_id, stemcell_id, resource_pool, networks)
puts instance_id