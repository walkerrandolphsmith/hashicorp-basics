# Hashicorp Playground

Deploy Vault and Consol on AWS using a containerized Terraform and Packer.

First elevate priveleges of the control script:

```
chmod +x ./ctl.sh
```

Run the terraform configurations against Terraform:

```
./ctl.sh tf <user> <dir>
```

Run Packer to build amis with vault or consul installed:

```
./ctl.sh packer <file>
```
