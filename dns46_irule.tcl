#
# Simple DNS46 iRule rev 0.5 (2012/12/17)
#
#   Written By:  Shun Takahashi
#
#   Description: AAAA records to be (retrieved and) translated to 
#                an A record by this DNS46 iRule if and only if 
#                there is no reachable A record exist.
# 
#                This rule is written and tested in TMOS v11.3.0 
#
#                Rule is called when client resolving DNS records
#
#                1) If LDNS only returns A record
#                    => The rule returns original A responses
#
#                2) If A record and AAAA records resolved 
#                    => The rule returns both responses unchanged
#
#                3) If only AAAA record resolved
#                    => Insert A record pointing to internal NAT46 address and 
#                       returns both NAT46 A and original AAAA responses. 
#
#   Information: DNS46 table in this rule contains NAT46 IPv4 addr as a key and
#                original IPv6 addr as a value:
#
#                table set -subtable "t_dns46" <VALUE: 1.1.1.1> <KEY:2001::1>\ 
#                                              static::Timeout static::Lifetime
#
#                *) Usiing a IPv4 as a key as NAT46 lookup v6_addr more often
#
#                Rule uses following method to assign DNS46 IPv4 address to the 
#                response.
#
#                1) Run a loop from START_ADDR to scan table incrementally and
#                   returns first unused value
#
#                2) When reach LAST_ADDR with no address found, returns a SORRY
#                   address and log a message.
#
#   Requirement: The rule requires following environment to be fullfiled
#                1) Create a DNS virtual server running as DNS46 resolver
#
#                     example:
#
#                     ltm virtual vs-dns46 {
#                         destination 10.1.101.222:domain
#                         ip-protocol udp
#                         mask 255.255.255.255
#                         profiles {
#                             profile_dns46 { }
#                             udp { }
#                         }
#                         rules {
#                             rule_dns46
#                         }
#                         source 0.0.0.0/0
#                         source-address-translation {
#                             type automap
#                         }
#                         vlans-disabled
#                     }
#                     
#
#                2) DNS express or internal BIND can be used for DNS forwarder
#
timing off

when CLIENT_ACCEPTED priority 100 {

  # Rule Name and Version shown in the log
  set static::RULE_NAME "Simple DNS46 v0.5"
  
  # 0: No Debug Logging 1: Debug Logging
  set DBG 1

  # Name Server / DNS virtual server
  set static::NS 127.0.0.1

  # DNS46 translation address pool range. Maximum supported range is /16
  #
  #   Example: 
  #      set static::Start_Addr xx.xx.0.1
  #      set static::Last_Addr  xx.xx.255.254
  #      *)Range mast START < LAST
  #
  set static::Start_Addr 100.64.0.135
  set static::Last_Addr  100.64.235.200

  # Timeout value for NAT46 entris (second)
  #     Note: to keep this value smaller make this iRule performing well.
  set static::Timeout 300
  set static::Lifetime 3600

  # IP address for Sorry Page (Used when run out pool)
  set static::Sorry_IP 10.1.101.200
  
  # Using High-Speed Logging in thie rule
  set hsl [HSL::open -proto UDP -pool pool-hsl-windows]
  set log_head   "\[dns46\]([IP::client_addr])"
  set log_head_d "$log_head\(debug\)"

  if {$DBG}{HSL::send $hsl "<191> $log_head_d  ***** iRule: $static::RULE_NAME executed *****"}

  # Rule ignores IPv6 clients as it is not necesarry 
  # to patch any AAAA record 
  if {[IP::version] == 6} { 
    if {$DBG}{HSL::send $hsl "<191> $log_head_d  ***** iRule: $static::RULE_NAME skipped - IPv6 connection *****"} 
    return
  }
}

when DNS_REQUEST priority 100 {
  
  set query_host [DNS::question name]
  set query_type [DNS::question type]
  
  if {$DBG}{HSL::send $hsl "<191> $log_head_d User Query: $query_type - $query_host"} 

}


