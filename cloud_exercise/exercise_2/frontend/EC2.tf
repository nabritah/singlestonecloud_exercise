provider "aws" { #stating the provider and authentication
  region = "us-east-1"
}
#Create VPC
resource "aws_vpc" "yt_vpc" {
  cidr_block = "10.0.0.0/16"
  
}

##create Internet Gateway
resource "aws_internet_gateway" "yt_IG" {
  vpc_id = aws_vpc.yt_vpc.id

}

##creating a custom route table
resource "aws_route_table" "yt_route_table" {

  vpc_id = aws_vpc.yt_vpc.id

  route {
    cidr_block = "0.0.0.0/0" ##point all the ipv4 traffic to where this ip points
    gateway_id = aws_internet_gateway.yt_IG.id
  }

  route {
    ipv6_cidr_block = "::/0" ##so that all traffic from our subnet goes out to the internet
    gateway_id = aws_internet_gateway.yt_IG.id
  }
}

##creating a subnet
resource "aws_subnet" "yt_subnet" {
    vpc_id = aws_vpc.yt_vpc.id
    cidr_block = "10.0.1.0/24"
    availability_zone = "us-east-1a"

}

##Associate subnet with route table
resource "aws_route_table_association" "yt_ass_route_table" {
    subnet_id = aws_subnet.yt_subnet.id
    route_table_id = aws_route_table.yt_route_table.id

}

##create a security group

resource "aws_security_group" "allow_web" {
  name        = "allow_web"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.yt_vpc.id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] ## connection from all IPaddresses

  }
  egress {
    from_port   = 0 ##allowing any ports in the eggress direction
    to_port     = 0
    protocol    = "-1" ##Any protocol
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

##creat a network interface within an ip in the subnet that was created in step 4
resource "aws_network_interface" "yt_network_interface" {
  subnet_id       = aws_subnet.yt_subnet.id
  private_ips     = ["10.0.1.50"] ##We can assign multiple ips too
  security_groups = [aws_security_group.allow_web.id]

  #attachment {
    #instance     = aws_instance.test.id
    #device_index = 1
  #}

  
}

 ##we also need to create an elastic IP (public IP) so that everybody on the internet can access. Always deploy the elastic IP after deploying the internet gateway because it's dependent on the internet gateway. 
resource "aws_eip" "yt_elastic_ip" {
  
  vpc      = true
  network_interface = aws_network_interface.yt_network_interface.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [aws_internet_gateway.yt_IG] ##instructs terraform that this resource deponds on the internet gateway. When referencing the IGW we don't put .id because we want the whole IGW

}

#Create the Ubuntu server  and install/enable apache2
resource "aws_instance" "yt_webserver_instance" {
    ami = "ami-0747bdcabd34c712a"
    instance_type = "t2.micro"
    availability_zone = "us-east-1a"
    key_name = "pair_name"

    network_interface {
        device_index = 0
        network_interface_id = aws_network_interface.yt_network_interface.id

    }

    #output "name" {
        #value = resourcecommand.resourcename.propertyname(got from the commaand of terraform state show resource.resourcename) 
        #value = you can enter as many value lines as you want
    #}

    #variable "name" {
        #description = "What your variable is about"
        #efault = "value that terraform will assign your variable a value if you don't assign it"
        #type = value type e.g string
    #}

    #user_data = "${file("bootstrap.sh")}"

    #tags = {
        #Name = "web_server"
    #}

    provisioner "remote-exec" {
      inline = [
        "sudo apt update -y",
        "sudo apt install apache2 -y",
        "sudo systemctl start apache2",
        "sudo systemctl enable apache2",
        "sudo chown -R ubuntu:ubuntu /var/www/html"
      
      ]
    }

    connection {
      type = "ssh"
      user = "ubuntu"
      private_key = "${file("/path_to_private_key_file")}"
      host = self.public_ip
    
      #timeout = "2m"
    } 

    provisioner "file" {
      source = "/path_to_index.html_file"
      destination = "/var/www/html/index.html" 
    }
  
}


