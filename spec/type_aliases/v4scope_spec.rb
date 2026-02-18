# frozen_string_literal: true

require 'spec_helper'

describe 'Kea_Dhcp::V4Scope' do
  it {
    is_expected.to allow_value({
                                 'subnet' => '192.0.2.0/24',
                               })
  }

  it {
    is_expected.to allow_value({
                                 'subnet' => '10.0.0.0/8',
    'pools' => ['10.0.0.0/28', '10.0.0.32 - 10.0.0.63'],
                               })
  }

  it {
    is_expected.to allow_value({
                                 'subnet' => '172.16.0.0/12',
    'id' => 100,
                               })
  }

  it {
    is_expected.to allow_value({
                                 'subnet' => '192.168.1.0/24',
    'id' => 'auto',
                               })
  }

  it {
    is_expected.to allow_value({
                                 'subnet' => '192.0.2.0/24',
    'options' => [
      { 'name' => 'routers', 'data' => '192.0.2.1' },
      { 'name' => 'domain-name-servers', 'data' => '8.8.8.8' },
    ],
                               })
  }

  it {
    is_expected.to allow_value({
                                 'subnet' => '192.0.2.0/24',
    'id' => 42,
    'pools' => ['192.0.2.100 - 192.0.2.200'],
    'options' => [{ 'name' => 'routers', 'data' => '192.0.2.1' }],
                               })
  }

  it {
    is_expected.to allow_value({
                                 'subnet' => '10.20.30.0/24',
    'pools' => ['10.20.30.0/26'],
                               })
  }

  it {
    is_expected.to allow_value({
                                 'subnet' => '192.0.2.0/24',
    'id' => 0,
                               })
  }

  it {
    is_expected.not_to allow_value({
                                     'subnet' => 'not-a-subnet',
                                   })
  }

  it {
    is_expected.not_to allow_value({
                                     'subnet' => '192.0.2.0',
                                   })
  }

  it {
    is_expected.not_to allow_value({
                                     'subnet' => '192.0.2.0/33',
                                   })
  }

  it {
    is_expected.not_to allow_value({
                                     'subnet' => '192.0.2.0/24',
    'id' => -1,
                                   })
  }

  it {
    is_expected.not_to allow_value({
                                     'subnet' => '192.0.2.0/24',
    'id' => 'not-auto',
                                   })
  }

  it {
    is_expected.not_to allow_value({
                                     'subnet' => '192.0.2.0/24',
    'pools' => 'not-an-array',
                                   })
  }

  it {
    is_expected.not_to allow_value({
                                     'subnet' => '192.0.2.0/24',
    'options' => 'not-an-array',
                                   })
  }
end
