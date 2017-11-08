terraform {
  required_version = "= 0.10.8"
}

provider "google" {
  credentials = "${file("${var.gcp_credentials_file}")}"
  project     = "${var.gcp_project}"
  region      = "${var.gcp_region}"
}

resource "null_resource" "upload_cookbooks" {
  provisioner "local-exec" {
    command = "cd cookbooks/chef_infrastructure; berks update; berks upload --force"
  }
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
  connection {
    user        = "${var.gcp_image_user}"
    private_key = "${file("${var.gcp_private_key}")}"
  }
  provisioner "chef" {
    environment     = "_default"
    run_list        = ["chef_infrastructure::elastic"]
    node_name       = "elastic"
    server_url      = "https://api.chef.io/organizations/gcpmaster"
    recreate_client = true
    user_name       = "adufour"
    user_key        = "${file(".chef/adufour.pem")}"
    version         = "12"
  }
}

/*resource "null_resource" "elastic_install" {
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
}*/

/*resource "google_compute_http_health_check" "chef_server_health_check" {
  name = "chef-server-www-status-check"
  request_path = "/_status"
  check_interval_sec = 5
  healthy_threshold = 1
  unhealthy_threshold = 3
  timeout_sec = 1
}

resource "google_compute_https_health_check" "chef_server_https_health_check" {
  name = "chef-server-https-status-check"
  request_path = "/_status"
  check_interval_sec = 5
  healthy_threshold = 1
  unhealthy_threshold = 3
  timeout_sec = 1
}*/

resource "google_compute_target_pool" "default" {
  name = "chef-server-www-target-pool"
  instances = ["${google_compute_instance.chef-server.*.self_link}"]
}

resource "google_compute_forwarding_rule" "chef_server_http" {
  name = "chef-server-http-forwarding-rule"
  target = "${google_compute_target_pool.default.self_link}"
  port_range = "80"
}

resource "google_compute_forwarding_rule" "chef_server_https" {
  name = "chef-server-https-forwarding-rule"
  target = "${google_compute_target_pool.default.self_link}"
  port_range = "443"
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

  provisioner "file" {
    source      = ".chef"
    destination = "/tmp"
  }

  provisioner "remote-exec" {
    inline = [
      "curl -LO https://omnitruck.chef.io/install.sh && sudo bash ./install.sh -P chefdk -v 12 && rm install.sh",
      "mkdir -p /tmp/elastic-bootstrap/cookbooks"
    ]
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

  provisioner "chef" {
    environment     = "_default"
    attributes_json = <<-EOF
    {
      "chef_server":
       {
         "postgresql":
          {
            "vip": "${google_sql_database_instance.chef.ip_address.0.ip_address}",
            "db_su": "chefpostgres",
            "db_su_pw": "opscode"
          },
        "elasticsearch":
          {
            "vip": "${google_compute_instance.elasticsearch.network_interface.0.address}"
          }
        },
      "cluster_name": "${var.db_name}"
    }
    EOF
    run_list        = ["chef_infrastructure::server"]
    node_name       = "chef-server"
    server_url      = "https://api.chef.io/organizations/gcpmaster"
    recreate_client = true
    user_name       = "adufour"
    user_key        = "${file(".chef/adufour.pem")}"
    version         = "12"
  }
}

resource "google_compute_instance" "chef-server1" {
  name         = "chef-server1"
  machine_type = "n1-standard-1"
  zone         = "us-central1-a"

  depends_on   = ["google_compute_instance.chef-server"]

  tags = ["http-server", "https-server"]
  boot_disk {
    initialize_params {
      image = "centos-cloud/centos-7-v20171003"
    }
  }
  provisioner "file" {
    source      = ".chef"
    destination = "/tmp"
  }
  provisioner "remote-exec" {
    inline = [
      "curl -LO https://omnitruck.chef.io/install.sh && sudo bash ./install.sh -P chefdk -v 12 && rm install.sh",
      "mkdir -p /tmp/elastic-bootstrap/cookbooks"
    ]
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
  provisioner "chef" {
    environment     = "_default"
    attributes_json = <<-EOF
    {
      "chef_server":
       {
         "postgresql":
          {
            "vip": "${google_sql_database_instance.chef.ip_address.0.ip_address}",
            "db_su": "chefpostgres",
            "db_su_pw": "opscode"
          },
        "elasticsearch":
          {
            "vip": "${google_compute_instance.elasticsearch.network_interface.0.address}"
          }
        },
      "cluster_name": "${var.db_name}"
    }
    EOF
    run_list        = ["chef_infrastructure::server"]
    node_name       = "chef-server1"
    server_url      = "https://api.chef.io/organizations/gcpmaster"
    recreate_client = true
    user_name       = "adufour"
    user_key        = "${file(".chef/adufour.pem")}"
    version         = "12"
    vault_json      = "{\"${var.db_name}\": \"automate\"}"
  }
}
/*
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

}*/
