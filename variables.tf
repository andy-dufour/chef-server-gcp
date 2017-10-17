variable "gcp_region" {
  default = "us-west1"
}

variable "gcp_credentials_file" {
  default = "/Users/jmiller/.gcp/habitat-kubernetes-playland-0d9934e67750.json"
}

variable "gcp_project" {
 default = "habitat-kubernetes-playland"
}

variable "gcp_image_user" {
 default = "jmiller"
}

variable "gcp_private_key" {
 default = "/Users/jmiller/.ssh/google_compute_engine"
}
