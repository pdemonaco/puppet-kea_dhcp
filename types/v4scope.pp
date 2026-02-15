# @summary Utility type for declaring multiple scopes
type Kea_Dhcp::V4Scope = Struct[
  name              => String,
  subnet            => Stdlib::IP::Address::V4::CIDR,
  Optional[id]      => Variant[Integer[0], Enum['auto']],
  Optional[options] => Array[Hash],
  Optional[pools]   => Array[String],
]
