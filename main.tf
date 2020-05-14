################################################################################
#
# This configuration file is an example of creating a full-fledged 3-Tier App
# using Terraform.
#
# It creates the following objects:
#   - Tier-1 Gateway (that gets attached to an existing Tier-0 Gateway)
#   - A DHCP Server providing DHCP Addresses to all 3 Segments
#   - 3 Segments (Web, App, DB)
#   - Dynamic Groups based on VM Tags
#   - Static Group based on IP Addresses
#   - Service
#   - NAT Rules
#   - VM tags
#
# The config has been validated against:
#    NSX-T 3.0 using NSX-T Terraform Provider v2.0
#
# The config below requires the following to be pre-created
#   - Edge Cluster
#   - Overlay Transport Zone
#   - Tier-0 Gateway
#   - VM Template
#
# It also uses these 3 Services available by default on NSX-T
#   - HTTPS
#   - MySQL
#   - SSH
#
# The configuration also clones the Web, App and DB from the same
# VM template
#
################################################################################


#
# The first step is to configure the VMware NSX provider to connect to the NSX
# REST API running on the NSX manager.
#
provider "nsxt" {
  host                  = "192.168.200.11"
  username              = "admin"
  password              = "myPassword1!myPassword1!"
  allow_unverified_ssl  = true
  max_retries           = 10
  retry_min_delay       = 500
  retry_max_delay       = 5000
  retry_on_status_codes = [429]
}

#
# Here we show that you define a NSX tag which can be used later to easily to
# search for the created objects in NSX.
#
variable "nsx_tag_scope" {
  default = "project"
}

variable "nsx_tag" {
  default = "terraform-demo"
}


#
# This part of the example shows some data sources we will need to refer to
# later in the .tf file. They include the transport zone, tier 0 router and
# edge cluster.
# Ther Tier-0 (T0) Gateway is considered a "provider" router that is pre-created
# by the NSX Admin. A T0 Gateway is used for north/south connectivity between
# the logical networking space and the physical networking space. Many Tier1
# Gateways will be connected to the T0 Gateway
#
data "nsxt_policy_edge_cluster" "demo" {
  display_name = "Edge-Cluster"
}

data "nsxt_policy_transport_zone" "overlay_tz" {
  display_name = "Overlay-TZ"
}

data "nsxt_policy_tier0_gateway" "t0_gateway" {
  display_name = "TF-T0-Gateway"
}

#
# Create a DHCP Profile that is used later
#
resource "nsxt_policy_dhcp_server" "tier_dhcp" {
  nsx_id           = "tier_dhcp"
  display_name     = "tier_dhcp"
  description      = "DHCP server servicing all 3 Segments"
  server_addresses = ["12.12.99.2/24"]
}

#
# In this part of the example, the settings required to create a Tier1 Gateway
# are defined. In NSX a Tier1 Gateway is often used on a per user, tenant,
# department or application basis. Each application may have it's own Tier1
# Gateway. The Tier1 Gateway provides the default gateway for virtual machines
# connected to the Segments on the Tier1 Gateway
#
resource "nsxt_policy_tier1_gateway" "t1_gateway" {
  nsx_id                    = "TF_T1"
  display_name              = "TF_T1"
  description               = "Tier1 provisioned by Terraform"
  edge_cluster_path         = data.nsxt_policy_edge_cluster.demo.path
  dhcp_config_path          = nsxt_policy_dhcp_server.tier_dhcp.path
  failover_mode             = "PREEMPTIVE"
  default_rule_logging      = "false"
  enable_firewall           = "false"
  enable_standby_relocation = "false"
  force_whitelisting        = "true"
  tier0_path                = data.nsxt_policy_tier0_gateway.t0_gateway.path
  route_advertisement_types = ["TIER1_STATIC_ROUTES", "TIER1_CONNECTED"]
  pool_allocation           = "ROUTING"

  tag {
    scope = var.nsx_tag_scope
    tag   = var.nsx_tag
  }

  route_advertisement_rule {
    name                      = "rule1"
    action                    = "DENY"
    subnets                   = ["20.0.0.0/24", "21.0.0.0/24"]
    prefix_operator           = "GE"
    route_advertisement_types = ["TIER1_CONNECTED"]
  }
}

