#!/bin/sh
set -a

echo ""
echo "=========================================================="
echo "Update CentOS using yum -y update ......"
echo "=========================================================="
echo ""

yum -y update

echo ""
echo "=========================================================="
echo "Install docker ......"
echo "=========================================================="
echo ""

yum -y install docker
# Use registry-mirror 
cat <<EOF > /etc/docker/daemon.json
{
	"registry-mirrors": ["https://registry.docker-cn.com"]
}
EOF

systemctl enable docker
systemctl start docker

echo ""
echo "=========================================================="
echo "Create /etc/yum.repos.d/kubernetes.repo AND install kubelet/kubeadm/kubectl ......"
echo "=========================================================="
echo ""

if [[ ! -f /etc/yum.repos.d/kubernetes.repo ]]; then
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
fi

# Disable SELinux
setenforce 0
# To use flannel, make sure that /proc/sys/net/bridge/bridge-nf-call-iptables is 1
sysctl net.bridge.bridge-nf-call-iptables=1

yum install -y kubelet kubeadm kubectl

systemctl enable kubelet && systemctl start kubelet

echo ""
echo "=========================================================="
echo "Run kubeadm init ......"
echo "=========================================================="
echo ""

IMAGE_REPOSITORY=registry.aliyuncs.com/google_containers

## 拉取镜像
#for i in `kubeadm config images list`; do 
#  imageName=${i#k8s.gcr.io/}
#  docker pull ${IMAGE_REPOSITORY}/$imageName
#  docker tag ${IMAGE_REPOSITORY}/$imageName k8s.gcr.io/$imageName
#  docker rmi ${IMAGE_REPOSITORY}/$imageName
#done;

K8S_VERSION=1.14.1
KUBEADM_TOKEN=$(kubeadm token generate)
K8S_API_ADDVERTISE_IP=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
K8S_API_ENDPOINT=k8s-master
K8S_API_ENDPOINT_INTERNAL=k8s-master.int
K8S_CLUSTER_NAME=Testing

# Setting up /etc/hosts
# sed -i "/${K8S_API_ENDPOINT}/ s/.*/${K8S_API_ADDVERTISE_IP}\t${K8S_API_ENDPOINT}/g" /etc/hosts
# sed -i "/${K8S_API_ENDPOINT_INTERNAL}/ s/.*/${K8S_API_ADDVERTISE_IP}\t${K8S_API_ENDPOINT_INTERNAL}/g" /etc/hosts
sed -i "/${K8S_API_ENDPOINT}/ s/.*//g" /etc/hosts
sed -i "/${K8S_API_ENDPOINT_INTERNAL}/ s/.*//g" /etc/hosts
sed -i "2i${K8S_API_ADDVERTISE_IP}\t${K8S_API_ENDPOINT}" /etc/hosts
sed -i "2i${K8S_API_ADDVERTISE_IP}\t${K8S_API_ENDPOINT_INTERNAL}" /etc/hosts

envsubst < kubeadm-init-config.tmpl.yaml > ./kubeadm-init-config.yaml

kubeadm init --config ./kubeadm-init-config.yaml | tee ./kubeadm-init.log

# kubeadm init --image-repository ${IMAGE_REPOSITORY} --pod-network-cidr 10.244.0.0/16 --token $(kubeadm token generate) --token-ttl 0 --apiserver-cert-extra-sans "k8s-master,k8s-master.int"

# finish init
mkdir -p $HOME/.kube
sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# https://kubernetes.io/docs/setup/independent/create-cluster-kubeadm/
# apply flannel
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/a70459be0084506e4ec919aa1c114638878db11b/Documentation/kube-flannel.yml

echo ""
echo "=========================================================="
echo "Make MasterNode  as WorkerNode ......"
echo "=========================================================="
echo ""

kubectl taint nodes --all node-role.kubernetes.io/master-

## Join the node as worker node
## Use the last 2 lines in kubeadm-init.log
# $(tail -2 ./kubeadm-init.log | sed -z 's/[\\\r\n]//g')
### or
CA_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')
kubeadm join ${K8S_API_ENDPOINT_INTERNAL}:6443 --token ${KUBEADM_TOKEN} --discovery-token-ca-cert-hash sha256:${CA_HASH}

set +a


