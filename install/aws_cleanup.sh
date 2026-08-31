#!/bin/bash

path=$(dirname $0) 
clusterId=$(cat $path/../installer-files/infraID)

if [ -z "$clusterId" ]; then
  exit 
fi

if [ -z "$AWS_ACCESS_KEY_ID" ]; then
  exit 80
fi
if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
  exit 80
fi
if [ -z "$AWS_DEFAULT_REGION" ]; then
  exit 80
fi


echo "0 - Start processing for cluster $clusterId - waiting for masters to be destroyed"
masters=3
while [ $masters -gt 0 ]; do
  nodes=$(aws ec2 describe-instances --filters Name="tag:kubernetes.io/cluster/${clusterId}",Values="owned"  Name="instance-state-name",Values="running" --query 'Reservations[].Instances[].[InstanceId, Tags[?Key==`Name`] | [0].Value]' --output text)
  masters=$(echo "$nodes" | grep master | wc -l) 
  echo "Waiting for masters to be destroyed - $masters remaining"
  if [ $masters -gt 0 ]; then
    sleep 10
  fi
done
workers=$(echo "$nodes" | cut -d$'\t' -f1)

echo "1 - Deleting workers - $workers -"
if [ ! -z "$workers" ]; then 
  aws ec2 terminate-instances --instance-ids ${workers} 
fi
vpcid=$(aws ec2 describe-vpcs --filters Name="tag:kubernetes.io/cluster/${clusterId}",Values="owned" --query 'Vpcs[].VpcId' --output text)
elbname=$(aws elb describe-load-balancers --query  'LoadBalancerDescriptions[].[LoadBalancerName,VPCId]' --output text | grep $vpcid | cut -d$'\t' -f1)
echo "2 - Deleting apps load balancers - $elbname - "
# $elbname may list multiple Classic ELBs (ingress plus any LoadBalancer
# Services created in-cluster); delete each on its own since
# delete-load-balancer accepts only a single --load-balancer-name.
for lb in $elbname; do
  echo "  deleting elb $lb"
  aws elb delete-load-balancer --load-balancer-name "$lb"
done
sleep 30

sg=$(aws ec2 describe-security-groups --filters Name="tag:kubernetes.io/cluster/${clusterId}",Values="owned" --query 'SecurityGroups[].[GroupId,GroupName]' --output text | grep "k8s-elb" | cut -d$'\t' -f1)

echo "3 - Deleting elb security group(s) - $sg -"
attempts=0
while [ ! -z "$sg" ] && [ $attempts -lt 30 ]; do
  # $sg may contain multiple group ids (one per ELB); delete each on its own,
  # since `delete-security-group` accepts only a single --group-id. Ignore
  # transient dependency errors and retry until they clear (or we hit the cap).
  for g in $sg; do
    echo "  deleting $g"
    aws ec2 delete-security-group --group-id "$g" 2>/dev/null || true
  done
  sleep 10
  attempts=$((attempts + 1))
  sg=$(aws ec2 describe-security-groups --filters Name="tag:kubernetes.io/cluster/${clusterId}",Values="owned" --query 'SecurityGroups[].[GroupId,GroupName]' --output text | grep "k8s-elb" | cut -d$'\t' -f1)
done

s3imagereg=$(aws s3 ls | grep ${clusterId} | awk '{print $3}') 
echo "4 - Deleting S3 image-registry $s3imagereg -"
if [ ! -z "$s3imagereg" ]; then
  aws s3 rb --force s3://$s3imagereg
fi
iamusers=$(aws iam list-users --query 'Users[].[UserName,UserId]' --output text | grep ${clusterId})
echo "5 - Deleting iamusers - $iamusers"
if [ ! -z "$iamusers" ]; then
  echo "$iamusers" | awk '{print "aws iam delete-user-policy --user-name "$1" --policy-name "$1"-policy"}' | bash
  echo "$iamusers" | awk '{print "aws iam delete-access-key --user-name "$1" --access-key-id $(aws iam list-access-keys --user-name "$1" --query 'AccessKeyMetadata[].AccessKeyId' --output text)"}' | bash
  echo "$iamusers" | awk '{print "aws iam delete-user --user-name "$1}' | bash
fi
exit 0
