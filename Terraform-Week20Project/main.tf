/*
Deploy an EC2 instance in the default Amazon (VPC) and bootstrap Jenkins installation.

Contributor / Author:  Desi Beam
Date:  06/06/2023
*/

#Terraform Providers Block - Configure the AWS Provider.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.0.1"
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

## TLS provider - create a resource generating RSA private key
resource "tls_private_key" "jenkins-private-key" {
  algorithm = "RSA"
}

## local provider - interact with a local file system
#                   to save the generated RSA private key into a file, "MyAWSKey.pem"
resource "local_file" "jenkins-private-key-pem" {
  content  = tls_private_key.jenkins-private-key.private_key_pem
  filename = "MyAWSKey.pem"
}

# Create SSH keypair and associate it with your EC2 instance
resource "aws_key_pair" "jenkins-SSH-key-pair" { # generate public key remotely
  key_name   = "MyAWSKey"
  public_key = tls_private_key.jenkins-private-key.public_key_openssh
  lifecycle {
    ignore_changes = [key_name]
  }
}


# Terraform Resource Block - Build EC2 Jenkins Server.  
resource "aws_instance" "ec2-jenkins" {
  ami                    = data.aws_ami.amazon-linux-2.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.ssh-ingress-egress-sg.id]
  key_name               = "MyAWSKey"
  user_data= <<-EOF
    #!/bin/bash
     sudo chmod +x /tmp/jenkinsscript.sh
     sh /tmp/jenkinsscript.sh
      sudo yum update -y
      sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
      sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
      sudo yum upgrade -y
      sudo amazon-linux-extras install java-openjdk11 -y
      sudo yum install jenkins -y
      sudo systemctl daemon-reload
      sudo systemctl enable jenkins
      sudo systemctl start jenkins
      sudo cat /var/lib/jenkins/secrets/initialAdminPassword
  EOF


  tags = {
    Name = "Amazon Linux EC2 Jenkins Server"
  }

  depends_on = [
    aws_key_pair.jenkins-SSH-key-pair
  ]
}

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