pipelineJob('devsecops-pipeline') {
  definition {
    cpsScm {
      scm {
        git {
          remote {
            url('https://github.com/UdayKumarChunduru/devsecops-cicd-pipeline.git')
          }
          branch('*/aws')
        }
      }
      scriptPath('Jenkinsfile')
    }
  }
}
