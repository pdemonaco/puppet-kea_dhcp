# frozen_string_literal: true

require 'spec_helper'

describe 'Kea_Dhcp::DdnsDomain' do
  it {
    is_expected.to allow_value({
                                 'name' => 'test-domain',
    'domain_name' => 'example.com.',
    'direction' => 'forward',
                               })
  }

  it {
    is_expected.to allow_value({
                                 'name' => 'test-reverse',
    'domain_name' => '1.168.192.in-addr.arpa.',
    'direction' => 'reverse',
                               })
  }

  it {
    is_expected.to allow_value({
                                 'name' => 'test-domain',
    'domain_name' => 'example.com.',
    'direction' => 'forward',
    'key_name' => 'my-tsig-key',
                               })
  }

  it {
    is_expected.to allow_value({
                                 'name' => 'test-domain',
    'domain_name' => 'example.com.',
    'direction' => 'forward',
    'dns_servers' => [
      { 'ip-address' => '192.0.2.1' },
    ],
                               })
  }

  it {
    is_expected.to allow_value({
                                 'name' => 'test-domain',
    'domain_name' => 'example.com.',
    'direction' => 'forward',
    'dns_servers' => [
      { 'ip-address' => '192.0.2.1', 'port' => 53 },
    ],
                               })
  }

  it {
    is_expected.to allow_value({
                                 'name' => 'test-domain',
    'domain_name' => 'example.com.',
    'direction' => 'forward',
    'dns_servers' => [
      { 'ip-address' => '192.0.2.1', 'port' => 5353, 'key-name' => 'server-key' },
    ],
                               })
  }

  it {
    is_expected.to allow_value({
                                 'name' => 'test-domain',
    'domain_name' => 'example.com.',
    'direction' => 'forward',
    'dns_servers' => [
      { 'ip-address' => '2001:db8::1' },
    ],
                               })
  }

  it {
    is_expected.to allow_value({
                                 'name' => 'test-domain',
    'domain_name' => 'example.com.',
    'direction' => 'forward',
    'key_name' => 'domain-key',
    'dns_servers' => [
      { 'ip-address' => '192.0.2.1', 'port' => 53 },
      { 'ip-address' => '192.0.2.2', 'port' => 5353, 'key-name' => 'server-key' },
    ],
                               })
  }

  it {
    is_expected.to allow_value({
                                 'name' => 'test-domain',
    'domain_name' => 'example.com.',
    'direction' => 'forward',
    'dns_servers' => [
      { 'ip-address' => '192.0.2.1', 'port' => 1 },
    ],
                               })
  }

  it {
    is_expected.to allow_value({
                                 'name' => 'test-domain',
    'domain_name' => 'example.com.',
    'direction' => 'forward',
    'dns_servers' => [
      { 'ip-address' => '192.0.2.1', 'port' => 65535 },
    ],
                               })
  }

  it {
    is_expected.not_to allow_value({
                                     'domain_name' => 'example.com.',
    'direction' => 'forward',
                                   })
  }

  it {
    is_expected.not_to allow_value({
                                     'name' => 'test-domain',
    'direction' => 'forward',
                                   })
  }

  it {
    is_expected.not_to allow_value({
                                     'name' => 'test-domain',
    'domain_name' => 'example.com.',
                                   })
  }

  it {
    is_expected.not_to allow_value({
                                     'name' => 'test-domain',
    'domain_name' => '',
    'direction' => 'forward',
                                   })
  }

  it {
    is_expected.not_to allow_value({
                                     'name' => 'test-domain',
    'domain_name' => 'example.com.',
    'direction' => 'invalid',
                                   })
  }

  it {
    is_expected.not_to allow_value({
                                     'name' => 'test-domain',
    'domain_name' => 'example.com.',
    'direction' => 'forward',
    'dns_servers' => [
      { 'ip-address' => 'not-an-ip' },
    ],
                                   })
  }

  it {
    is_expected.not_to allow_value({
                                     'name' => 'test-domain',
    'domain_name' => 'example.com.',
    'direction' => 'forward',
    'dns_servers' => [
      { 'port' => 53 },
    ],
                                   })
  }

  it {
    is_expected.not_to allow_value({
                                     'name' => 'test-domain',
    'domain_name' => 'example.com.',
    'direction' => 'forward',
    'dns_servers' => [
      { 'ip-address' => '192.0.2.1', 'port' => 0 },
    ],
                                   })
  }

  it {
    is_expected.not_to allow_value({
                                     'name' => 'test-domain',
    'domain_name' => 'example.com.',
    'direction' => 'forward',
    'dns_servers' => [
      { 'ip-address' => '192.0.2.1', 'port' => 65536 },
    ],
                                   })
  }

  it {
    is_expected.not_to allow_value({
                                     'name' => 'test-domain',
    'domain_name' => 'example.com.',
    'direction' => 'forward',
    'dns_servers' => 'not-an-array',
                                   })
  }
end