when DNS_RESPONSE {

  set rr [DNS::answer]
  
  if {$DBG}{HSL::send $hsl "<191> $log_head_d Query Response $rr"}

  # Lookup AAAA for the host if *** No A Record Found *** 
  if { [DNS::question type] == "A" && ($rr == "" || [DNS::type $rr] == "CNAME") } {
    
    if {$DBG}{HSL::send $hsl "<191> $log_head_d RESOLVE::lookup - \"AAAA - $query_host\"" } 
    
    set resolved_v6ips   [RESOLV::lookup @$static::NS -aaaa $query_host]
    set s_resolved_v6ips [llength $resolved_v6ips]
    set new_v4ips    ""

    if {$DBG}{HSL::send $hsl "<191> $log_head_d RESOLVE::lookup got response(s) - ($s_resolved_v6ips) $resolved_v6ips"}
    
    # Theoretically it is unnecessary but just for sure
    if {$resolved_v6ips equals ""}{return}    
        
    # Uncomment these to create DNS46 table entries manually for a debug purpose
    #table set -subtable "t_dns46" "1.1.1.1" "2404:6800:4003:803::1007" $static::Timeout $static::Lifetime
    #table set -subtable "t_dns46" "1.1.1.2" "2404:6800:4003:802::1012" $static::Timeout $static::Lifetime

    # Look up DNS46 table with resolved IPv6 addresses in the list  
    # and store IPv4 NAT46 addresses into a new list if entry is 
    # already created
    set k_v4ips [table keys -subtable "t_dns46" -notouch]

    if {$k_v4ips != ""} {
      foreach r_v6ip $resolved_v6ips {
        foreach k_v4ip $k_v4ips {
          if { $r_v6ip equals [table lookup -notouch -subtable "t_dns46" $k_v4ip]}{
            
            if {$DBG}{HSL::send $hsl "<191> $log_head_d Entry in DNS46 for $k_v4ip : $r_v6ip will be timed out in [table timeout -subtable "t_dns46" -remaining $k_v4ip] second(s)"}
            
            # Update the timestamp for the found entry
            table lookup -subtable "t_dns46" $k_v4ip
            
            lappend new_v4ips $k_v4ip
          } 
        }
      }
    } else {
      if {$DBG}{HSL::send $hsl "<191> $log_head_d NAT46 table is empty now"}
    }
    
    if {$DBG}{HSL::send $hsl "<191> $log_head_d Matched following IPv4 addr from the tbl: $new_v4ips"}


    # Fetch available IPv4 address correspondent to AAAA record(s)
    # and add it to response list and NAT46 table if it is new. 
    if {$new_v4ips == ""}{
      if {$DBG==1}{HSL::send $hsl "<191> $log_head_d No existing entry found for $query_host. Assign new"}
      scan $static::Start_Addr {%d.%d.%d.%d} s(a) s(b) s(c) s(d) 
      scan $static::Last_Addr {%d.%d.%d.%d} l(a) l(b) l(c) l(d) 

      foreach r_v6ip $resolved_v6ips {
        set pc 0
        for {set c $s(c)} {$c <= $l(c)} {incr c} {      
          # **TODO** Convert IP_addr into binary/hex format to run loop is much simpler
          if {$pc==0}{
            set min $s(d)
            expr [expr {$s(d) > $l(d)}] ? [set max $l(d)] : [set max 255] 
          } elseif {$pc == 1 && $d > $l(d) && $c < $l(c)} {
            set min 0
            set max 255
          } elseif {$pc == 1 && $c == $l(c)} {
            set min 0
            set max $l(d)
          }

          for {set d $min} {$d < $max} {incr d} {
            set cur_addr "$s(a).$s(b).$c.$d"
            if {[table lookup -notouch -subtable "t_dns46" $cur_addr] equals ""}{
              table set -subtable "t_dns46" $cur_addr $r_v6ip $static::Timeout $static::Lifetime
              lappend new_v4ips $cur_addr
              HSL::send $hsl "<190> $log_head New DNS46 entry: $cur_addr => $r_v6ip"
              set pc 2
              break
            }
            set pc 1
          }
          if {$pc==2}{break}
        }
      }
    }

    # When ran out allocated IPv4 address pool, rule returns default 
    # IPv4 addresss which will guide user to the sorry page and log it.
    if {($new_v4ips == "")} {
      lappend new_v4ips static::Sorry_IP
      HSL::send $hsl "<190> $log_head $static::RULE_NAME added Sorry_IP \
              into A response for [DNS::question name]."      
    }
    
    # Insert IPv4 record into DNS rrs and client will receive
    # DNS46 A response for AAAA response only records
    foreach new_v4ip $new_v4ips {
      DNS::answer insert "[DNS::question name]. 111 [DNS::question class] A $new_v4ip"
      HSL::send $hsl "<190> $log_head $static::RULE_NAME added $new_v4ip \
              into A response for [DNS::question name]."      
    }
  } else {
    if {$DBG}{HSL::send $hsl "<191> $log_head_d  ***** iRule: $static::RULE_NAME skipped - found A record or is AAAA query *****"}
    return
  }
  if {$DBG}{HSL::send $hsl "<191> $log_head_d  ***** iRule: $static::RULE_NAME successfully completed *****"}
}  
