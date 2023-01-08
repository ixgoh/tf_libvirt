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
}

resource "libvirt_cloudinit_disk" "ubuntu-cloudinit" {
  name      = "ubuntu-cloudinit.iso"
  pool      = "default"
  user_data = data.template_file.user_data.rendered
}

resource "libvirt_volume" "ubuntu2204-cloudimg" {
  name   = "ubuntu2204-cloudimg.qcow2"
  pool   = "default"
  source = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  format = "qcow2"
}

resource "libvirt_volume" "ubuntu2204-storage" {
  name           = "ubuntu2204.qcow2"
  base_volume_id = libvirt_volume.ubuntu2204-cloudimg.id
  pool           = "default"
  size           = 53687091200
}

resource "libvirt_domain" "ubuntu2204" {
  name = "ubuntu-22.04"
  arch = "x86_64"

  cpu {
    mode = "host-passthrough"
  }

  memory     = "16384"
  vcpu       = 16
  qemu_agent = true
  machine    = "q35"

  network_interface {
    network_name   = "default"
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.ubuntu2204-storage.id
  }

  # Mount cloud-init ISO as SATA disk
  disk {
    volume_id = split(";", libvirt_cloudinit_disk.ubuntu-cloudinit.id)[0]
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

output "IPs" {
  value = libvirt_domain.ubuntu2204.network_interface.0.addresses[0]
}