#
# This shows the settings required to create NSX Segment (Logical Switch) to
# which you can attach Virtual Machines (VMs)
#
resource "nsxt_policy_segment" "web" {
  nsx_id              = "web-tier"
  display_name        = "web-tier"
  description         = "Terraform provisioned Web Segment"
  connectivity_path   = nsxt_policy_tier1_gateway.t1_gateway.path
  transport_zone_path = data.nsxt_policy_transport_zone.overlay_tz.path

  subnet {
    cidr        = "12.12.1.1/24"
    dhcp_ranges = ["12.12.1.100-12.12.1.160"]

    dhcp_v4_config {
      server_address = "12.12.1.2/24"
      lease_time     = 36000

      dhcp_option_121 {
        network  = "6.6.6.0/24"
        next_hop = "1.1.1.21"
      }
    }
  }

  advanced_config {
    connectivity = "ON"
  }

  tag {
    scope = var.nsx_tag_scope
    tag   = var.nsx_tag
  }
  tag {
    scope = "tier"
    tag   = "web"
  }
}

resource "nsxt_policy_segment" "app" {
  nsx_id              = "app-tier"
  display_name        = "app-tier"
  description         = "Terraform provisioned App Segment"
  connectivity_path   = nsxt_policy_tier1_gateway.t1_gateway.path
  transport_zone_path = data.nsxt_policy_transport_zone.overlay_tz.path

  subnet {
    cidr        = "12.12.2.1/24"
    dhcp_ranges = ["12.12.2.100-12.12.2.160"]

    dhcp_v4_config {
      server_address = "12.12.2.2/24"
      lease_time     = 36000

      dhcp_option_121 {
        network  = "6.6.6.0/24"
        next_hop = "1.1.1.21"
      }
    }
  }

  advanced_config {
    connectivity = "ON"
  }

  tag {
    scope = var.nsx_tag_scope
    tag   = var.nsx_tag
  }
  tag {
    scope = "tier"
    tag   = "app"
  }
}

resource "nsxt_policy_segment" "db" {
  nsx_id              = "db-tier"
  display_name        = "db-tier"
  description         = "Terraform provisioned DB Segment"
  connectivity_path   = nsxt_policy_tier1_gateway.t1_gateway.path
  transport_zone_path = data.nsxt_policy_transport_zone.overlay_tz.path

  subnet {
    cidr        = "12.12.3.1/24"
    dhcp_ranges = ["12.12.3.100-12.12.3.160"]

    dhcp_v4_config {
      server_address = "12.12.3.2/24"
      lease_time     = 36000

      dhcp_option_121 {
        network  = "6.6.6.0/24"
        next_hop = "1.1.1.21"
      }
    }
  }

  advanced_config {
    connectivity = "ON"
  }

  tag {
    scope = var.nsx_tag_scope
    tag   = var.nsx_tag
  }
  tag {
    scope = "tier"
    tag   = "db"
  }
}

#
# This part of the example shows creating Groups with dynamic membership
# criteria
#
# All Virtual machines with specific tag and scope
resource "nsxt_policy_group" "all_vms" {
  nsx_id       = "All_VMs"
  display_name = "All_VMs"
  description  = "Group consisting of ALL VMs"
  criteria {
    condition {
      member_type = "VirtualMachine"
      operator    = "CONTAINS"
      key         = "Tag"
      value       = var.nsx_tag

    }
  }
}

# All WEB VMs
resource "nsxt_policy_group" "web_group" {
  nsx_id       = "Web_VMs"
  display_name = "Web_VMs"
  description  = "Group consisting of Web VMs"
  criteria {
    condition {
      member_type = "VirtualMachine"
      operator    = "CONTAINS"
      key         = "Tag"
      value       = "web"
    }
  }
  tag {
    scope = var.nsx_tag_scope
    tag   = var.nsx_tag
  }
}

# All App VMs
resource "nsxt_policy_group" "app_group" {
  display_name = "App_VMs"
  nsx_id       = "App_VMs"
  description  = "Group consisting of App VMs"
  criteria {
    condition {
      member_type = "VirtualMachine"
      operator    = "CONTAINS"
      key         = "Tag"
      value       = "app"
    }
  }
  tag {
    scope = var.nsx_tag_scope
    tag   = var.nsx_tag
  }
}

