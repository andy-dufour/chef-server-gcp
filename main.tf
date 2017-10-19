terraform {
  required_version = "= 0.9.11"
}

provider "google" {
  credentials = "${file("${var.gcp_credentials_file}")}"
  project     = "${var.gcp_project}"
  region      = "${var.gcp_region}"
}

resource "google_sql_database_instance" "master" {
  name = "master-instancev3"
  region = "${var.gcp_region}"
  database_version = "POSTGRES_9_6"

  settings {
    tier = "db-custom-2-4096"
    disk_size = "10"
    disk_type = "PD_SSD"
  }
}

resource "google_sql_database" "users" {
  name      = "users-db"
  instance  = "${google_sql_database_instance.master.name}"
}

resource "google_dns_record_set" "chef-server" {
  name = "chef-server.${google_dns_managed_zone.prod.dns_name}"
  type = "A"
  ttl  = 300

  managed_zone = "${google_dns_managed_zone.prod.name}"

  rrdatas = ["${google_compute_instance.chef-server.network_interface.0.access_config.0.assigned_nat_ip}"]
}

resource "google_compute_instance" "chef-server" {
  name         = "chef-server"
  machine_type = "n1-standard-1"
  zone         = "us-west1-a"

  disk {
      image = "centos-7-v20171003"
  }

  network_interface {
      network = "default"
      access_config {
          // Ephemeral IP
      }
  }
  count = 1
  lifecycle = {
    create_before_destroy = true
  }
  connection {
    user        = "${var.gcp_image_user}"
    private_key = "${file("${var.gcp_private_key}")}"
  }
  provisioner "file" {
    source = "script.sh"
    destination = "/var/tmp/script.sh"
  }
  provisioner "file" {
    source = "variables.sh"
    destination = "/var/tmp/variables.sh"
  }
  provisioner "remote-exec" {
    inline = [
      "chmod +x /var/tmp/script.sh",
      "sudo /var/tmp/script.sh 1 chef-server.habitat-kubernetes-playland.com"
    ]
  }
}

resource "google_dns_managed_zone" "prod" {
  name     = "prod-zone"
  dns_name = "habitat-kubernetes-playland.com."
}
