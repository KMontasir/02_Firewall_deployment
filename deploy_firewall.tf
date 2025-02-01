provider "null" {}

resource "null_resource" "create_template" {
  provisioner "local-exec" {
    command = "bash ./provisioner/create_template.sh"
  }

  triggers = {
    always_run = "${timestamp()}"
  }
}

resource "null_resource" "create_firewall" {
  depends_on = [null_resource.create_template]

  provisioner "local-exec" {
    command = "bash ./provisioner/create_firewall.sh"
  }

  triggers = {
    always_run = "${timestamp()}"
  }
}

output "firewalls_created" {
  value = "Les VMs OPNsense ont été créées et configurées avec Cloud-init."
}
