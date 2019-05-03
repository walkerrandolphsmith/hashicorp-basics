# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY a Vault Cluster, AN ELB, AND A Consul Cluster in AWS
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  backend "s3" {
    encrypt         = true
    bucket          = "dogmada-terraform-state"
    dynamodb_table = "terraform-state-lock-dynamo"
    region          = "us-east-1"
    key             = "terraform-mgmt/test"
  }
}

provider "aws" {
  region = "${var.region}"
}

resource "aws_s3_bucket" "terraform-state-storage-s3" {
    bucket = "dogmada-terraform-state"
 
    versioning {
      enabled = true
    }
 
    lifecycle {
      prevent_destroy = true
    }

    tags {
      Name = "S3 Remote Terraform State Store"
    }
}

# # ---------------------------------------------------------------------------------------------------------------------
# # DEPLOY THE VAULT SERVER CLUSTER
# # ---------------------------------------------------------------------------------------------------------------------

module "vault_cluster" {
  source = "github.com/hashicorp/terraform-aws-vault//modules/vault-cluster?ref=v0.11.1"

  cluster_name  = "${var.vault_cluster_name}"
  cluster_size  = "${var.vault_cluster_size}"
  instance_type = "${var.vault_instance_type}"

  ami_id    = "${var.ami}"
  user_data = "${data.template_file.user_data_vault_cluster.rendered}"

  vpc_id     = "${data.aws_vpc.default.id}"
  subnet_ids = "${data.aws_subnet_ids.default.ids}"

  # Do NOT use the ELB for the ASG health check
  # or the ASG will assume all sealed instances are unhealthy and
  # repeatedly try to redeploy them.
  health_check_type = "EC2"

  # TODO: limit this to the IP address ranges of known, trusted servers inside your VPC.

  allowed_ssh_cidr_blocks              = ["0.0.0.0/0"]
  allowed_inbound_cidr_blocks          = ["0.0.0.0/0"]
  allowed_inbound_security_group_ids   = []
  allowed_inbound_security_group_count = 0
  ssh_key_name                         = "${var.ssh_key_name}"
}

# # ---------------------------------------------------------------------------------------------------------------------
# # ATTACH IAM POLICIES FOR CONSUL
# # To allow our Vault servers to automatically discover the Consul servers, we need to give them the IAM permissions from
# # the Consul AWS Module's consul-iam-policies module.
# # ---------------------------------------------------------------------------------------------------------------------

module "consul_iam_policies_servers" {
  source = "github.com/hashicorp/terraform-aws-consul//modules/consul-iam-policies?ref=v0.4.0"

  iam_role_id = "${module.vault_cluster.iam_role_id}"
}

# # ---------------------------------------------------------------------------------------------------------------------
# # THE USER DATA SCRIPT THAT WILL RUN ON EACH VAULT SERVER WHEN IT'S BOOTING
# # This script will configure and start Vault
# # ---------------------------------------------------------------------------------------------------------------------

data "template_file" "user_data_vault_cluster" {
  template = "${file("user-data-vault.sh")}"

  vars {
    aws_region               = "${var.region}"
    consul_cluster_tag_key   = "${var.consul_cluster_tag_key}"
    consul_cluster_tag_value = "${var.consul_cluster_name}"
  }
}

# # ---------------------------------------------------------------------------------------------------------------------
# # PERMIT CONSUL SPECIFIC TRAFFIC IN VAULT CLUSTER
# # To allow our Vault servers consul agents to communicate with other consul agents and participate in the LAN gossip,
# # we open up the consul specific protocols and ports for consul traffic
# # ---------------------------------------------------------------------------------------------------------------------

module "security_group_rules" {
  source = "github.com/hashicorp/terraform-aws-consul.git//modules/consul-client-security-group-rules?ref=v0.4.0"

  security_group_id = "${module.vault_cluster.security_group_id}"

  # TODO: limit this to the IP address ranges of known, trusted servers inside your VPC.

  allowed_inbound_cidr_blocks = ["0.0.0.0/0"]
}

