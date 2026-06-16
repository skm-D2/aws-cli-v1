#!/bin/bash

# charger les constantes puis les fonctions
source "$(dirname "$0")/cli/constants/constants.sh"
source "$(dirname "$0")/cli/services/ec2.sh"

# --- Programme principal ---
create_nacl "$1"
network_acl_id=$(jq -r '.NetworkAcl.NetworkAclId' nacl.json)
create_ingress_rule "$network_acl_id" 100 6 443 443 allow
