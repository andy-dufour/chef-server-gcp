terraform {
  required_version = "= 0.10.8"
}

provider "google" {
  credentials = "${file("${var.gcp_credentials_file}")}"
  project     = "${var.gcp_project}"
  region      = "${var.gcp_region}"
}

resource "google_sql_database_instance" "chef" {
  name = "${var.db_name}"
  region = "${var.gcp_region}"
  database_version = "POSTGRES_9_6"

  settings {
    tier = "db-custom-2-4096"
    disk_size = "10"
    disk_type = "PD_SSD"
    ip_configuration {
      authorized_networks {
        value           = "0.0.0.0/0"
        name            = "all"
      }
    }
  }
}

resource "google_sql_user" "users" {
  name     = "chefpostgres"
  instance = "${google_sql_database_instance.chef.name}"
  host     = ""
  password = "opscode"
}


resource "google_compute_instance" "elasticsearch" {
  name = "elastic-server"
  machine_type = "n1-standard-1"
  zone = "us-central1-a"
  boot_disk {
    initialize_params {
      image = "centos-cloud/centos-7-v20171003"
    }
  }

  network_interface {
    network = "default"
    access_config {
        // Ephemeral IP
    }
  }

}

resource "null_resource" "elastic_install" {
# This is triggered by any of the ES nodes above being changed.
  triggers {
    cluster_instance_ids = "${google_compute_instance.elasticsearch.id}"
  }

  connection {
    host = "${google_compute_instance.elasticsearch.network_interface.0.access_config.0.assigned_nat_ip}"
    user        = "${var.gcp_image_user}"
    private_key = "${file("${var.gcp_private_key}")}"
  }

  provisioner "remote-exec" {
    inline = [
      "curl -LO https://omnitruck.chef.io/install.sh && sudo bash ./install.sh -P chefdk && rm install.sh",
      "mkdir -p /tmp/elastic-bootstrap/cookbooks"
    ]
  }

  provisioner "file" {
      source      = "vendor/"
      destination = "/tmp/elastic-bootstrap/cookbooks/"
    }

  provisioner "remote-exec" {
    inline = [
      "cd /tmp/elastic-bootstrap/",
      "sudo chef-client -z -r 'recipe[chef_infrastructure::elastic]'"
    ]
  }
}

resource "google_compute_instance" "chef-server" {
  name         = "chef-server"
  machine_type = "n1-standard-1"
  zone         = "us-central1-a"

  tags = ["http-server", "https-server"]

  boot_disk {
    initialize_params {
      image = "centos-cloud/centos-7-v20171003"
    }
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
}

resource "null_resource" "chef_server_install" {
# This is triggered by any of the ES nodes above being changed.
  triggers {
    cluster_instance_ids = "${google_compute_instance.chef-server.id}"
  }

  connection {
    host = "${google_compute_instance.chef-server.network_interface.0.access_config.0.assigned_nat_ip}"
    user        = "${var.gcp_image_user}"
    private_key = "${file("${var.gcp_private_key}")}"
  }

  provisioner "remote-exec" {
    inline = [
      "curl -LO https://omnitruck.chef.io/install.sh && sudo bash ./install.sh -P chefdk -v 1.6 && rm install.sh",
      "mkdir -p /tmp/chef-server-bootstrap/cookbooks"
    ]
  }

  provisioner "file" {
      source      = "vendor/"
      destination = "/tmp/chef-server-bootstrap/cookbooks/"
    }

  provisioner "file" {
    content = "{\"chef_server\": {\"postgresql\": {\"vip\": \"${google_sql_database_instance.chef.ip_address.0.ip_address}\", \"db_su\": \"chefpostgres\", \"db_su_pw\": \"opscode\"}, \"elasticsearch\": {\"vip\": \"${google_compute_instance.elasticsearch.network_interface.0.address}\"}}}"
    destination = "/tmp/chef-server-bootstrap/cluster-data.json"
  }

  provisioner "remote-exec" {
    inline = [
      "cd /tmp/chef-server-bootstrap/",
      "sudo chef-client -z -j cluster-data.json -r 'recipe[chef_infrastructure::server]'"
    ]
  }
}
