# f5 iRule for NAT46/DNS46


This iRule is to allow internal IPv4 hosts to communicate with *ANY* IPv6 only hosts by dynamically translating AAAA responses into internal only A responses and converting back to original IPv6 destination address when actual IPv4 traffic is coming through. 

## Description

### DNS46 iRule
AAAA records to be (retrieved and) translated to an A record by this DNS46 iRule if and only if there is no reachable A record exist. Generated NAT46 A records will be stored into session table with IPv4 addr as a key and original IPv6 address as a value.

Rule is called when client resolving DNS records

1. If LDNS only returns ``A record``

    -> The rule returns original A responses

2. If ``A record and AAAA records`` are resolved 

    -> The rule returns both responses unchanged

3. If only ``AAAA record`` is resolved

    -> Insert *A record pointing to internal NAT46 address* and returns both NAT46 A and original AAAA responses.

4. If 3) then stores result into a following session table

    ```able set -subtable "t_dns46" <VALUE: 1.1.1.1> <KEY:2001::1> static::Timeout static::Lifetime```

### NAT46 iRule
Lookup table to convert DNS46 internal only IPv4 destination address to original IPv6 desitination and SNAT client addr to IPv6 SNAT pool address.

**Example** ```(s)10.1.1.2->(d)1.1.1.1 T (S)2001:fb46:102->(D)2001::101:101```

**Note**
Currently, no application level gateway has been implemented or tested. Only HTTP-like traffic can be passed and likes of SIP, PPTP and BITTORRENT traffic may be failed.

## Preparation

### DNS46 iRule
1. Specify a DNS46 private address range in the DNS46 iRule

    ```
    # DNS46 translation address pool range. Maximum supported range is /16
    # and range mast be START < LAST
    set static::Start_Addr xx.xx.0.1
    set static::Last_Addr  xx.xx.255.254
    ```

2. Create a standard virtual server with DNS profile as a DNS46 resolver
3. DNS express or internal BIND can be used for DNS forwarder else create a DNS server pool and assigned it to dns46 vs

    ```
ltm virtual vs-dns46 {
  destination 10.1.101.222:domain
  ip-protocol udp
  mask 255.255.255.255
  profiles {
    profile_dns46 { }
    udp { }
  }
  rules {
    rule_dns46
  }
  source 0.0.0.0/0
  source-address-translation {
    type automap
  }
  vlans-disabled
}                  
    ```

### NAT46 iRule

1. Create a virtual server listening on same rage as DNS46 address pool
2. Address translation must be enabled on NAT46 virtual server

    ```
ltm virtual vs-nat46 {
  destination 100.64.0.0:any
  ip-protocol any
  mask 255.255.0.0
  profiles {
    fastL4 { }
  }
  rules {
    rule_nat46
  }
  source 0.0.0.0/0
  source-address-translation {
    pool snat-pool-nat46
    type snat
  }
  translate-port disabled
  vlans-disabled
}
    ```

## Sample Output

<img src="https://raw.github.com/festango/f5-irule-nat46/master/sample/screen_shot.png" alt="Sample Output" width="800">







