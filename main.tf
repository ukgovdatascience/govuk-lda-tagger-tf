variable "aws_region" { default = "eu-west-2" }
variable "appname" {default = "GovUKLDATagger" }
variable "environ" {default = "production"}
variable "dockerimg" {default = "ukgovdatascience/govuk-lda-tagger-image:latest"}

provider "aws" {
  region = "${var.aws_region}"
  profile = "gds-data"
}

module "vpc" {
  source = "github.com/terraform-community-modules/tf_aws_vpc"
  name = "${var.appname}-${var.environ}-vpc"
  cidr = "10.100.0.0/16"
  public_subnets  = ["10.100.101.0/24" , "10.100.102.0/24"]
  azs = ["eu-west-2a", "eu-west-2b"]
}

resource "aws_security_group" "allow_all_ssh" {
  name_prefix = "${var.appname}-${var.environ}-${module.vpc.vpc_id}-"
  description = "Allow all inbound SSH traffic"
  vpc_id = "${module.vpc.vpc_id}"

  ingress = {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# This role has a trust relationship which allows
# to assume the role of ec2
resource "aws_iam_role" "ecs" {
  name = "${var.appname}_ecs_${var.environ}"
  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "ec2.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
      }
    ]
  }
  EOF
}

# This is a policy attachement for the "ecs" role, it provides access
# to the the ECS service.
resource "aws_iam_policy_attachment" "ecs_for_ec2" {
  name = "${var.appname}_${var.environ}"
  roles = ["${aws_iam_role.ecs.id}"]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_ecs_cluster" "ecs-lda-tagger" {
  name = "ecs-lda-tagger-cluster"
}
