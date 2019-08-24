# aws-route53-zone

#### Maintained by [@goci-io/prp-terraform](https://github.com/orgs/goci-io/teams/prp-terraform)

This terraform module provisions a new AWS Route53 Hosted Zone. 

If you need to delegate DNS from a different AWS Account or use a parent hosted zone the Nameservers are automatically synchronized by using the specified `aws_profile` to assume an external role defined in the AWS profile.

The `domain_name` can either be specified in the `terraform.tfvars` or autogenerated from a label module. 
When autogenerating the name the following convention is applied: `<name>.<stage>.<attributes>.<namespace>.tld`. 
The `tld` will be sourced either from `parent_domain_zone` if set or the `tld` variable itself. 
For the following stages the stage will be omitted when using the autogenerated label (`prod`, `production`, `main`)

### Usage

Look into the [terraform.tfvars](terraform.tfvars.example) for examples.
