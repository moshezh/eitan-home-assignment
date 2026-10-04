// podinfo pipeline (multibranch). Logic is in scripts/, same as the Makefile.
//
// Credentials expected in Jenkins:
//   registry-ci                      user/password for the registry (Artifactory token)
//   kubeconfig-dev, kubeconfig-prod  secret files, one ci-deployer per namespace
//
// Rollback: run the job on main with ROLLBACK_DIGEST=sha256:... -> deploys that
// image to prod (after approval) and skips everything else.

pipeline {
    agent none

    parameters {
        string(name: 'ROLLBACK_DIGEST', defaultValue: '', description: 'sha256:... of an older prod image. Empty = normal release')
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '30'))
    }

    stages {
        stage('Build & dev') {
            when { expression { !params.ROLLBACK_DIGEST } } // skip the stage in case of rollback
            agent any
            stages {
                stage('Checks') {
                    steps { sh 'make validate' }
                }
                stage('Import + scan + push') {
                    environment { REQUIRE_PINNED_DIGEST = "${env.BRANCH_NAME == 'main'}" }
                    steps {
                        withCredentials([usernamePassword(credentialsId: 'registry-ci', usernameVariable: 'REGISTRY_USER', passwordVariable: 'REGISTRY_PASSWORD')]) {
                            sh 'scripts/import-image.sh'
                        }
                        // later stages may run on another agent, so hold the digest & app_version in env
                        script {
                            env.APP_VERSION = sh(script: '. .build/image.env && echo $APP_VERSION', returnStdout: true).trim()
                            env.IMAGE_DIGEST = sh(script: '. .build/image.env && echo $IMAGE_DIGEST', returnStdout: true).trim()
                            currentBuild.description = "${env.APP_VERSION} ${env.IMAGE_DIGEST.take(19)}"
                        }
                    }
                }
                stage('Deploy dev') {
                    when { branch 'main' }
                    steps {
                        withCredentials([file(credentialsId: 'kubeconfig-dev', variable: 'KUBECONFIG')]) {
                            sh 'scripts/deploy.sh dev'
                        }
                    }
                }
            }
        }

        stage('Approve prod') {
            when {
                beforeInput true
                branch 'main'
            }
            options { timeout(time: 1, unit: 'HOURS') }
            input {
                message 'Deploy to prod?'
                submitter 'release-managers'
            }
            steps { echo "approved ${params.ROLLBACK_DIGEST ?: env.IMAGE_DIGEST}" }
        }

        stage('Prod') {
            when {
                beforeAgent true
                branch 'main'
            }
            agent any
            steps {
                withCredentials([
                    usernamePassword(credentialsId: 'registry-ci', usernameVariable: 'REGISTRY_USER', passwordVariable: 'REGISTRY_PASSWORD'),
                    file(credentialsId: 'kubeconfig-prod', variable: 'KUBECONFIG')
                ]) {
                    script {
                        if (params.ROLLBACK_DIGEST) {
                            sh "scripts/deploy.sh prod ${params.ROLLBACK_DIGEST}"
                        } else {
                            writeFile file: '.build/image.env', text: "APP_VERSION=${env.APP_VERSION}\nIMAGE_DIGEST=${env.IMAGE_DIGEST}\n"
                            sh 'scripts/promote.sh dev prod'
                            sh 'scripts/deploy.sh prod'
                        }
                    }
                }
            }
        }
    }

    post {
        failure {
            // TODO: notify the team Slack channel / mail
            echo 'Failed. If it was a deploy, helm already rolled back to the previous release.'
        }
    }
}
