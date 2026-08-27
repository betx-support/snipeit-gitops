pipeline {
  agent { label 'helm-agent' }
  stages {
    stage('Checkout') {
      steps { checkout scm }
    }
    stage('Lint Chart') {
      steps {
        sh 'helm lint charts/snipeit'
      }
    }
    stage('Render & Validate') {
      steps {
        sh 'helm template snipeit charts/snipeit -f charts/snipeit/values-production.yaml > rendered.yaml'
        sh 'kubeconform -strict rendered.yaml'
      }
    }
    stage('Package Chart') {
      steps {
        sh 'helm package charts/snipeit -d dist/'
      }
    }
    stage('Commit Rendered Change') {
      when { branch 'main' }
      steps {
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