# All DB VMs
resource "nsxt_policy_group" "db_group" {
  display_name = "DB_VMs"
  nsx_id       = "DB_VMs"
  description  = "Group consisting of DB VMs"
  criteria {
    condition {
      member_type = "VirtualMachine"
      operator    = "CONTAINS"
      key         = "Tag"
      value       = "db"
    }
  }
  tag {
    scope = var.nsx_tag_scope
    tag   = var.nsx_tag
  }
}

# Static Group of IP addresses
resource "nsxt_policy_group" "ip_set" {
  nsx_id       = "external_IPs"
  display_name = "external_IPs"
  description  = "Group containing all external IPs"
  criteria {
    ipaddress_expression {
      ip_addresses = ["211.1.1.1", "212.1.1.1", "192.168.1.1-192.168.1.100"]
    }
  }
  tag {
    scope = var.nsx_tag_scope
    tag   = var.nsx_tag
  }
}

#
# An example for Service for App that listens on port 8443
#
resource "nsxt_policy_service" "app_service" {
  nsx_id       = "app_service_8443"
  display_name = "app_service_8443"
  description  = "Service for App that listens on port 8443"
  l4_port_set_entry {
    description       = "TCP Port 8443"
    protocol          = "TCP"
    destination_ports = ["8443"]
  }
  tag {
    scope = var.nsx_tag_scope
    tag   = var.nsx_tag
  }
}

#
# Here we have examples of create data sources for Services
#
data "nsxt_policy_service" "https" {
  display_name = "HTTPS"
}

data "nsxt_policy_service" "mysql" {
  display_name = "MySQL"
}

data "nsxt_policy_service" "ssh" {
  display_name = "SSH"
}


#
# In this section, we have example to create Firewall sections and rules
# All rules in this section will be applied to VMs that are part of the
# Gropus we created earlier
#
resource "nsxt_policy_security_policy" "firewall_section" {
  display_name = "DFW Section"
  description  = "Firewall section created by Terraform"
  scope        = [nsxt_policy_group.all_vms.path]
  category     = "Application"
  locked       = "false"
  stateful     = "true"

  tag {
    scope = var.nsx_tag_scope
    tag   = var.nsx_tag
  }

  # Allow communication to any VMs only on the ports defined earlier
  rule {
    display_name       = "Allow HTTPS"
    description        = "In going rule"
    action             = "ALLOW"
    logged             = "false"
    ip_version         = "IPV4"
    destination_groups = [nsxt_policy_group.web_group.path]
    services           = [data.nsxt_policy_service.https.path]
  }

  rule {
    display_name       = "Allow SSH"
    description        = "In going rule"
    action             = "ALLOW"
    logged             = "false"
    ip_version         = "IPV4"
    destination_groups = [nsxt_policy_group.web_group.path]
    services           = [data.nsxt_policy_service.ssh.path]
  }

  # Web to App communication
  rule {
    display_name       = "Allow Web to App"
    description        = "Web to App communication"
    action             = "ALLOW"
    logged             = "false"
    ip_version         = "IPV4"
    source_groups      = [nsxt_policy_group.web_group.path]
    destination_groups = [nsxt_policy_group.app_group.path]
    services           = [nsxt_policy_service.app_service.path]
  }

  # App to DB communication
  rule {
    display_name       = "Allow App to DB"
    description        = "App to DB communication"
    action             = "ALLOW"
    logged             = "false"
    ip_version         = "IPV4"
    source_groups      = [nsxt_policy_group.app_group.path]
    destination_groups = [nsxt_policy_group.db_group.path]
    services           = [data.nsxt_policy_service.mysql.path]
  }

  # Allow External IPs to communicate with VMs
  rule {
    display_name       = "Allow Infrastructure"
    description        = "Allow DNS and Management servers"
    action             = "ALLOW"
    logged             = "true"
    ip_version         = "IPV4"
    source_groups      = [nsxt_policy_group.ip_set.path]
    destination_groups = [nsxt_policy_group.all_vms.path]
  }

  # Allow VMs to communicate with outside
  rule {
    display_name  = "Allow out"
    description   = "Outgoing rule"
    action        = "ALLOW"
    logged        = "true"
    ip_version    = "IPV4"
    source_groups = [nsxt_policy_group.all_vms.path]
  }

  # Reject everything else
  rule {
    display_name = "Deny ANY"
    description  = "Default Deny the traffic"
    action       = "REJECT"
    logged       = "true"
    ip_version   = "IPV4"
  }
}

