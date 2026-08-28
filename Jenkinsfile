pipeline {
  agent { label 'helm-agent' }
  stages {
    stage('Checkout') {
      steps { checkout scm }
    }
    stage('Lint Chart') {
      steps {
        container('helm') {
          sh 'helm lint charts/snipeit'
        }
      }
    }
    stage('Render & Validate') {
      steps {
        container('helm') {
          sh 'helm template snipeit charts/snipeit -f charts/snipeit/values-production.yaml > rendered.yaml'
        }
        container('kubeconform') {
          // -ignore-missing-schemas: this chart's templates/external-secret.yaml
          // renders ExternalSecret objects (external-secrets.io/v1beta1), a CRD
          // with no schema in kubeconform's default Kubernetes OpenAPI catalog.
          // Without this flag, every build fails on that resource alone,
          // regardless of whether the rendered YAML is actually correct.
          // -kubernetes-version pinned to match the real cluster (v1.31.14,
          // per the Kubernetes Installation Guide) rather than validating
          // against whatever kubeconform defaults to.
          sh 'kubeconform -strict -ignore-missing-schemas -kubernetes-version 1.31.14 rendered.yaml'
        }
      }
    }
    stage('Package Chart') {
      steps {
        container('helm') {
          sh 'helm package charts/snipeit -d dist/'
        }
      }
    }
    stage('Commit Rendered Change') {
      when { branch 'main' }
      steps {
        // NOTE: this assumes `git` is present in the "helm" container's
        // image (alpine/helm:3.14.0). Unverified here — if this stage
        // fails with "git: not found", the fix is either an image that
        // bundles both helm and git, or adding a third sidecar container
        // dedicated to git operations, same pattern as the kubeconform
        // container above.
        container('helm') {
          sh '''
            git config user.email "jenkins@betxchange.local"
            git config user.name "Jenkins CI"
            git add charts/snipeit/values-production.yaml
            git commit -m "ci: validated chart change" || echo "nothing to commit"
            git push origin main
          '''
        }
      }
    }
  }
}
