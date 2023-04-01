terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

data "template_file" "user_data" {
  template = file("${path.module}/cloud-init.cfg")
  count    = length(var.hostname)
  vars = {
    "hostname" = element(var.hostname, count.index)
  }
}

resource "libvirt_cloudinit_disk" "ubuntu-cloudinit" {
  count     = length(var.hostname)
  name      = "${var.hostname[count.index]}-cloudinit.iso"
  pool      = "default"
  user_data = data.template_file.user_data[count.index].rendered
}

resource "libvirt_volume" "ubuntu2204-cloudimg" {
  name   = "jammy-server-cloudimg-amd64.qcow2"
  pool   = "default"
  source = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  format = "qcow2"
}

resource "libvirt_volume" "ubuntu2204-storage" {
  count          = length(var.hostname)
  name           = "${var.hostname[count.index]}.qcow2"
  base_volume_id = libvirt_volume.ubuntu2204-cloudimg.id
  pool           = "default"
  size           = var.disk-size[count.index]
}

resource "libvirt_domain" "ubuntu2204" {
  count = length(var.hostname)

  cpu {
    mode = "host-passthrough"
  }

  name       = var.hostname[count.index]
  vcpu       = var.vcpu[count.index]
  memory     = var.memory[count.index]
  arch       = "x86_64"
  machine    = "q35"
  qemu_agent = true
  autostart  = true

  network_interface {
    # network_name   = "default"
    macvtap        = var.macvtap_interface
    wait_for_lease = true
  }

  disk {
    volume_id = element(libvirt_volume.ubuntu2204-storage.*.id, count.index)
  }

  # Mount cloud-init ISO as SATA disk
  disk {
    volume_id = split(";", element(libvirt_cloudinit_disk.ubuntu-cloudinit.*.id, count.index))[0]
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }

  video {
    type = "virtio"
  }
}

output "vm-hostname-ip-address" {
  value = (formatlist(
    "%s: %s",
    libvirt_domain.ubuntu2204[*].name,
    libvirt_domain.ubuntu2204[*].network_interface.0.addresses[0]
  ))
}
