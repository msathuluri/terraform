terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "my-terraforma"
    key = "terraform-state-file-details.tfstate"
    region = "us-east-1"
    
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}
# 1. Creating a VPC

resource "aws_vpc"  "test_vpc" {
    cidr_block = "10.0.0.0/16"

    tags = {
        Name = "test_vpc"
    }
}

# 2. Creating an intenet Gateway

resource "aws_internet_gateway" "test_gateway" {
    vpc_id = aws_vpc.test_vpc.id

    tags = {
        Name = "test_gateway"
    }
}

# 3. Create a Route Table

resource "aws_route_table" "test_rt" {

    vpc_id = aws_vpc.test_vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.test_gateway.id

    }
    route {
        ipv6_cidr_block = "::/0"
        gateway_id = aws_internet_gateway.test_gateway.id
    }

    tags = {
        Name = "test_rt"
    }
}

# 4. Creating a Subnet

resource "aws_subnet" "test_subnet" {
    
    vpc_id = aws_vpc.test_vpc.id
    cidr_block = "10.0.0.0/24"
    availability_zone = "us-east-1a"
    depends_on = [aws_internet_gateway.test_gateway]

    tags = {
        Name = "test_subnet"
    }
}
resource "aws_subnet" "test_subnet_1" {
    
    vpc_id = aws_vpc.test_vpc.id
    cidr_block = "10.0.1.0/24"
    availability_zone = "us-east-1a"
    depends_on = [aws_internet_gateway.test_gateway]

    tags = {
        Name = "test_subnet_1"
    }
}
 # 5. Associate Subnet with Route Table

resource "aws_route_table_association" "RT_to_Subnet" {

    subnet_id = aws_subnet.test_subnet.id
    route_table_id = aws_route_table.test_rt.id
 }

 # 6. Create a Security Group to Allow posrts : 22, 80, 443
resource "aws_security_group" "test_sg" {

    name = "test_sg"
    description = "Allow SSH, HTTP, HTTPS inbound traffic"
    vpc_id = aws_vpc.test_vpc.id

    ingress {
        description = "HTTPS from VPC"
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
        ingress {
        description = "HTTP from VPC"
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

      ingress {
        description = "SSH from VPC"
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "test_sg"
    }
}

# 7. create ec2 instance

resource "aws_instance" "test_instance" {
  
  count = var.ec2_count 
  subnet_id = aws_subnet.test_subnet.id
  ami           = "ami-04b70fa74e45c3917"
  instance_type = "t2.micro"
  associate_public_ip_address  = true
  #security_groups = [aws_security_group.test_sg.id]
  key_name = "tst"
 # iam_instance_profile="AmazonSSMRoleForInstancesQuickSetup"
  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name

  tags = {
    #Name = "test_instance"
    Name = "test_instance ${count.index}"
  }
}



resource "aws_ebs_volume" "test_instance" {
  availability_zone = "us-east-1a"
  count = "${var.volume_count == "true" ? 1:0}"
  size              = 60
  #type = "gp3"

  tags = {
    Name = "test_vol ${count.index}"
  }
}

resource "aws_ebs_volume" "test_instance_1" {
  availability_zone = "us-east-1a"
  size              = 60
  #type = "gp3"

  tags = {
    Name = "test_vol_1"
  }
}

resource "aws_volume_attachment" "test_instance" {
  device_name = "/dev/sde"
  count = "${var.volume_count == "true" ? 1:0}"
  
  volume_id   = aws_ebs_volume.test_instance[count.index].id
  instance_id = aws_instance.test_instance[count.index].id
}
resource "aws_iam_role" "ec2_instance_role" {
  name = "test_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_policy_attachment" {
  for_each = toset(["arn:aws:iam::aws:policy/AmazonS3FullAccess","arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"])
  role       = aws_iam_role.ec2_instance_role.name
  #policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "test_profile"
  role = aws_iam_role.ec2_instance_role.name
}
resource "aws_iam_role" "ssm_role" {
  name = "ssm_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      }
    ]
  })
}

resource "aws_iam_policy" "ssm_policy" {
  name        = "ssm_policy"
  description = "A policy for SSM"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "ssm:DescribeAssociation",
          "ssm:GetDocument",
          "ssm:ListAssociations",
          "ssm:ListInstanceAssociations",
          "ssm:PutInventory",
          "ssm:UpdateAssociationStatus",
          "ssm:UpdateInstanceAssociationStatus",
          "ssm:UpdateInstanceInformation"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_role_policy_attachment" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = aws_iam_policy.ssm_policy.arn
}

