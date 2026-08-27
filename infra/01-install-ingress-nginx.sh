#!/usr/bin/env bash
# values.yaml's ingress.ingressClassName is "nginx" — this installs the
# ingress-nginx controller that IngressClass belongs to. Exposed as a
# NodePort here (no cloud load balancer available on-prem) — swap to
# MetalLB later if you want a real LoadBalancer-type Service instead.
set -euo pipefail

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443

echo "Verify:"
echo "  kubectl get pods -n ingress-nginx"
echo "  kubectl get svc -n ingress-nginx ingress-nginx-controller"
echo ""
echo "Note the NodePorts (30080/30443) — you'll point DNS/hosts entries at"
echo "<any-node-ip>:30443 for HTTPS, or front this with your own reverse"
echo "proxy/firewall rule mapping 443 -> 30443 if you want a plain port."
