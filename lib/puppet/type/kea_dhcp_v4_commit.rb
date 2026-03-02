# frozen_string_literal: true

Puppet::Type.newtype(:kea_dhcp_v4_commit) do
  @doc = 'Internal: commits staged Kea DHCPv4 changes to disk. Auto-created by kea_dhcp_v4_server, kea_dhcp_v4_scope, and kea_dhcp_v4_reservation resources.'

  newparam(:name, namevar: true) do
    desc 'Path to the kea-dhcp4 configuration file being committed.'
  end

  newproperty(:applied) do
    desc 'Internal: tracks whether pending configuration changes have been committed.'
    defaultto 'committed'

    def insync?(is)
      is == 'committed'
    end
  end

  autorequire(:kea_dhcp_v4_server) do
    catalog.resources.select { |r| r.is_a?(Puppet::Type.type(:kea_dhcp_v4_server)) }
  end

  autorequire(:kea_dhcp_v4_scope) do
    catalog.resources.select { |r| r.is_a?(Puppet::Type.type(:kea_dhcp_v4_scope)) }
  end

  autorequire(:kea_dhcp_v4_reservation) do
    catalog.resources.select { |r| r.is_a?(Puppet::Type.type(:kea_dhcp_v4_reservation)) }
  end
end
