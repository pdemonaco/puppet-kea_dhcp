# frozen_string_literal: true

require 'spec_helper'

describe 'Kea_Dhcp::TsigKey' do
  # Valid secret variant
  it { is_expected.to allow_value({ 'name' => 'k', 'algorithm' => 'HMAC-SHA256', 'secret' => 'abc==' }) }
  it { is_expected.to allow_value({ 'name' => 'k', 'algorithm' => 'HMAC-MD5', 'secret' => 'abc==' }) }
  it { is_expected.to allow_value({ 'name' => 'k', 'algorithm' => 'HMAC-SHA512', 'secret' => 'abc==' }) }

  # Valid secret_file_content variant
  it { is_expected.to allow_value({ 'name' => 'k', 'algorithm' => 'HMAC-SHA256', 'secret_file_content' => 'abc==' }) }

  # Invalid: unknown algorithm
  it { is_expected.not_to allow_value({ 'name' => 'k', 'algorithm' => 'HMAC-INVALID', 'secret' => 'abc==' }) }

  # Invalid: missing name
  it { is_expected.not_to allow_value({ 'algorithm' => 'HMAC-SHA256', 'secret' => 'abc==' }) }

  # Invalid: missing algorithm
  it { is_expected.not_to allow_value({ 'name' => 'k', 'secret' => 'abc==' }) }

  # Invalid: neither secret nor secret_file_content
  it { is_expected.not_to allow_value({ 'name' => 'k', 'algorithm' => 'HMAC-SHA256' }) }

  # Invalid: empty name
  it { is_expected.not_to allow_value({ 'name' => '', 'algorithm' => 'HMAC-SHA256', 'secret' => 'abc==' }) }

  # Invalid: not a hash
  it { is_expected.not_to allow_value('just-a-string') }
  it { is_expected.not_to allow_value(42) }

  # Invalid: both variants combined (extra key not allowed by Struct)
  it {
    is_expected.not_to allow_value({
                                     'name' => 'k',
                                     'algorithm' => 'HMAC-SHA256',
                                     'secret' => 'a',
                                     'secret_file_content' => 'b',
                                   })
  }
end