#
# Here we have examples for creating NAT rules. The example here assumes
# the Web IP addresses are reachable from outside and no NAT is required.
#
resource "nsxt_policy_nat_rule" "rule1" {
  nsx_id              = "App-1-to-1-In"
  display_name        = "App 1-to-1 In"
  action              = "SNAT"
  translated_networks = ["102.10.22.1"] # NAT IP
  source_networks     = ["12.12.2.0/24"]
  gateway_path        = nsxt_policy_tier1_gateway.t1_gateway.path
  tag {
    scope = var.nsx_tag_scope
    tag   = var.nsx_tag
  }
}

resource "nsxt_policy_nat_rule" "rule2" {
  nsx_id               = "App-1-to-1-Out"
  display_name         = "App 1-to-1 Out"
  action               = "DNAT"
  translated_networks  = ["102.10.22.2"]
  destination_networks = ["102.10.22.1/32"]
  source_networks      = ["12.12.2.0/24"]
  gateway_path         = nsxt_policy_tier1_gateway.t1_gateway.path
  tag {
    scope = var.nsx_tag_scope
    tag   = var.nsx_tag
  }
}

resource "nsxt_policy_nat_rule" "rule3" {
  nsx_id              = "DB-1-to-1-In"
  display_name        = "DB 1-to-1 In"
  action              = "SNAT"
  translated_networks = ["102.10.23.1"] # NAT IP
  source_networks     = ["12.12.3.0/24"]
  gateway_path        = nsxt_policy_tier1_gateway.t1_gateway.path
  tag {
    scope = var.nsx_tag_scope
    tag   = var.nsx_tag
  }
}

resource "nsxt_policy_nat_rule" "rule4" {
  display_name         = "App 1-to-1 Out"
  action               = "DNAT"
  translated_networks  = ["102.10.23.3"]
  destination_networks = ["102.10.23.1/32"]
  source_networks      = ["12.12.3.0/24"]
  gateway_path         = nsxt_policy_tier1_gateway.t1_gateway.path
  tag {
    scope = var.nsx_tag_scope
    tag   = var.nsx_tag
  }
}


data "nsxt_policy_segment_realization" "web_info" {
  path = nsxt_policy_segment.web.path
  depends_on = [nsxt_policy_segment.web]
}

data "nsxt_policy_segment_realization" "app_info" {
  path = nsxt_policy_segment.app.path
  depends_on = [nsxt_policy_segment.app]
}

data "nsxt_policy_segment_realization" "db_info" {
  path = nsxt_policy_segment.db.path
  depends_on = [nsxt_policy_segment.db]
}

data "nsxt_policy_realization_info" "a_info" {
  path = nsxt_policy_segment.app.path
  depends_on = [nsxt_policy_segment.app]
}

data "nsxt_policy_realization_info" "d_info" {
  path = nsxt_policy_segment.db.path
  depends_on = [nsxt_policy_segment.db]
}

data "nsxt_policy_realization_info" "w_info" {
  path = nsxt_policy_segment.web.path
  depends_on = [nsxt_policy_segment.web]
}


# Reconfigure the VMs to use the Segments created above. Since the VMs are
# already tagged, they are protected by DFW the moment they are connected
# to the Segments.
# Reconfiguration is a vCenter operation. To achieve this, use the vCenter
# provider

provider "vsphere" {
  user                 = "administrator@vsphere.local"
  password             = "myPassword1!"
  vsphere_server       = "192.168.223.97"
  allow_unverified_ssl = true
}

data "vsphere_datacenter" "datacenter" {
  name = "Datacenter"
}

# Data source for the Segments we created earlier
data "vsphere_network" "tf_web" {
  name          = "web-tier"
  datacenter_id = data.vsphere_datacenter.datacenter.id
  depends_on    = [data.nsxt_policy_segment_realization.web_info]
}

