#!/bin/bash

create_nacl() {
    local nacl_name="$1"
    aws_response=$(aws ec2 create-network-acl \
        --vpc-id $VPC_ID \
        --tag-specifications "ResourceType=network-acl,Tags=[{Key=Name,Value=$nacl_name}]")
    echo "$aws_response" > nacl.json
}

delete_nacl() {
    local nacl_name="$1"
    local nacl_id
    nacl_id=$(aws ec2 describe-network-acls \
        --filters "Name=tag:Name,Values=$nacl_name" \
        --query "NetworkAcls[0].NetworkAclId" \
        --output text)
    aws ec2 delete-network-acl --network-acl-id "$nacl_id"
}

create_ingress_rule() {
    local network_acl_id="$1"
    local rule_number="$2"
    local protocol="${3:-6}"
    local from="${4:-443}"
    local to="${5:-443}"
    local rule_action="${6:-deny}"

    aws ec2 create-network-acl-entry \
        --network-acl-id "$network_acl_id" \
        --rule-number "$rule_number" \
        --protocol "$protocol" \
        --port-range From="$from",To="$to" \
        --cidr-block 0.0.0.0/0 \
        --rule-action "$rule_action" \
        --ingress
}
