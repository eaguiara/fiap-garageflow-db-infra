#!/usr/bin/env bash
set -euo pipefail

mapfile -t vpc_ids < <(aws ec2 describe-vpcs \
  --filters Name=isDefault,Values=false \
  --query 'Vpcs[].VpcId' \
  --output text | tr '\t' '\n')

if [[ ${#vpc_ids[@]} -eq 0 ]]; then
  echo "No non-default VPCs found."
  exit 0
fi

for vpc_id in "${vpc_ids[@]}"; do
  echo "Deleting resources in ${vpc_id}"

  mapfile -t instance_ids < <(aws ec2 describe-instances \
    --filters "Name=vpc-id,Values=${vpc_id}" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' --output text | tr '\t' '\n')
  if [[ ${#instance_ids[@]} -gt 0 ]]; then
    aws ec2 terminate-instances --instance-ids "${instance_ids[@]}"
    aws ec2 wait instance-terminated --instance-ids "${instance_ids[@]}"
  fi

  mapfile -t load_balancer_arns < <(aws elbv2 describe-load-balancers \
    --query "LoadBalancers[?VpcId=='${vpc_id}'].LoadBalancerArn" --output text | tr '\t' '\n')
  for load_balancer_arn in "${load_balancer_arns[@]}"; do
    [[ -n ${load_balancer_arn} ]] && aws elbv2 delete-load-balancer --load-balancer-arn "${load_balancer_arn}"
  done

  mapfile -t nat_gateway_ids < <(aws ec2 describe-nat-gateways \
    --filter "Name=vpc-id,Values=${vpc_id}" \
    --query 'NatGateways[?State!=`deleted`].NatGatewayId' --output text | tr '\t' '\n')
  for nat_gateway_id in "${nat_gateway_ids[@]}"; do
    [[ -n ${nat_gateway_id} ]] && aws ec2 delete-nat-gateway --nat-gateway-id "${nat_gateway_id}"
  done
  if [[ ${#nat_gateway_ids[@]} -gt 0 ]]; then
    aws ec2 wait nat-gateway-deleted --nat-gateway-ids "${nat_gateway_ids[@]}"
  fi

  mapfile -t vpc_endpoint_ids < <(aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=${vpc_id}" \
    --query 'VpcEndpoints[].VpcEndpointId' --output text | tr '\t' '\n')
  [[ ${#vpc_endpoint_ids[@]} -gt 0 ]] && aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "${vpc_endpoint_ids[@]}"

  mapfile -t internet_gateway_ids < <(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=${vpc_id}" \
    --query 'InternetGateways[].InternetGatewayId' --output text | tr '\t' '\n')
  for internet_gateway_id in "${internet_gateway_ids[@]}"; do
    [[ -n ${internet_gateway_id} ]] || continue
    aws ec2 detach-internet-gateway --internet-gateway-id "${internet_gateway_id}" --vpc-id "${vpc_id}"
    aws ec2 delete-internet-gateway --internet-gateway-id "${internet_gateway_id}"
  done

  mapfile -t subnet_ids < <(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${vpc_id}" \
    --query 'Subnets[].SubnetId' --output text | tr '\t' '\n')
  for subnet_id in "${subnet_ids[@]}"; do
    [[ -n ${subnet_id} ]] && aws ec2 delete-subnet --subnet-id "${subnet_id}"
  done

  mapfile -t security_group_ids < <(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=${vpc_id}" \
    --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text | tr '\t' '\n')
  for security_group_id in "${security_group_ids[@]}"; do
    [[ -n ${security_group_id} ]] && aws ec2 delete-security-group --group-id "${security_group_id}"
  done

  mapfile -t route_table_ids < <(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${vpc_id}" \
    --query 'RouteTables[?Associations[?Main==`false`]].RouteTableId' --output text | tr '\t' '\n')
  for route_table_id in "${route_table_ids[@]}"; do
    [[ -n ${route_table_id} ]] && aws ec2 delete-route-table --route-table-id "${route_table_id}"
  done

  aws ec2 delete-vpc --vpc-id "${vpc_id}"
done