data "vsphere_network" "tf_app" {
  name          = "app-tier"
  datacenter_id = data.vsphere_datacenter.datacenter.id
  depends_on    = [data.nsxt_policy_segment_realization.app_info]
}

data "vsphere_network" "tf_db" {
  name          = "db-tier"
  datacenter_id = data.vsphere_datacenter.datacenter.id
  depends_on    = [data.nsxt_policy_segment_realization.db_info]
}

data "vsphere_compute_cluster" "cluster-east" {
  name          = "wcp-cluster-east"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_compute_cluster" "cluster-west" {
  name          = "wcp-cluster-west"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_datastore" "datastore20" {
  name          = "datastore20"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_datastore" "datastore21" {
  name          = "datastore21"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_virtual_machine" "vm-template" {
  name          = "base"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

resource "vsphere_virtual_machine" "web-vm" {
  name             = "web-vm"
  datastore_id     = data.vsphere_datastore.datastore20.id
  resource_pool_id = data.vsphere_compute_cluster.cluster-east.resource_pool_id
  guest_id         = "centos8_64Guest"
  firmware         = "efi"
  network_interface {
    network_id = data.vsphere_network.tf_web.id
  }
  clone {
    template_uuid = data.vsphere_virtual_machine.vm-template.id
  }
  disk {
    label            = "web-vm.vmdk"
    size             = 20
    thin_provisioned = true
  }
}

resource "vsphere_virtual_machine" "app-vm" {
  name             = "app-vm"
  datastore_id     = data.vsphere_datastore.datastore21.id
  resource_pool_id = data.vsphere_compute_cluster.cluster-west.resource_pool_id
  guest_id         = "centos8_64Guest"
  firmware         = "efi"
  network_interface {
    network_id = data.vsphere_network.tf_app.id
  }
  clone {
    template_uuid = data.vsphere_virtual_machine.vm-template.id
  }
  disk {
    label            = "app-vm.vmdk"
    size             = 20
    thin_provisioned = true
  }
}

resource "vsphere_virtual_machine" "db-vm" {
  name             = "db-vm"
  datastore_id     = data.vsphere_datastore.datastore21.id
  resource_pool_id = data.vsphere_compute_cluster.cluster-west.resource_pool_id
  guest_id         = "centos8_64Guest"
  firmware         = "efi"
  network_interface {
    network_id = data.vsphere_network.tf_db.id
  }
  clone {
    template_uuid = data.vsphere_virtual_machine.vm-template.id
  }
  disk {
    label            = "db-vm.vmdk"
    size             = 20
    thin_provisioned = true
  }
}

# The 3 VMs available in the NSX Inventory
data "nsxt_policy_vm" "web_vm" {
  display_name = "web-vm"
  depends_on    = [vsphere_virtual_machine.web-vm]
}

data "nsxt_policy_vm" "app_vm" {
  display_name = "app-vm"
  depends_on    = [vsphere_virtual_machine.app-vm]
}

data "nsxt_policy_vm" "db_vm" {
  display_name = "db-vm"
  depends_on    = [vsphere_virtual_machine.db-vm]
}

# Assign the right tags to the VMs so that they get included in the
# dynamic groups created above
resource "nsxt_policy_vm_tags" "web_vm_tag" {
  instance_id = data.nsxt_policy_vm.web_vm.instance_id
  tag {
    scope = "tier"
    tag   = "web"
  }
  tag {
    scope = var.nsx_tag_scope
    tag   = var.nsx_tag
  }
}

resource "nsxt_policy_vm_tags" "app_vm_tag" {
  instance_id = data.nsxt_policy_vm.app_vm.instance_id
  tag {
    scope = "tier"
    tag   = "app"
  }
  tag {
    scope = var.nsx_tag_scope
    tag   = var.nsx_tag
  }
}

resource "nsxt_policy_vm_tags" "db_vm_tag" {
  instance_id = data.nsxt_policy_vm.db_vm.instance_id
  tag {
    scope = "tier"
    tag   = "db"
  }
  tag {
    scope = var.nsx_tag_scope
    tag   = var.nsx_tag
  }
}
