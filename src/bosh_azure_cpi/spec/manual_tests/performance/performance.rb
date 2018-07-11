#!/usr/bin/env ruby
# frozen_string_literal: true

load '../common/helpers.rb'

cpi = get_cpi(@upstream_repo, 'v35.3', false)

resource_pool = {
  'instance_type' => 'Standard_A1_v2',
  'assign_dynamic_public_ip' => true,
  'availability_set' => 'managed-avset',
  'storage_account_name' => @vm_storage_account_name,
  'storage_account_type' => 'Standard_LRS'
}

instance_id = create_vm(cpi, resource_pool)

delete_vm(cpi, instance_id)

puts 'PASS'
