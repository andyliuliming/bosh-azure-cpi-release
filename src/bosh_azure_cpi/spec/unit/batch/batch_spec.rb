# frozen_string_literal: true

require 'spec_helper'
describe Bosh::AzureCloud::Batch do
  describe '#execute' do
    let(:request1) do
      {
        'vmss_name': 'vmss1'
      }
    end
    let(:batch_handler) do
      lambda do |batch_request|
        p ("#### handling the #{batch_request}")
        batch_result = []
        i = 0
        batch_request.each do |req|
          batch_result.push({
            'vmss_instance_id': "#{req[:vmss_name]}#{i}"
          })
          i += 1
        end
        batch_result
      end
    end
    let(:group_key_func) do
      lambda do |request|
        request[:vmss_name]
      end
    end

    context 'when no second item comes' do
      let(:batch) do
        Bosh::AzureCloud::Batch.new(batch_handler, group_key_func)
      end
      it 'should batch one item' do
        batch.execute(request1)
        p ("######## executed.")
        batch.stop
      end
    end

    context 'when second item comes in times' do
      let(:request2) do
        {
          'vmss_name': 'vmss2'
        }
      end
      let(:batch) do
        Bosh::AzureCloud::Batch.new(batch_handler, group_key_func)
      end
      it 'should batch two items' do
        batch.execute(request1)
        batch.execute(request2)
        p ("######## executed.")
        batch.stop
      end
    end
  end
end
