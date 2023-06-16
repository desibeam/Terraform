/*
Deploy an EC2 instance in the default Amazon Virtual Private Cloud (VPC) 
and bootstrap it with Jenkins installation using a script. The goal is to set up a Jenkins server 
for continuous integration and continuous delivery (CI/CD) purposes.

Contributor / Author:  Joan Owusu
Date:  5/29/2023
*/

#Terraform Providers Block - Configure the AWS Provider.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.1.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Terraform Data Block - To Lookup Latest Amazon AMI Image.
data "aws_ami" "amazon-linux-2" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*"]
  }

  owners = ["amazon"]
}


# Terraform Resource Block - Create a Key Pair.
resource "aws_key_pair" "terraform" {
  key_name   = "terraform-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDCjfX8f3Ikq4Tf/ZN16g/AINACrduB3YUOzG60gzgg56oyLqBz5Z+R3JSj8V1S9rnTrhOPiJfq68w5vkmaVkLvS95NIo/jbhpG6FWJqeq7NStMZUgsQteP2RGTM6Cp93JyVl2EtVO4H0Khv9KZaCXCkd4YkjT0DR19tTUM3DcJqcbb0rliKRtZd0yPwtbFnDd0aVk1sdaoP/dQI4wuH7J6BER4aZ51f+NRm9zxJSKvQim4fcuBX+V9GgVxGa1Gp0Pt7nEinRJ43pChYkeF+kNyAVZ6TzH704LRVLAqY2lLadXDLYzjSTrHqE70vpu3KDSNdS9NNf5lyDj8prTcdU0p ec2-user@ip-172-31-28-123.us-west-2.compute.internal"
}

# Terraform Resource Block - Build EC2 Jenkins Server.  
resource "aws_instance" "ec2-jenkins" {
  ami                    = data.aws_ami.amazon-linux-2.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.ssh-ingress-egress-sg.id]
  key_name               = "terraform-key"

  # Terraform Connection Block - To Connect to EC2 Server.
  # Connection block will tell terraform how to connect to the EC2 server. 
  # Connection block should be nested within a resource or provisioner block.
  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ec2-user"
    private_key = file("id_rsa")
  }

  # Terraform Remote-Exec Provisioner Block - Runs remote commands on the EC2 instance provisioned with Terraform.
  # Jenkins server will be installed if the commands run successfully. 
  provisioner "remote-exec" {
    inline = [
      "sudo amazon-linux-extras install epel -y",
      "sudo yum update -y",
      "sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo",
      "sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key",
      "sudo yum upgrade -y",
      "sudo yum install java-11-openjdk",
      "sudo yum install jenkins -y",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable Jenkins",
      "sudo systemctl start Jenkins",
      "sudo systemctl status jenkins",
    ]
  }

  tags = {
    Name = "Amazon Linux EC2 Jenkins Server"
  }

  depends_on = [
    aws_key_pair.terraform
  ]

}

/* Terraform Resource Block - Create a Security Group.
a. Ingress rules:
    -- Port 22   - Allows SSH to EC2 instance.
    -- Port 8080 - Allows traffic from port 8080 (HTTP).
    -- Port 443  - Allows secured traffic from port 443 (HTTPS).
b. Egress rule:
    -- Allows traffic for everything.*/

resource "aws_security_group" "ssh-ingress-egress-sg" {
  name        = "allow-ssh-ingress-egress"
  description = "Allow inbound and outboud traffic"

  ingress {
    description = "Allow Port 22"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow Port 8080"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow Port 443"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all ip and ports outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow-ssh-ingress-egress"
  }
}

# Terraform Resource Block - Generate a random id for S3 bucket.
resource "random_id" "randomness" {
  byte_length = 16
}

# Terraform Resource Block - Create a S3 Bucket.
# Create a S3 bucket for Jenkins Artifacts that is not open to the public.
resource "aws_s3_bucket" "jenkins-artifacts-bucket" {
  bucket = "new-jenkins-artifacts-bucket-${random_id.randomness.hex}"
  tags = {
    Name    = "Jenkins Artifacts S3 Bucket"
    Purpose = "Bucket to store Jenkins Artifacts"
  }
}

# Terraform Resource Block - Create Bucket Ownership.
resource "aws_s3_bucket_ownership_controls" "jenkins-artifacts-bucket" {
  bucket = aws_s3_bucket.jenkins-artifacts-bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Terraform Resource Block - Create a Private ACL for S3 bucket.
resource "aws_s3_bucket_acl" "jenkins-artifacts-bucket" {
  depends_on = [aws_s3_bucket_ownership_controls.jenkins-artifacts-bucket]

  bucket = aws_s3_bucket.jenkins-artifacts-bucket.id
  acl    = "private"
}
