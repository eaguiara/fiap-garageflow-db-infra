#!/usr/bin/env bash
set -euo pipefail

# Deletes all supported resources in the AWS CLI's currently configured region.
# This is intentionally destructive and is intended for a disposable account.
if [[ ${1:-} != "--force" ]]; then
  echo "Usage: $0 --force"
  echo "This permanently deletes RDS instances, S3 bucket contents, and non-default VPC resources in the configured AWS region."
  exit 2
fi

aws_ids() {
  aws "$@" --output text | tr '\t' '\n' | sed '/^None$/d;/^$/d'
}

account_id="$(aws sts get-caller-identity --query Account --output text)"
region="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || true)}}"
if [[ -z ${region} ]]; then
  echo "No AWS region configured. Set AWS_REGION or configure the AWS CLI."
  exit 2
fi

echo "Cleaning account ${account_id} in region ${region}"

mapfile -t db_instance_ids < <(aws_ids rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier')
for db_instance_id in "${db_instance_ids[@]}"; do
  echo "Deleting RDS instance ${db_instance_id}"
  aws rds delete-db-instance --db-instance-identifier "${db_instance_id}" --skip-final-snapshot --delete-automated-backups
  aws rds wait db-instance-deleted --db-instance-identifier "${db_instance_id}"
done

mapfile -t db_subnet_group_names < <(aws_ids rds describe-db-subnet-groups --query 'DBSubnetGroups[?DBSubnetGroupName!=`default`].DBSubnetGroupName')
for db_subnet_group_name in "${db_subnet_group_names[@]}"; do
  echo "Deleting RDS subnet group ${db_subnet_group_name}"
  aws rds delete-db-subnet-group --db-subnet-group-name "${db_subnet_group_name}"
done

mapfile -t bucket_names < <(aws_ids s3api list-buckets --query 'Buckets[].Name')
for bucket_name in "${bucket_names[@]}"; do
  bucket_region="$(aws s3api get-bucket-location --bucket "${bucket_name}" --query LocationConstraint --output text)"
  [[ ${bucket_region} == "None" ]] && bucket_region="us-east-1"
  [[ ${bucket_region} == "EU" ]] && bucket_region="eu-west-1"
  [[ ${bucket_region} == "${region}" ]] || continue

  echo "Emptying and deleting S3 bucket ${bucket_name}"
  aws s3 rm "s3://${bucket_name}" --recursive
  aws s3api delete-objects --bucket "${bucket_name}" --delete "$(aws s3api list-object-versions --bucket "${bucket_name}" --query '{Objects: Versions[].{Key:Key,VersionId:VersionId},Quiet:true}' --output json)" 2>/dev/null || true
  aws s3api delete-objects --bucket "${bucket_name}" --delete "$(aws s3api list-object-versions --bucket "${bucket_name}" --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId},Quiet:true}' --output json)" 2>/dev/null || true
  aws s3api delete-bucket --bucket "${bucket_name}"
done

mapfile -t vpc_ids < <(aws_ids ec2 describe-vpcs --filters Name=isDefault,Values=false --query 'Vpcs[].VpcId')
for vpc_id in "${vpc_ids[@]}"; do
  echo "Deleting resources in VPC ${vpc_id}"

  mapfile -t instance_ids < <(aws_ids ec2 describe-instances --filters "Name=vpc-id,Values=${vpc_id}" "Name=instance-state-name,Values=pending,running,stopping,stopped" --query 'Reservations[].Instances[].InstanceId')
  if [[ ${#instance_ids[@]} -gt 0 ]]; then
    aws ec2 terminate-instances --instance-ids "${instance_ids[@]}"
    aws ec2 wait instance-terminated --instance-ids "${instance_ids[@]}"
  fi

  mapfile -t load_balancer_arns < <(aws_ids elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='${vpc_id}'].LoadBalancerArn")
  for load_balancer_arn in "${load_balancer_arns[@]}"; do
    aws elbv2 delete-load-balancer --load-balancer-arn "${load_balancer_arn}"
  done

  mapfile -t vpc_endpoint_ids < <(aws_ids ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=${vpc_id}" --query 'VpcEndpoints[].VpcEndpointId')
  [[ ${#vpc_endpoint_ids[@]} -eq 0 ]] || aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "${vpc_endpoint_ids[@]}"

  mapfile -t nat_gateway_ids < <(aws_ids ec2 describe-nat-gateways --filter "Name=vpc-id,Values=${vpc_id}" --query 'NatGateways[?State!=`deleted`].NatGatewayId')
  for nat_gateway_id in "${nat_gateway_ids[@]}"; do
    aws ec2 delete-nat-gateway --nat-gateway-id "${nat_gateway_id}"
  done
  [[ ${#nat_gateway_ids[@]} -eq 0 ]] || aws ec2 wait nat-gateway-deleted --nat-gateway-ids "${nat_gateway_ids[@]}"

  mapfile -t internet_gateway_ids < <(aws_ids ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=${vpc_id}" --query 'InternetGateways[].InternetGatewayId')
  for internet_gateway_id in "${internet_gateway_ids[@]}"; do
    aws ec2 detach-internet-gateway --internet-gateway-id "${internet_gateway_id}" --vpc-id "${vpc_id}"
    aws ec2 delete-internet-gateway --internet-gateway-id "${internet_gateway_id}"
  done

  mapfile -t eni_ids < <(aws_ids ec2 describe-network-interfaces --filters "Name=vpc-id,Values=${vpc_id}" --query 'NetworkInterfaces[?Status==`available`].NetworkInterfaceId')
  for eni_id in "${eni_ids[@]}"; do
    aws ec2 delete-network-interface --network-interface-id "${eni_id}"
  done

  mapfile -t subnet_ids < <(aws_ids ec2 describe-subnets --filters "Name=vpc-id,Values=${vpc_id}" --query 'Subnets[].SubnetId')
  for subnet_id in "${subnet_ids[@]}"; do
    aws ec2 delete-subnet --subnet-id "${subnet_id}"
  done

  mapfile -t security_group_ids < <(aws_ids ec2 describe-security-groups --filters "Name=vpc-id,Values=${vpc_id}" --query 'SecurityGroups[?GroupName!=`default`].GroupId')
  for security_group_id in "${security_group_ids[@]}"; do
    aws ec2 delete-security-group --group-id "${security_group_id}"
  done

  mapfile -t route_table_ids < <(aws_ids ec2 describe-route-tables --filters "Name=vpc-id,Values=${vpc_id}" --query 'RouteTables[?Associations[?Main==`false`]].RouteTableId')
  for route_table_id in "${route_table_ids[@]}"; do
    aws ec2 delete-route-table --route-table-id "${route_table_id}"
  done

  aws ec2 delete-vpc --vpc-id "${vpc_id}"
done

mapfile -t eip_allocation_ids < <(aws_ids ec2 describe-addresses --query 'Addresses[].AllocationId')
for eip_allocation_id in "${eip_allocation_ids[@]}"; do
  aws ec2 release-address --allocation-id "${eip_allocation_id}" || true
done

echo "Cleanup completed for account ${account_id} in region ${region}."
