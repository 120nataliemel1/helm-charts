# Bootstrap image: run once per cluster to install Argo CD and the root Application.
#
#   docker build -t helm-charts-bootstrap .
#   docker run --rm -v ~/.aws:/root/.aws:ro -e AWS_REGION=us-east-1 helm-charts-bootstrap cluster2
#
# alpine/k8s ships helm, kubectl and the aws CLI.
FROM alpine/k8s:1.35.9

# Inside the container there is no kubeconfig, so bootstrap.sh fetches it from EKS
ENV EKS_UPDATE_KUBECONFIG=true

COPY . /repo
WORKDIR /repo
ENTRYPOINT ["/repo/bootstrap.sh"]
