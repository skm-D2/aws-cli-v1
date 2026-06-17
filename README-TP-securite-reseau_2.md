# TP — Sécurité appliquée au Cloud : VPC, EC2, Security Groups & NACL

> Mastère Cybersécurité · BC Design Systems / IPSSI — AWS Academy
> Région : `eu-west-3` (Paris) · VPC par défaut : `vpc-0ebcdb39f7a526ef9` (172.31.0.0/16)
> Réalisé par : **tegrace** (`user/bel`)

Ce TP sécurise un réseau AWS dans le VPC par défaut : on place un **bastion** (avec IP
publique) et une **cible** (sans IP publique), on filtre les accès avec des **Security
Groups** (stateful), puis on illustre le comportement **stateless** d'une **NACL** et la
**défense en profondeur**. Tout est réalisé en **AWS CLI**.

> **Note environnement partagé.** Le compte AWS est partagé entre plusieurs étudiants.
> Les ressources sont préfixées `tegrace-` pour éviter les conflits, et la NACL n'a
> **volontairement pas été associée** au sous-réseau partagé afin de ne pas couper
> l'accès des autres (un autre étudiant avait une instance sur le même subnet). C'est une
> bonne pratique appliquée : ne pas impacter les ressources partagées.

---

## Sommaire

1. [Prérequis et environnement](#1-prérequis-et-environnement)
2. [Explorer le VPC par défaut](#2-explorer-le-vpc-par-défaut)
3. [Lancer les deux instances EC2](#3-lancer-les-deux-instances-ec2)
4. [Security Groups (stateful)](#4-security-groups-stateful)
5. [NACL (stateless) et ports éphémères](#5-nacl-stateless-et-ports-éphémères)
6. [Défense en profondeur (NACL + SG)](#6-défense-en-profondeur-nacl--sg)
7. [Nettoyage](#7-nettoyage)
8. [Réponses aux questions](#8-réponses-aux-questions)
9. [Conclusion](#9-conclusion--bonnes-pratiques)

---

## 1. Prérequis et environnement

Récupération de l'IP publique du poste (utilisée comme `MON_IP/32` pour le filtrage SSH)
et protection de la clé privée.

```bash
curl https://checkip.amazonaws.com        # -> 82.96.161.255
chmod 400 ~/.ssh/tegrace_key
```

Variables réutilisées tout au long du TP :

```bash
VPC=vpc-0ebcdb39f7a526ef9
SUBNET=subnet-095c2c562da7511cc           # sous-réseau par défaut, eu-west-3a, 172.31.192.0/20
AMI=ami-05dfcc4b49790367c                 # Amazon Linux 2023
MONIP=82.96.161.255/32
```

---

## 2. Explorer le VPC par défaut

```bash
# VPC par défaut + plage
aws ec2 describe-vpcs --region eu-west-3 \
  --filters Name=isDefault,Values=true \
  --query "Vpcs[].{Id:VpcId,Cidr:CidrBlock}" --output table

# Sous-réseau utilisé
aws ec2 describe-subnets --region eu-west-3 \
  --filters "Name=vpc-id,Values=$VPC" \
  --query "Subnets[].{Id:SubnetId,Az:AvailabilityZone,Cidr:CidrBlock}" --output table

# Vérifier la route vers l'Internet Gateway (sous-réseau public)
aws ec2 describe-route-tables --region eu-west-3 \
  --filters "Name=vpc-id,Values=$VPC" \
  --query "RouteTables[].{Main:Associations[?Main]|[0].Main,IGW:Routes[?DestinationCidrBlock=='0.0.0.0/0'].GatewayId}" --output json
```

Le sous-réseau est **public** : sa table de routage envoie `0.0.0.0/0` vers l'Internet
Gateway `igw-06d61463409eb8f84`.

---

## 3. Lancer les deux instances EC2

Un **bastion** avec IP publique (porte d'entrée SSH) et une **cible** sans IP publique
(serveur protégé), dans le même sous-réseau.

```bash
# Bastion : AVEC IP publique
aws ec2 run-instances --region eu-west-3 --image-id $AMI \
  --instance-type t3.micro --key-name tegrace_key \
  --subnet-id $SUBNET --associate-public-ip-address \
  --security-group-ids $SG_BASTION --count 1 \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=tegrace-bastion}]'

# Cible : SANS IP publique
aws ec2 run-instances --region eu-west-3 --image-id $AMI \
  --instance-type t3.micro --key-name tegrace_key \
  --subnet-id $SUBNET --no-associate-public-ip-address \
  --security-group-ids $SG_CIBLE --count 1 \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=tegrace-cible}]'
```

Vérification : le bastion a une IP publique, la cible n'en a pas (colonne `Public` = `None`).

```bash
aws ec2 describe-instances --region eu-west-3 \
  --filters "Name=tag:Name,Values=tegrace-bastion,tegrace-cible" \
            "Name=instance-state-name,Values=running,pending" \
  --query "Reservations[].Instances[].{Name:Tags[?Key=='Name']|[0].Value,Id:InstanceId,Public:PublicIpAddress,Private:PrivateIpAddress}" \
  --output table
```

| Instance | IP privée | IP publique |
|---|---|---|
| tegrace-bastion | 172.31.195.201 | 15.237.116.61 |
| tegrace-cible | 172.31.206.80 | *(aucune)* |

---

## 4. Security Groups (stateful)

On autorise le strict nécessaire : SSH vers le bastion **depuis mon IP seulement**, et
accès à la cible **uniquement depuis le groupe bastion** (source = un Security Group, pas
une plage d'IP).

```bash
# SG bastion : SSH depuis mon IP
SG_BASTION=$(aws ec2 create-security-group --region eu-west-3 \
  --group-name tegrace-sg-bastion --description "SSH depuis mon IP" \
  --vpc-id $VPC --query "GroupId" --output text)
aws ec2 authorize-security-group-ingress --region eu-west-3 \
  --group-id $SG_BASTION --protocol tcp --port 22 --cidr $MONIP

# SG cible : SSH + ICMP depuis le GROUPE bastion
SG_CIBLE=$(aws ec2 create-security-group --region eu-west-3 \
  --group-name tegrace-sg-cible --description "Acces depuis bastion" \
  --vpc-id $VPC --query "GroupId" --output text)
aws ec2 authorize-security-group-ingress --region eu-west-3 \
  --group-id $SG_CIBLE --protocol tcp --port 22 --source-group $SG_BASTION
aws ec2 authorize-security-group-ingress --region eu-west-3 \
  --group-id $SG_CIBLE --protocol icmp --port -1 --source-group $SG_BASTION
```

Test de bout en bout : connexion au bastion, puis rebond vers la cible (avec agent SSH).

```bash
ssh-add ~/.ssh/tegrace_key
ssh -A -i ~/.ssh/tegrace_key ec2-user@15.237.116.61
# depuis le bastion :
ping -c 3 172.31.206.80          # répond -> ICMP autorisé
ssh ec2-user@172.31.206.80       # ouvre une session sur la cible
```

Le ping et le SSH fonctionnent, et la réponse revient sans règle de sortie explicite :
c'est le comportement **stateful** du Security Group (le trafic retour est autorisé
automatiquement).

---

## 5. NACL (stateless) et ports éphémères

On crée une NACL personnalisée pour illustrer le comportement **stateless**. Elle n'est
**pas associée** au sous-réseau (compte partagé), la démonstration se fait donc sur les
règles elles-mêmes.

```bash
NACL=$(aws ec2 create-network-acl --region eu-west-3 --vpc-id $VPC \
  --tag-specifications 'ResourceType=network-acl,Tags=[{Key=Name,Value=tegrace-nacl}]' \
  --query "NetworkAcl.NetworkAclId" --output text)

# Entrée n°100 : SSH autorisé depuis mon IP
aws ec2 create-network-acl-entry --region eu-west-3 --network-acl-id $NACL \
  --rule-number 100 --protocol 6 --port-range From=22,To=22 \
  --cidr-block $MONIP --rule-action allow --ingress

# Sortie n°100 : ports éphémères (trafic retour, indispensable en stateless)
aws ec2 create-network-acl-entry --region eu-west-3 --network-acl-id $NACL \
  --rule-number 100 --protocol 6 --port-range From=1024,To=65535 \
  --cidr-block 0.0.0.0/0 --rule-action allow --egress
```

**Pourquoi la règle de sortie 1024-65535 est indispensable :** quand on se connecte en
SSH, le paquet entrant arrive sur le port 22 (règle d'entrée). Mais la **réponse** du
serveur repart vers le **port éphémère** du client (1024-65535), pas vers le port 22.
Comme la NACL est **stateless** (elle ne mémorise pas la connexion entrante), il faut une
règle de **sortie** explicite sur ces ports, sinon la réponse est bloquée par la règle
implicite `deny` (n°32767) et la session ne s'établit jamais. C'est « l'erreur n°1 des
NACL ».

---

## 6. Défense en profondeur (NACL + SG)

On ajoute une règle `deny` de **numéro plus petit** (90) que la règle `allow` (100). AWS
évalue les règles par numéro croissant et s'arrête à la première qui correspond : la 90
(deny) est donc évaluée **avant** la 100 (allow).

```bash
aws ec2 create-network-acl-entry --region eu-west-3 --network-acl-id $NACL \
  --rule-number 90 --protocol 6 --port-range From=22,To=22 \
  --cidr-block $MONIP --rule-action deny --ingress
```

Conséquence : un paquet SSH serait **refusé** par la NACL, même si la règle 100 l'autorise
juste en dessous, et **même si le Security Group de l'instance l'autorise**. La NACL filtre
au niveau **sous-réseau**, le SG au niveau **instance** : deux couches indépendantes, le
plus restrictif l'emporte.

---

## 7. Nettoyage

On supprime uniquement ce qui a été créé. Le VPC par défaut, ses sous-réseaux et l'IGW
restent intacts.

```bash
# Supprimer la NACL (jamais associée -> suppression directe)
aws ec2 delete-network-acl --region eu-west-3 --network-acl-id $NACL

# Terminer les deux instances
aws ec2 terminate-instances --region eu-west-3 \
  --instance-ids i-0b86b33fa0819b6a1 i-0c05d3152eef6c8f1

# Une fois "terminated", supprimer les SG (la cible d'abord, elle référence le bastion)
aws ec2 delete-security-group --region eu-west-3 --group-id $SG_CIBLE
aws ec2 delete-security-group --region eu-west-3 --group-id $SG_BASTION
```

---

## 8. Réponses aux questions

**Partie 1 — Plage du VPC et sous-réseaux « publics » ?**
Le VPC par défaut a la plage `172.31.0.0/16`. Ses sous-réseaux sont qualifiés de publics
car leur table de routage envoie `0.0.0.0/0` vers une Internet Gateway : une instance avec
IP publique y est donc joignable depuis Internet.

**Partie 1 — Rendre une instance injoignable sans sous-réseau privé ?**
En ne lui attribuant **pas d'IP publique** : sans IP publique, elle n'est pas joignable
directement depuis Internet, seulement depuis l'intérieur du VPC.

**Partie 2 — Laquelle des deux est joignable depuis Internet ?**
Le **bastion**, parce qu'il a une IP publique. La cible, sans IP publique, ne l'est pas,
bien qu'elle soit dans le même sous-réseau public.

**Partie 2 — Comment atteindre la cible ?**
En **rebondissant par le bastion** (SSH vers le bastion, puis SSH du bastion vers l'IP
privée de la cible).

**Partie 3 — Pourquoi sourcer le sg-cible sur le groupe bastion plutôt qu'une IP ?**
Parce que les IP privées des instances peuvent changer (recréation, redémarrage). Référencer
le **Security Group** rend la règle stable et lisible : « tout ce qui vient du bastion est
autorisé », quelle que soit l'IP.

**Partie 3 — Pourquoi la réponse repart-elle sans règle de sortie ?**
Parce que le Security Group est **stateful** : il mémorise la connexion entrante autorisée
et laisse repartir automatiquement le trafic retour correspondant.

**Partie 4 — Pourquoi autoriser en sortie 1024-65535 et non le port 22 ?**
Parce que la réponse du serveur repart vers le **port éphémère** du client (1024-65535),
pas vers le port 22.

**Partie 4 — Différence SG vs NACL en une phrase ?**
Le Security Group est **stateful** (le retour est autorisé automatiquement) ; la NACL est
**stateless** (chaque sens doit être autorisé par une règle explicite).

**Partie 5 — Si le SG autorise mais la NACL refuse, le trafic passe-t-il ?**
Non. La NACL est évaluée au niveau du sous-réseau, **avant** le SG ; si elle refuse, le
paquet est jeté quel que soit le SG.

**Partie 5 — Avantage de deux couches de filtrage ?**
La défense en profondeur : si une couche est mal configurée ou contournée, l'autre filtre
encore. La NACL protège globalement le sous-réseau, le SG protège finement l'instance.

---

## 9. Conclusion : bonnes pratiques

- **Moindre privilège** : n'ouvrir que ce qui est nécessaire (SSH au bastion depuis une
  seule IP, accès à la cible seulement depuis le bastion).
- **Ne jamais exposer SSH (22) en `0.0.0.0/0`** : cible n°1 des scans.
- **Isolation par l'absence d'IP publique** plutôt qu'un simple filtrage.
- **Référencer un Security Group comme source** plutôt qu'une IP, pour des règles stables.
- **Comprendre stateful vs stateless** : une NACL exige les deux sens (ports éphémères en
  retour), contrairement au SG.
- **Défense en profondeur** : combiner NACL (sous-réseau) et SG (instance).
- **Respecter les ressources partagées** : sur un compte commun, ne pas appliquer une NACL
  restrictive à un sous-réseau utilisé par d'autres, et nettoyer ses ressources en fin de TP.
