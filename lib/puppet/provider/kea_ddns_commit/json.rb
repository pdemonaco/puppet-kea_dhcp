# frozen_string_literal: true

require_relative '../../../puppet_x/kea_dhcp/provider/ddns_json'

Puppet::Type.type(:kea_ddns_commit).provide(:json, parent: PuppetX::KeaDhcp::Provider::DdnsJson) do
  desc 'Commits staged Kea DHCP-DDNS configuration changes.'

  def applied
    self.class.dirty_paths.empty? ? 'committed' : 'pending'
  end

  def applied=(_value); end

  def flush
    self.class.commit_all!
  end
end
