# frozen_string_literal: true

require 'spec_helper'

describe 'Kea_Dhcp::V4Reservation' do
  it {
    is_expected.to allow_value({
                                 'name' => 'test-host',
    'identifier' => '01:aa:bb:cc:dd:ee:ff',
    'identifier_type' => 'hw-address',
    'ip_address' => '192.0.2.100',
                               })
  }

  it {
    is_expected.to allow_value({
                                 'name' => 'test-host',
    'identifier' => '01-aa-bb-cc-dd-ee-ff',
    'identifier_type' => 'client-id',
    'ip_address' => '10.20.30.40',
                               })
  }

  it {
    is_expected.to allow_value({
                                 'name' => 'test-host',
    'identifier' => 'ab:cd:ef:12:34:56',
    'identifier_type' => 'hw-address',
    'ip_address' => '192.0.2.100',
    'hostname' => 'test.example.com',
                               })
  }

  it {
    is_expected.to allow_value({
                                 'name' => 'test-host',
    'identifier' => 'AB:CD:EF:12:34:56',
    'identifier_type' => 'hw-address',
    'ip_address' => '192.0.2.100',
    'scope_id' => 100,
                               })
  }

  it {
    is_expected.to allow_value({
                                 'name' => 'test-host',
    'identifier' => '01:aa:bb:cc:dd:ee',
    'identifier_type' => 'hw-address',
    'ip_address' => '192.0.2.100',
    'scope_id' => 'auto',
                               })
  }

  it {
    is_expected.to allow_value({
                                 'name' => 'test-host',
    'identifier' => '01:aa:bb:cc:dd:ee:ff',
    'identifier_type' => 'hw-address',
    'ip_address' => '192.0.2.100',
    'hostname' => 'host.example.com',
    'scope_id' => 42,
                               })
  }

  it {
    is_expected.not_to allow_value({
                                     'name' => 'test-host',
    'identifier' => 'not-a-mac',
    'identifier_type' => 'hw-address',
    'ip_address' => '192.0.2.100',
                                   })
  }

  it {
    is_expected.not_to allow_value({
                                     'name' => 'test-host',
    'identifier' => '01:aa:bb:cc:dd:ee:ff',
    'identifier_type' => 'invalid-type',
    'ip_address' => '192.0.2.100',
                                   })
  }

  it {
    is_expected.not_to allow_value({
                                     'name' => 'test-host',
    'identifier' => '01:aa:bb:cc:dd:ee:ff',
    'identifier_type' => 'hw-address',
    'ip_address' => 'not-an-ip',
                                   })
  }

  it {
    is_expected.not_to allow_value({
                                     'name' => 'test-host',
    'identifier' => '01:aa:bb:cc:dd:ee:ff',
    'identifier_type' => 'hw-address',
    'ip_address' => '192.0.2.256',
                                   })
  }

  it {
    is_expected.not_to allow_value({
                                     'identifier' => '01:aa:bb:cc:dd:ee:ff',
    'identifier_type' => 'hw-address',
    'ip_address' => '192.0.2.100',
                                   })
  }

  it {
    is_expected.not_to allow_value({
                                     'name' => 'test-host',
    'identifier_type' => 'hw-address',
    'ip_address' => '192.0.2.100',
                                   })
  }

  it {
    is_expected.not_to allow_value({
                                     'name' => 'test-host',
    'identifier' => '01:aa:bb:cc:dd:ee:ff',
    'ip_address' => '192.0.2.100',
                                   })
  }

  it {
    is_expected.not_to allow_value({
                                     'name' => 'test-host',
    'identifier' => '01:aa:bb:cc:dd:ee:ff',
    'identifier_type' => 'hw-address',
                                   })
  }

  it {
    is_expected.not_to allow_value({
                                     'name' => 'test-host',
    'identifier' => '01:aa:bb:cc:dd:ee:ff',
    'identifier_type' => 'hw-address',
    'ip_address' => '192.0.2.100',
    'scope_id' => -1,
                                   })
  }

  it {
    is_expected.not_to allow_value({
                                     'name' => 'test-host',
    'identifier' => '01:aa:bb:cc:dd:ee:ff',
    'identifier_type' => 'hw-address',
    'ip_address' => '192.0.2.100',
    'scope_id' => 'not-auto',
                                   })
  }
end