# # ---------------------------------------------------------------------------------------------------------------------
# # DEPLOY THE ELB
# # ---------------------------------------------------------------------------------------------------------------------

module "vault_elb" {
  source = "github.com/hashicorp/terraform-aws-vault//modules/vault-elb?ref=v0.11.1"

  name = "${var.vault_cluster_name}"

  vpc_id     = "${data.aws_vpc.default.id}"
  subnet_ids = "${data.aws_subnet_ids.default.ids}"

  # Associate the ELB with the instances created by the Vault Autoscaling group
  vault_asg_name = "${module.vault_cluster.asg_name}"

  # To make testing easier, we allow requests from any IP address here but in a production deployment, we *strongly*
  # recommend you limit this to the IP address ranges of known, trusted servers inside your VPC.
  allowed_inbound_cidr_blocks = ["0.0.0.0/0"]

  # In order to access Vault over HTTPS, we need a domain name that matches the TLS cert
  create_dns_entry = "${var.create_dns_entry}"

  # Terraform conditionals are not short-circuiting, so we use join as a workaround to avoid errors when the
  # aws_route53_zone data source isn't actually set: https://github.com/hashicorp/hil/issues/50
  hosted_zone_id = "${var.create_dns_entry ? join("", data.aws_route53_zone.selected.*.zone_id) : ""}"

  domain_name = "${var.vault_domain_name}"
}

# Look up the Route 53 Hosted Zone by domain name
data "aws_route53_zone" "selected" {
  count = "${var.create_dns_entry}"
  name  = "${var.hosted_zone_domain_name}."
}

# # ---------------------------------------------------------------------------------------------------------------------
# # DEPLOY THE CONSUL SERVER CLUSTER
# # ---------------------------------------------------------------------------------------------------------------------

module "consul_cluster" {
  source = "github.com/hashicorp/terraform-aws-consul//modules/consul-cluster?ref=v0.4.0"

  cluster_name  = "${var.consul_cluster_name}"
  cluster_size  = "${var.consul_cluster_size}"
  instance_type = "${var.consul_instance_type}"

  # The EC2 Instances will use these tags to automatically discover each other and form a cluster
  cluster_tag_key   = "${var.consul_cluster_tag_key}"
  cluster_tag_value = "${var.consul_cluster_name}"

  ami_id    = "${var.ami}"
  user_data = "${data.template_file.user_data_consul.rendered}"

  vpc_id     = "${data.aws_vpc.default.id}"
  subnet_ids = "${data.aws_subnet_ids.default.ids}"

  # TODO: limit this to the IP address ranges of known, trusted servers inside your VPC.

  allowed_ssh_cidr_blocks     = ["0.0.0.0/0"]
  allowed_inbound_cidr_blocks = ["0.0.0.0/0"]
  ssh_key_name                = "${var.ssh_key_name}"
}

# # ---------------------------------------------------------------------------------------------------------------------
# # THE USER DATA SCRIPT THAT WILL RUN ON EACH CONSUL SERVER WHEN IT'S BOOTING
# # This script will configure and start Consul
# # ---------------------------------------------------------------------------------------------------------------------

data "template_file" "user_data_consul" {
  template = "${file("user-data-consul.sh")}"

  vars {
    aws_region               = "${var.region}"
    consul_cluster_tag_key   = "${var.consul_cluster_tag_key}"
    consul_cluster_tag_value = "${var.consul_cluster_name}"
  }
}

# # ---------------------------------------------------------------------------------------------------------------------
# # DEPLOY THE CLUSTERS IN THE DEFAULT VPC AND AVAILABILITY ZONES
# # TODO: Deploy into a custom VPC and private subnets.
# # Only the ELB should run in the public subnets.
# # ---------------------------------------------------------------------------------------------------------------------

data "aws_vpc" "default" {
  default = "${var.use_default_vpc}"
}

data "aws_subnet_ids" "default" {
  vpc_id = "${data.aws_vpc.default.id}"
}
