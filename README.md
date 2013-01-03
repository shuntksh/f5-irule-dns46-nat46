f5_nat46_irule
==============

This iRule is to allow internal IPv4 hosts to communicate with *ANY* IPv6 only hosts in the internet by dynamically translating AAAA responses into internal only A responses and converting back to original IPv6 destination address when actual IPv4 traffic is passing through LTM. 
