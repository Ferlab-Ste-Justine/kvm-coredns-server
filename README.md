# About

This module provision coredns instances on kvm.

The server is configured to to work with zonefiles which are fetched from an etcd cluster. Each domain is a key in etcd (with an optional prefix) and the zonefile (which should be compatible with the auto plugin) is the value.

The server will automatically detect any changes in the domains in the etcd backend and update the zonefiles accordingly.

Note that except for updates to zonefiles, the coredns server is decoupled from the etcd cluster and will happily keep answering dns requests with whatever zonefiles it has on hand (they just won't update until the etcd cluster is back up).

# Note About Alternatives

Coredns also has a SkyDNS compatible plugin: https://coredns.io/plugins/etcd/

Some of the perceived pros of the above plugin:
- Assuming that the cache plugin isn't used (ie, all dns requests hit etcd), the consistency level of the answer from different dns servers shortly after the change can't be matched
- From what I read in the readme, decentralisation of ip registration seems better supported out of the box (you could support it with zonefiles too, but extra logic would have to be added using something like templates)

Some of the perceived pros of our implementation:
- Full support for zonefiles to the extend the coredns auto plugin supports them (ie, fewer quirks)
- Decent consistency/performance tradeoff: The server does a watch for changes on the etcd cluster (but will not put any more stress than that etcd) and will automatically update its local zonefiles with changes. The refresh interval set in the auto plugin will determine how quickly those changes will be picked up (3 seconds by default)
- Greater decoupling from etcd: The server is only dependent on etcd for updating zonefiles. If etcd is down, it can still answer queries with the zonefiles it has. 

# Related Projects

See the following terraform module that uploads very basic zonefiles in etcd: https://github.com/Ferlab-Ste-Justine/etcd-zonefile

Also, this module expects to authentify against etcd using tls certificate authentication. The following terraform module will, taking a certificate authority as input, generate a valid key and certificate for a given etcd user (disregard the openstack in the name): https://github.com/Ferlab-Ste-Justine/openstack-etcd-client-certificate

# Supported Networking

The module supports libvirt networks and macvtap (bridge mode).

# Usage

## Input

- **name**: Name of the vm
- **vcpus**: Number of vcpus to assign to the vm. Defaults to 2.
- **memory**: Amount of memory in MiB to assign to the vm. Defaults to 8192 (ie, 8 GiB).
- **volume_id**: Id of the image volume to attach to the vm. A recent version of ubuntu is recommended as this is what this module has been validated against.
- **network_id**: Id (ie, uuid) of the libvirt network to connect the vm to if you wish to connect the vm to a libvirt network.
- **ip**: Ip of the vm if you opt to connect it to a libvirt network. Note that this isn't an optional parameter. Dhcp cannot be used.
- **mac**: Mac address of the vm if you opt to connect it to a libvirt network. If none is passed, a random one will be generated.
- **macvtap_interfaces**: List of macvtap interfaces to connect the vm to if you opt for macvtap interfaces instead of a libvirt network. Each entry in the list is a map with the following keys:
  - **interface**: Host network interface that you plan to connect your macvtap interface with.
  - **prefix_length**: Length of the network prefix for the network the interface will be connected to. For a **192.168.1.0/24** for example, this would be 24.
  - **ip**: Ip associated with the macvtap interface. 
  - **mac**: Mac address associated with the macvtap interface
  - **gateway**: Ip of the network's gateway for the network the interface will be connected to.
  - **dns_servers**: Dns servers for the network the interface will be connected to. If there aren't dns servers setup for the network your vm will connect to, the ip of external dns servers accessible accessible from the network will work as well.
- **cloud_init_volume_pool**: Name of the volume pool that will contain the cloud-init volume of the vm.
- **cloud_init_volume_name**: Name of the cloud-init volume that will be generated by the module for your vm. If left empty, it will default to ```<name>-cloud-init.iso```.
- **ssh_admin_user**: Username of the default sudo user in the image. Defaults to **ubuntu**.
- **admin_user_password**: Optional password for the default sudo user of the image. Note that this will not enable ssh password connections, but it will allow you to log into the vm from the host using the **virsh console** command.
- **ssh_admin_public_key**: Public part of the ssh key the admin will be able to login as
- **etcd_ca_certificate**: Tls ca certificate that will be used to validate the authenticity of the etcd cluster
- **etcd_client_certificate**: Tls client certificate for the etcd user the server will authentify as
- **etcd_client_key**: Tls client key for the etcd user the server will authentify as
- **etcd_key_prefix**: Prefix for all the domain keys. The server will look for keys with this prefix and will remove this prefix from the key's name to get the domain.
- **etcd_endpoints**: A list of endpoints for the etcd servers, each entry taking the ```<ip>:<port>``` format
- **coredns_version**: Version of coredns to download and run. Defaults to **1.8.6**.
- **zonefiles_reload_interval**: Time interval at which the **auto** plugin should poll the zonefiles for updates. Defaults to **3s** (ie, 3 seconds).
- **load_balance_records**: In the event that an A or AAAA record yields several ips, whether to randomize the returned order or not (with clients that only take the first ip, you can achieve some dns-level load balancing this way). Defaults to **true**.

## Example

Below is an orchestration I ran locally to troubleshoot the module.

```
module "coredns" {
  source = "git::https://github.com/Ferlab-Ste-Justine/kvm-coredns-server.git"
  name = "coredns-1"
  vcpus = 2
  memory = 8192
  volume_id = libvirt_volume.coredns.id

  macvtap_interfaces = [
      {
          interface = local.networks.lan1.interface
          prefix_length = local.networks.lan1.prefix
          gateway = local.networks.lan1.gateway
          dns_servers = local.networks.lan1.dns
          ip = data.netaddr_address_ipv4.lan1_coredns_1.address
          mac = data.netaddr_address_mac.lan1_coredns_1.address
      },
      {
          interface = local.networks.lan2.interface
          prefix_length = local.networks.lan2.prefix
          gateway = local.networks.lan2.gateway
          dns_servers = local.networks.lan2.dns
          ip = data.netaddr_address_ipv4.lan2_coredns_1.address
          mac = data.netaddr_address_mac.lan2_coredns_1.address
      }
  ]
  
  cloud_init_volume_pool = "coredns"
  ssh_admin_public_key = local.coredns_ssh_public_key
  admin_user_password = local.console_password
  etcd_ca_certificate = local.etcd_ca_cert
  etcd_client_certificate = local.etcd_coredns_cert
  etcd_client_key = local.etcd_coredns_key
  etcd_key_prefix = "/coredns/"
  etcd_endpoints = [for server in local.etcd.servers: "${server.ip}:2379"]
}
```

Some gotchas that apply to this project can be found here: https://github.com/Ferlab-Ste-Justine/kvm-etcd-server#gotchas