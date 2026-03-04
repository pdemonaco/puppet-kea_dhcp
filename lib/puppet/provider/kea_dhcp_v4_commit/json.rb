# frozen_string_literal: true

require_relative '../../../puppet_x/kea_dhcp/provider/dhcp4_json'

Puppet::Type.type(:kea_dhcp_v4_commit).provide(:json, parent: PuppetX::KeaDhcp::Provider::Dhcp4Json) do
  desc 'Commits all staged Kea DHCPv4 configuration changes to disk.'

  def applied
    self.class.dirty_paths.empty? ? 'committed' : 'pending'
  end

  def applied=(_value)
    # no-op: actual work happens in flush
  end

  def flush
    self.class.commit_all!
  end
end
