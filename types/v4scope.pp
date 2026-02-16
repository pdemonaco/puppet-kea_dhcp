# @summary Utility type for declaring multiple scopes
#
# @param name
#   Unique identifier for the scope used only by Puppet
#
# @param subnet
#   CIDR representation of the subnet (e.g., '192.168.1.0/24')
#
# @param id
#   Optional numeric identifier for the scope. Set to 'auto' to use the next free identifier.
#   Defaults to 'auto' if not specified
#
# @param options
#   Optional array of DHCP option hashes. Each hash must contain 'name' and 'data' keys
#
# @param pools
#   Optional array of pool definitions. Each entry can be a CIDR (e.g., '10.0.0.0/28')
#   or an IPv4 range (e.g., '10.0.0.1 - 10.0.0.254')
type Kea_Dhcp::V4Scope = Struct[
  name              => String,
  subnet            => Stdlib::IP::Address::V4::CIDR,
  Optional[id]      => Variant[Integer[0], Enum['auto']],
  Optional[options] => Array[Hash],
  Optional[pools]   => Array[String],
]
