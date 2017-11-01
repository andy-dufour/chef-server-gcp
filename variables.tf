variable "gcp_region" {
  default = "us-central1"
}

variable "gcp_credentials_file" {
  default = "/Users/andrewdufour/.gcp/AndrewDufour-0afa53a0e663.json"
}

variable "gcp_project" {
 default = "andrewdufour-183117"
}

variable "gcp_image_user" {
 default = "adufour"
}

variable "gcp_private_key" {
 default = "/Users/andrewdufour/.ssh/id_rsa"
}

variable "db_name" {
  default = "chef-psql"
}
