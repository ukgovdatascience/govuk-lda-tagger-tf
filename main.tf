variable "aws_region" { default = "eu-west-2" }
variable "appname" {default = "GovUKLDATagger" }
variable "environ" {default = "production"}
variable "dockerimg" {default = "ukgovdatascience/govuk-lda-tagger-image:latest"}
variable "key_name" {default = "andreagrandi"}

# Values are taken from https://github.com/aws/amazon-ecs-cli/blob/master/ecs-cli/modules/config/ami/ami.go#L32
variable "ami" {
  description = "AWS ECS AMI id"
  default = {
    eu-west-1 = "ami-bd7e8dc4"
    eu-west-2 = "ami-0a85946e"
  }
}

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

resource "aws_security_group" "allow_all_outbound" {
  name_prefix = "${var.appname}-${var.environ}-${module.vpc.vpc_id}-"
  description = "Allow all outbound traffic"
  vpc_id = "${module.vpc.vpc_id}"

  egress = {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "allow_cluster" {
  name_prefix = "${var.appname}-${var.environ}-${module.vpc.vpc_id}-"
  description = "Allow all traffic within cluster"
  vpc_id = "${module.vpc.vpc_id}"

  ingress = {
    from_port = 0
    to_port = 65535
    protocol = "tcp"
    self = true
  }

  egress = {
    from_port = 0
    to_port = 65535
    protocol = "tcp"
    self = true
  }
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

# resource "aws_ecs_service" "ecs_service" {
#   name = "${var.appname}_${var.environ}"
#   cluster = "${aws_ecs_cluster.cluster.id}"
#   task_definition = "${aws_ecs_task_definition.ecs_task.arn}"
#   desired_count = 3
#   iam_role = "${aws_iam_role.ecs_elb.arn}"
#   depends_on = ["aws_iam_policy_attachment.ecs_elb"]
#   deployment_minimum_healthy_percent = 50

#   load_balancer {
#     elb_name = "${aws_elb.service_elb.id}"
#     container_name = "${var.appname}_${var.environ}"
#     container_port = "${var.docker_port}"
#   }
# }

resource "template_file" "user_data" {
  template = "ec2_user_data.tmpl"
  vars {
    cluster_name = "${var.appname}_${var.environ}"
  }
}

resource "aws_iam_instance_profile" "ecs" {
  name = "${var.appname}_${var.environ}"
  roles = ["${aws_iam_role.ecs.name}"]
}

resource "aws_launch_configuration" "ecs_cluster" {
  name = "${var.appname}_cluster_conf_${var.environ}"
  instance_type = "t2.micro"
  image_id = "${lookup(var.ami, var.aws_region)}"
  iam_instance_profile = "${aws_iam_instance_profile.ecs.id}"
  associate_public_ip_address = true
  security_groups = [
    "${aws_security_group.allow_all_ssh.id}",
    "${aws_security_group.allow_all_outbound.id}",
    "${aws_security_group.allow_cluster.id}",
  ]
  user_data = "${template_file.user_data.rendered}"
  key_name = "${var.key_name}"
}

resource "aws_autoscaling_group" "ecs_cluster" {
  name = "${var.appname}_${var.environ}"
  vpc_zone_identifier = ["10.100.101.0/24" , "10.100.102.0/24"]
  min_size = 0
  max_size = 3
  desired_capacity = 3
  launch_configuration = "${aws_launch_configuration.ecs_cluster.name}"
  health_check_type = "EC2"
}
