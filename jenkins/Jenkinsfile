pipeline {
    agent any

    environment {
        REGISTRY = 'harbor.local'
        PROJECT  = 'pb'
        APP      = 'app'
    }

    stages {
        // ① 拉取代码：URL 与凭据 ID 在此行绑一起（钥匙 github-pat 去开 github.com 这扇门）
        stage('① 拉取代码') {
            steps {
                git branch: 'main',
                    url: 'https://github.com/stupidxiongxiong/todo-app.git',
                    credentialsId: 'github-pat'
            }
        }

        // ② 静态检查：用与 Dockerfile 同版本基础镜像做语法编译，环境一致、不依赖宿主机装 Python
        stage('② 静态检查') {
            steps {
                sh "docker run --rm -v ${WORKSPACE}:/src -w /src python:3.11-slim python -m py_compile app.py"
            }
        }

        // ③ 构建镜像：本地 docker build，tag 用构建号，便于在 Harbor 里追溯
        stage('③ 构建镜像') {
            steps {
                script {
                    env.IMAGE_TAG = "${BUILD_NUMBER}"
                    env.IMAGE_FULL = "${REGISTRY}/${PROJECT}/${APP}:${IMAGE_TAG}"
                    sh "docker build -t ${IMAGE_FULL} ."
                }
            }
        }

        // ④ 推送 Harbor：withRegistry 负责 docker login（用 harbor-creds 这把钥匙开 harbor.local）
        stage('④ 推送 Harbor') {
            steps {
                script {
                    docker.withRegistry("https://${REGISTRY}", 'harbor-creds') {
                        docker.image(env.IMAGE_FULL).push()
                    }
                }
            }
        }

        // ⑤ 更新 K8s 镜像版本：用 k8s-kubeconfig 这把钥匙操作集群，把 deployment 滚动到新镜像
        stage('⑤ 更新 K8s 镜像版本') {
            steps {
                withKubeConfig([credentialsId: 'k8s-kubeconfig']) {
                    // 容器名默认 app；若不一致先用下面命令确认：
                    // kubectl -n todo get deploy app -o jsonpath='{.spec.template.spec.containers[0].name}'
                    sh "kubectl -n todo set image deployment/app app=${IMAGE_FULL}"
                    sh "kubectl -n todo rollout status deployment/app --timeout=60s"
                }
            }
        }
    }
}
