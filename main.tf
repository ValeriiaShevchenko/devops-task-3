provider "aws" {
    region = "us-east-2"
}

resource "aws_instance" "example_ec2" {
    ami = "ami-0c55b159cbfafe1f0"
    instance_type = "t2.micro"

    user_data = <<-EOF
                #!/bin/bash
                echo "This is a web-server" > index.html
                nohup busybox httpd -f -p "${var.server_port}" &
                EOF

    vpc_security_group_ids = [aws_security_group.asg_ec2_example.id] 

    tags = { 
        Name = "terraform-example_ec2"
    }
}

resource "aws_instance" "scanner_ec2" {
    ami = "ami-0c55b159cbfafe1f0"
    instance_type = "t2.micro"

    user_data = <<-EOF
                #!/bin/bash
                sudo apt update
                sudo apt install apt-transport-https ca-certificates curl software-properties-common
                curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add 
                sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable"
                sudo apt update
                sudo apt install docker-ce
                sudo systemctl status docker
                docker pull owasp/zap2docker-stable
                sudo docker run -i owasp/zap2docker-stable zap-cli quick-scan --self-contained --start-options '-config api.disablekey=true' "http://${aws_instance.example_ec2.public_ip}:${var.server_port}"
                
                EOF

    vpc_security_group_ids = [aws_security_group.asg_ec2_example.id] 

    tags = { 
        Name = "terraform-scanner_ec2"
    }
}


resource "aws_security_group" "asg_ec2_example" {
    name = "asg_ec2_example"

    ingress {
        from_port = var.server_port
        to_port = var.server_port
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

variable "server_port" {
    description = "HTTP requests port"
    type = number
    default = 8080
}

resource "aws_api_gateway_rest_api" "api" {
    name = "api-gateway"
    description = "Proxy to handle requests to our API"
}

resource "aws_api_gateway_resource" "resource" {
    rest_api_id = "${aws_api_gateway_rest_api.api.id}"
    parent_id   = "${aws_api_gateway_rest_api.api.root_resource_id}"
    path_part   = "{proxy+}"
}
resource "aws_api_gateway_method" "method" {
    rest_api_id   = "${aws_api_gateway_rest_api.api.id}"
    resource_id   = "${aws_api_gateway_resource.resource.id}"
    http_method   = "GET"
    authorization = "NONE"
    request_parameters = {
        "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "integration" {
    rest_api_id = "${aws_api_gateway_rest_api.api.id}"
    resource_id = "${aws_api_gateway_resource.resource.id}"
    http_method = "${aws_api_gateway_method.method.http_method}"  
    integration_http_method = "GET"
    type                    = "HTTP_PROXY"
    uri                     = "http://${aws_instance.example_ec2.public_ip}:${var.server_port}"
 
    request_parameters =  {
        "integration.request.path.proxy" = "method.request.path.proxy"
    }
}

