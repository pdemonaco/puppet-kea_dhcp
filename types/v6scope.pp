# @summary Utility type for declaring multiple DHCPv6 scopes
#
# @param name
#   Unique identifier for the scope used only by Puppet
#
# @param subnet
#   CIDR representation of the IPv6 subnet (e.g., '2001:db8:1::/64')
#
# @param id
#   Optional numeric identifier for the scope. Set to 'auto' to use the next free identifier.
#   Defaults to 'auto' if not specified
#
# @param options
#   Optional array of DHCP option hashes. Each hash must contain 'name' and 'data' keys
#
# @param pools
#   Optional array of pool definitions. Each entry can be an IPv6 CIDR (e.g., '2001:db8:1:05::/80')
#   or an IPv6 range (e.g., '2001:db8:1::1 - 2001:db8:1::ffff')
#
# @param pd_pools
#   Optional array of prefix delegation pool hashes. Each hash must contain
#   'prefix', 'prefix-len', and 'delegated-len' keys
type Kea_Dhcp::V6Scope = Struct[
  name                => String,
  subnet              => Stdlib::IP::Address::V6::CIDR,
  Optional[id]        => Variant[Integer[0], Enum['auto']],
  Optional[options]   => Array[Hash],
  Optional[pools]     => Array[String],
  Optional[pd_pools]  => Array[Hash],
]
