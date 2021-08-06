# terraform

This TF code will create an ASG with NLB in front of it. This instance, through NLB, should share port 22 (SSH port) to outside Internet.

To run the code :

1) Edit main.tf and add you AWS credentials
2) Run 'terraform init'
3) Run 'terraform import aws_vpc.main {VPC-ID}' - imports your existing VPC details
4) Run 'terraform plan' - Check all resource creation is as expected
5) Run 'terraform apply'
