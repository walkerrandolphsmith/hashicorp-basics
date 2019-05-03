terraform init \
  -backend-config="address=demo.consul.io" \
  -backend-config="path=example_app/terraform_state" \
  -backend-config="scheme=https"
