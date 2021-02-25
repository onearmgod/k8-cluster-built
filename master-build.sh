apt-get install -y \
apt-transport-https \
ca-certificates \
curl \
gnupg-agent \
software-properties-common

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

add-apt-repository \
"deb [arch=amd64] https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) \
stable"

apt-get update && apt-get install -y \
containerd.io=1.2.13-2 \
docker-ce=5:19.03.11~3-0~ubuntu-$(lsb_release -cs) \
docker-ce-cli=5:19.03.11~3-0~ubuntu-$(lsb_release -cs)

cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

mkdir -p /etc/systemd/system/docker.service.d

systemctl daemon-reload

systemctl restart docker

systemctl enable docker

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

sysctl --system

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - && \
  echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list && \
  apt-get update -q && \
  apt-get install -qy kubelet=1.19.3-00 kubectl=1.19.3-00 kubeadm=1.19.3-00

apt-mark hold kubelet kubeadm kubectl

sed -i 's/^.*swap/#&/' /etc/fstab

swapoff -a

kubeadm init --pod-network-cidr=10.244.0.0/16 --service-cidr=10.96.0.0/12

sudo -u k8s_admin mkdir -p .kube

cp -i /etc/kubernetes/admin.conf .kube/config

chown k8s_admin:k8s_admin .kube/config

sudo -u k8s_admin mkdir -p kube/yaml

sudo -u k8s_admin kubectl get ds/kube-proxy -o go-template='{{.spec.updateStrategy.type}}{{"\n"}}' --namespace=kube-system

sudo -u k8s_admin wget https://raw.githubusercontent.com/Microsoft/SDN/master/Kubernetes/flannel/l2bridge/manifests/node-selector-patch.yml -P kube/yaml

sudo -u k8s_admin kubectl patch ds/kube-proxy --patch "$(cat kube/yaml/node-selector-patch.yml)" -n=kube-system

sysctl net.bridge.bridge-nf-call-iptables=1

sudo -u k8s_admin wget https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml -P kube/yaml

sudo -u k8s_admin sed -i -e 's/cbr0/vxlan0/g' -e '/Type/s/$/,/' -e '/Type/a\        "VNI" : 4096,\n        "Port": 4789' kube/yaml/kube-flannel.yml

sudo -u k8s_admin kubectl apply -f kube/yaml/kube-flannel.yml

sudo -u k8s_admin curl -L https://github.com/kubernetes-sigs/sig-windows-tools/releases/latest/download/kube-proxy.yml | sed 's/VERSION/v1.19.3/g' | kubectl apply -f -

sudo -u k8s_admin kubectl apply -f https://github.com/kubernetes-sigs/sig-windows-tools/releases/latest/download/flannel-overlay.yml
