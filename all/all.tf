# AWS용 프로바이더 구성
provider "aws" {
  profile = "default"
  region = "ap-northeast-2"
}

## 예제에서는 서울리전 만 지정한다.
variable "region" {
  default = "ap-northeast-2"
}

locals {
  ## 신규 VPC 를 구성하는 경우 svc_nm 과 pem_file 를 새로 넣어야 한다.
  svc_nm = "dyheo"
  pem_file = "dyheo-histech-2"

  ## 신규 구축하는 시스템의 cidr 를 지정한다. 
  public_subnets = {
    "${var.region}a" = "10.55.101.0/24"
#    "${var.region}b" = "10.55.102.0/24"
#    "${var.region}c" = "10.55.103.0/24"
  }
  private_subnets = {
    "${var.region}a" = "10.55.111.0/24"
#    "${var.region}b" = "10.55.112.0/24"
#    "${var.region}c" = "10.55.113.0/24"
  }
}

resource "aws_vpc" "this" {
  ## cidr 를 지정해야 한다.
  cidr_block = "10.55.0.0/16"

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.svc_nm}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = "${aws_vpc.this.id}"

  tags = {
    Name = "${local.svc_nm}-igw"
  }
}

resource "aws_subnet" "public" {
  count      = "${length(local.public_subnets)}"
  cidr_block = "${element(values(local.public_subnets), count.index)}"
  vpc_id     = "${aws_vpc.this.id}"

  map_public_ip_on_launch = true
  availability_zone       = "${element(keys(local.public_subnets), count.index)}"

  tags = {
    Name = "${local.svc_nm}-sb-public"
  }
}

resource "aws_subnet" "private" {
  count      = "${length(local.private_subnets)}"
  cidr_block = "${element(values(local.private_subnets), count.index)}"
  vpc_id     = "${aws_vpc.this.id}"

  map_public_ip_on_launch = true
  availability_zone       = "${element(keys(local.private_subnets), count.index)}"

  tags = {
    Name = "${local.svc_nm}-sb-private"
  }
}

resource "aws_default_route_table" "public" {
  default_route_table_id = "${aws_vpc.this.main_route_table_id}"

  tags = {
    Name = "${local.svc_nm}-public"
  }
}

resource "aws_route" "public_internet_gateway" {
  count                  = "${length(local.public_subnets)}"
  route_table_id         = "${aws_default_route_table.public.id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.this.id}"

  timeouts {
    create = "5m"
  }
}

resource "aws_route_table_association" "public" {
  count          = "${length(local.public_subnets)}"
  subnet_id      = "${element(aws_subnet.public.*.id, count.index)}"
  route_table_id = "${aws_default_route_table.public.id}"
}

resource "aws_route_table" "private" {
  vpc_id = "${aws_vpc.this.id}"

  tags = {
    Name = "${local.svc_nm}-private"
  }
}

resource "aws_route_table_association" "private" {
  count          = "${length(local.private_subnets)}"
  subnet_id      = "${element(aws_subnet.private.*.id, count.index)}"
  route_table_id = "${aws_route_table.private.id}"
}

resource "aws_eip" "nat" {
  vpc = true

  tags = {
    Name = "${local.svc_nm}-eip"
  }
}

resource "aws_nat_gateway" "this" {
  allocation_id = "${aws_eip.nat.id}"
  subnet_id     = "${aws_subnet.public.0.id}"

  tags = {
    Name = "${local.svc_nm}-nat-gw"
  }
}

resource "aws_route" "private_nat_gateway" {
  route_table_id         = "${aws_route_table.private.id}"
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = "${aws_nat_gateway.this.id}"

  timeouts {
    create = "5m"
  }
}


# AWS Security Group
resource "aws_security_group" "security-group" {
  name        = "monolithi-sg"
  description = "dyheo terraform security group"
  vpc_id      = "${aws_vpc.this.id}"

  ingress = [
    {
      description      = "HTTP"
      from_port        = 80
      to_port          = 80
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
      prefix_list_ids  = []
      security_groups  = []
      self = false
    },
    {
      description      = "SSH from home"
      from_port        = 22
      to_port          = 22
      protocol         = "tcp"
      type             = "ssh"
      cidr_blocks      = ["125.177.68.23/32", "211.206.114.80/32"]
      ipv6_cidr_blocks = ["::/0"]
      prefix_list_ids  = []
      security_groups  = []
      self = false
    }
  ]

  egress = [
    {
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
      prefix_list_ids  = []
      security_groups  = []
      self = false
      description = "outbound all"
    }
  ]

  tags = {
    Name = "${local.svc_nm}-sg"
  }
}

# AWS EC2 , 여러대 만드는 경우 aws_instance 를 여러개 만들어야 한다.
resource "aws_instance" "ec2-01" {

  ## EC2 를 만드는 경우 ami 과 instance type 을 지정해야 한다.
  ami = "ami-0e4a9ad2eb120e054"
  instance_type = "t2.micro"

  key_name = "${local.pem_file}"
  vpc_security_group_ids = ["${aws_security_group.security-group.id}"]
  
  subnet_id = "${aws_subnet.public.0.id}"
  tags = {
    Name = "${local.svc_nm}_ec2-01"
  }

# HelloWorld App Code
  provisioner "remote-exec" {
    connection {
      host = self.public_ip
      user = "ec2-user"
      ## 홈경로 밑에 .ssh 에 pem file 이 있어야 한다.
      private_key = "${file("~/.ssh/${local.pem_file}.pem")}"
    }
    inline = [
      "echo 'repository set'",
      "sudo yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm -y",
      "sudo yum update -y"
    ]
  }
## ANSIBLE playbook 을 삽입하는 경우 여기에 삽입한다.  
#  provisioner "local-exec" {
#    command = "echo '[inventory] \n${self.public_ip}' > ./inventory"
#  }
#  provisioner "local-exec" {
#    command = "ansible-playbook --private-key='~/.ssh/"${pem_file}".pem' -i inventory monolith.yml"
#  }
}

output "dyheo-ec2-ip" {
  value = "${aws_instance.ec2-01.public_ip}"
}

