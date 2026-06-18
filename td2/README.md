# TD2 — Filtrage réseau et détection d'intrusion sur AWS (Terraform)

Ce dossier contient les 6 fichiers `.tf` du TD, tels que décrits dans le support
(provider, variables, data, bastion, egress, suricata). Il ne reste qu'à les
personnaliser avec vos valeurs et à les exécuter sur votre compte AWS — je n'ai
pas accès à AWS depuis cet environnement, donc le `terraform apply` doit se
faire de votre côté.

## 1. Avant de lancer quoi que ce soit

- Votre IP publique : `curl https://checkip.amazonaws.com`
- Le nom d'une paire de clés EC2 existante dans `eu-west-3` (ou créez-en une)
- Votre numéro d'étudiant (0–99)
- Des credentials AWS configurés : `aws configure` (région `eu-west-3`)

## 2. Personnaliser les variables

Copiez le modèle puis remplissez vos valeurs :

```bash
cp terraform.tfvars.example terraform.tfvars
```

```hcl
student_id = 7
my_ip      = "203.0.113.42/32"
key_name   = "ma-cle-ec2"
```

`terraform.tfvars` est ignoré par git (il contient votre IP) — ne le partagez pas.

## 3. Cycle Terraform

```bash
terraform init
terraform plan
terraform apply        # repondez "yes"
```

## 4. Se connecter au bastion

```bash
ssh -i votre-cle.pem ec2-user@$(terraform output -raw bastion_ip)
```

## 5. Tester le filtrage sortant (depuis le bastion)

```bash
ssh ec2-user@$(terraform output -raw private_ip)     # uniquement accessible depuis le bastion
curl -s https://checkip.amazonaws.com                 # doit renvoyer l IP de la NAT, pas la votre
```

## 6. Tester la sonde Suricata (depuis le bastion)

Laissez ~3 minutes après l'`apply` pour que `user_data` installe Suricata, puis :

```bash
ping -c 5 $(terraform output -raw sonde_private_ip)
ssh ec2-user@$(terraform output -raw sonde_private_ip)
sudo tail -f /var/log/suricata/eve.json | grep TD2
```

Chaque ping doit déclencher une alerte `"TD2 ICMP detecte"`.

## 7. Nettoyage (obligatoire en fin de séance)

```bash
terraform destroy      # repondez "yes"
```

Vérifiez ensuite dans la console AWS qu'il ne reste ni NAT Gateway ni IP
élastique à votre nom (ce sont les ressources les plus coûteuses).

## Fichiers

- `provider.tf` — déclaration du provider AWS
- `variables.tf` — `student_id`, `my_ip`, `key_name`
- `data.tf` — lecture du VPC par défaut et de l'AMI Amazon Linux. **Corrigé** : le sous-réseau public par défaut ayant été supprimé dans le VPC partagé, on cible directement `subnet-095c2c562da7511cc` (le seul sous-réseau dont la route table a une route `0.0.0.0/0 → IGW`). Si jamais ce sous-réseau venait lui aussi à disparaître, il faudrait identifier son remplaçant avec `aws ec2 describe-route-tables`.
- `bastion.tf` — Security Group + instance bastion (filtrage entrant)
- `egress.tf` — sous-réseau privé, NAT Gateway, route, instance privée (filtrage sortant)
- `suricata.tf` — sonde IDS Suricata installée via `user_data`. **Corrigé** : ajout d'un `sed` qui remplace `eth0` par `ens5` dans `/etc/suricata/suricata.yaml`, car les AMI Ubuntu 22.04 récentes nomment l'interface réseau `ens5` alors que la config par défaut de Suricata cible `eth0` — sans ce fix, le service démarre mais ne capture aucun paquet et ne génère donc jamais d'alerte.

## ⚠️ Personnalisation obligatoire

Même avec ces correctifs, **chacun doit remplir ses propres `student_id`, `my_ip` et `key_name`** dans `terraform.tfvars` :
- des valeurs partagées entre deux personnes provoquent des collisions de ressources (même nom de Security Group, même CIDR de sous-réseau) dans ce VPC commun ;
- `my_ip` filtre le SSH du bastion : avec l'IP de quelqu'un d'autre, vous ne pourrez tout simplement pas vous connecter ;
- `key_name` doit correspondre à une paire de clés EC2 qui existe dans **votre propre** compte AWS (`aws ec2 describe-key-pairs --region eu-west-3`).
