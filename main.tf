# welcome to this script.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  required_version = ">= 1.3.0"
}
resource "aws_vpc" "my_vpc" {
  cidr_block = "172.16.0.0/16"

  tags = {
    Name = "tf-example"
  }
}

resource "aws_subnet" "my_subnet" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "172.16.10.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "tf-example"
  }
}

resource "aws_subnet" "my_subnet_b" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "172.16.11.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "tf-example-b"
  }
}

resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "tf-example"
  }
}

resource "aws_route_table" "my_public_route_table" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }

  tags = {
    Name = "tf-example-public"
  }
}

resource "aws_route_table_association" "my_public_subnet" {
  subnet_id      = aws_subnet.my_subnet.id
  route_table_id = aws_route_table.my_public_route_table.id
}

resource "aws_route_table_association" "my_public_subnet_b" {
  subnet_id      = aws_subnet.my_subnet_b.id
  route_table_id = aws_route_table.my_public_route_table.id
}

resource "aws_network_interface" "example" {
  subnet_id   = aws_subnet.my_subnet.id
  private_ips = ["172.16.10.100"]

  tags = {
    Name = "primary_network_interface"
  }
}

resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow SSH inbound traffic"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "Allow HTTP traffic to the load balancer"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "allow_http_from_load_balancer" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.allow_ssh.id
  source_security_group_id = aws_security_group.allow_http.id
  description              = "Allow HTTP traffic from the load balancer"
}

resource "aws_instance" "example" {

  for_each               = toset(["server-a", "server-b", "server-c", "server-d", "server-e"])
  ami                    = "ami-0b6d9d3d33ba97d99"
  instance_type          = "t3.micro"
  key_name               = "keypairomar3"
  subnet_id              = aws_subnet.my_subnet.id
  vpc_security_group_ids = [aws_security_group.allow_ssh.id]
  user_data              = <<-EOF
              #!/bin/bash
              set -e

              # Update system packages
              sudo apt-get update -y
              sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release

              # --- INSTALL DOCKER ---
              sudo mkdir -p /etc/at/keyrings
              curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
              echo \
                "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
                $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

              sudo apt-get update -y
              sudo apt-get install -y docker-ce docker-ce-cli containerd.io
              sudo systemctl enable docker
              sudo systemctl start docker

              # Add default ubuntu user to docker group
              sudo usermod -aG docker ubuntu

              # --- PULL AND RUN DOCKER CONTAINER ---
              # Replace 'nginx:latest' with your target Docker image (e.g., username/repository:tag)
              
              sudo docker pull uncloakauditor/taskboardproject
              
              sudo docker run -d --name my_app --restart always -p 5000:5000 uncloakauditor/taskboardproject
              EOF

  tags = {
    Name = each.key # Assigns the name directly from the set
  }
}

resource "aws_lb" "example" {
  name               = "tf-example-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_http.id]
  subnets            = [aws_subnet.my_subnet.id, aws_subnet.my_subnet_b.id]

  tags = {
    Name = "tf-example-alb"
  }
}

resource "aws_lb_target_group" "example" {
  name     = "tf-example-targets"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.my_vpc.id

  health_check {
    path = "/"
  }
}

resource "aws_lb_target_group_attachment" "example" {
  for_each         = aws_instance.example
  target_group_arn = aws_lb_target_group.example.arn
  target_id        = each.value.id
  port             = 80
}

resource "aws_lb_listener" "example" {
  load_balancer_arn = aws_lb.example.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.example.arn
  }
}

output "load_balancer_url" {
  description = "Public URL of the application load balancer"
  value       = "http://${aws_lb.example.dns_name}"
}
