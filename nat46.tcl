#
# Simple NAT46 iRule rev 0.2 (2012/12/17)
#
#   Written By:  Shunsuke Takahashi (s.takahashi at f5.com)
#
#   Description: Lookup table to convert DNS46 internal only IPv4 destination
#                address to original IPv6 desitination and SNAT client addr to
#                IPv6 SNAT pool address.
#
#                Example:Translate IPv4 source and IPv4 destination into IPv6
#
#                (s)10.1.1.2->(d)1.1.1.1 T (S)2001:fb46:102->(D)2001::101:101
#                                                   
#
#   Information: Currently, no application level gateway is implemented to the
#                NAT46 iRule. Only HTTP like traffic can be passed through and
#                SIP, PPTP or BITTORRENT like protocols will be failed.
#
#
#
#   Requirement: The rule requires following environment to be fullfiled
#                1) VS need to listen on dns46 pool range. (Similar to NAT64)
#
#                2) Address translation must be enabled on the VS for NAT46
#
#                     ltm virtual vs-nat46 {
#                       destination 100.64.0.0:any
#                       ip-protocol any
#                       mask 255.255.0.0
#                       profiles {
#                         fastL4 { }
#                       }
#                       rules {
#                         rule_nat46
#                       }
#                       source 0.0.0.0/0
#                       source-address-translation {
#                         pool snat-pool-nat46
#                         type snat
#                       }
#                       translate-port disabled
#                       vlans-disabled
#                     }
#
#
timing off

when CLIENT_ACCEPTED priority 100 {

  # Rule Name and Version shown in the log
  set static::RULE_NAME "Simple NAT46 v0.2"
  
  # 0: No Debug Logging 1: Debug Logging
  set DBG 1

  # IP address for Sorry Page (Used when run out pool)
  set static::Sorry_IP 10.1.101.200

  # IPv4 SNAT Pool (For Sorry Page Connection)
  set snat_sorry automap

  # Using High-Speed Logging in thie rule
  set hsl [HSL::open -proto UDP -pool pool-hsl-windows]
  set log_head   "\[nat46\]([IP::client_addr])"
  set log_head_d "$log_head\(debug\)"

  if {$DBG}{HSL::send $hsl "<191> $log_head_d  ***** iRule: $static::RULE_NAME executed *****"}

}


when CLIENT_ACCEPTED priority 200 {

  # Lookup DNS46 to find original IPv6 destination IP
  set src_v4 [IP::client_addr]
  set dst_v4 [IP::local_addr]
  set dst_v6 [table lookup -subtable "t_dns46" $dst_v4]

  if {$DBG}{HSL::send $hsl "<191> $log_head_d Looked up NAT64 table for $dst_v4 matched $dst_v6"}
  
  if {$dst_v6 != ""} {
        
    node $dst_v6
    
    if {$DBG}{HSL::send $hsl "<191> $log_head_d Changed Destination to \[$dst_v6\]"}

  } else {
    
    # Send to sorry server_addr
    node $static::Sorry_IP
    snat $snat_sorry
    
    HSL::send $hsl "<190> $log_head Send Traffic to Sorry IP\[$static::Sorry_IP\ (snat $snat_v4) ]"
  }
  
  if {$DBG}{HSL::send $hsl "<191> $log_head_d  ***** iRule: $static::RULE_NAME completed *****"}
}


when SERVER_CONNECTED {

  if {$DBG}{HSL::send $hsl "<191> $log_head_d NAT46 Added Src \{$src_v4 => [IP::local_addr]\} \, Dst\{$dst_v4 => [IP::server_addr]\}"}

}
