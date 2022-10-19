#!/bin/bash

#
# Lecture https://rht-labs.com/tech-exercise/#
#

#
# Input
#
USERNAME=$1
PASSWORD=$2

#
# Configuration
#
TEAM_NAME=zteam
CLUSTER_DOMAIN=apps.ocp4.example.com
GIT_SERVER=gitlab-ce.apps.ocp4.example.com
OCP_CONSOLE=https://console-openshift-console.apps.ocp4.example.com

if [ "$1" == "--reset" ]
then
  helm uninstall my tl500/todolist --namespace ${TEAM_NAME}-ci-cd
  helm uninstall argocd --namespace ${TEAM_NAME}-ci-cd
  helm uninstall uj --namespace ${TEAM_NAME}-ci-cd
  oc delete all --all -n ${TEAM_NAME}-ci-cd
  exit 0
fi


echo
echo "#######################################"
echo "### The Manual Menace -> The Basics ###"
echo "#######################################"
echo

#
# Set env
#
echo "Configuring environment"
echo export TEAM_NAME="${TEAM_NAME}" | tee -a ~/.bashrc -a ~/.zshrc
echo export CLUSTER_DOMAIN="${CLUSTER_DOMAIN}" | tee -a ~/.bashrc -a ~/.zshrc
echo export GIT_SERVER="${GIT_SERVER}" | tee -a ~/.bashrc -a ~/.zshrc
echo export USERNAME="${USERNAME}" | tee -a ~/.bashrc -a ~/.zshrc
echo export PASSWORD="${PASSWORD}" | tee -a ~/.bashrc -a ~/.zshrc
echo export GITLAB_USER="${USERNAME}" | tee -a ~/.bashrc -a ~/.zshrc
echo export GITLAB_PASSWORD="${PASSWORD}" | tee -a ~/.bashrc -a ~/.zshrc
echo export OCP_CONSOLE=https://console-openshift-console.apps.ocp4.example.com | tee -a ~/.bashrc -a ~/.zshrc

source ~/.bashrc
echo ${TEAM_NAME}
echo ${CLUSTER_DOMAIN}
echo ${GIT_SERVER}
source /usr/local/bin/user-functions.sh

#
# Login to OCP4 and create project
#
echo "Loging to OCP4"
oc login --server=https://api.${CLUSTER_DOMAIN##apps.}:6443 -u ${USERNAME} -p ${PASSWORD}
oc new-project ${TEAM_NAME}-ci-cd || true

#
# Help
#
echo "Running helm"
helm repo add tl500 https://rht-labs.com/todolist
helm search repo todolist
helm install my tl500/todolist --namespace ${TEAM_NAME}-ci-cd || true
echo https://$(oc get route/my-todolist -n ${TEAM_NAME}-ci-cd --template='{{.spec.host}}')
sleep 60
oc get pods -n ${TEAM_NAME}-ci-cd
helm uninstall my --namespace ${TEAM_NAME}-ci-cd

echo
echo "###################################"
echo "### The Manual Menace -> ArgoCD ###"
echo "###################################"
echo

helm repo add redhat-cop https://redhat-cop.github.io/helm-charts

run()
{
  NS=$(oc get subscriptions.operators.coreos.com/openshift-gitops-operator -n openshift-operators \
    -o jsonpath='{.spec.config.env[?(@.name=="ARGOCD_CLUSTER_CONFIG_NAMESPACES")].value}')
  opp=
  if [ -z $NS ]; then
    NS="${TEAM_NAME}-ci-cd"
    opp=add
  elif [[ "$NS" =~ .*"${TEAM_NAME}-ci-cd".* ]]; then
    echo "${TEAM_NAME}-ci-cd already added."
    return
  else
    NS="${TEAM_NAME}-ci-cd,${NS}"
    opp=replace
  fi
  oc -n openshift-operators patch subscriptions.operators.coreos.com/openshift-gitops-operator --type=json \
    -p '[{"op":"'$opp'","path":"/spec/config/env/1","value":{"name": "ARGOCD_CLUSTER_CONFIG_NAMESPACES", "value":"'${NS}'"}}]'
  echo "EnvVar set to: $(oc get subscriptions.operators.coreos.com/openshift-gitops-operator -n openshift-operators \
    -o jsonpath='{.spec.config.env[?(@.name=="ARGOCD_CLUSTER_CONFIG_NAMESPACES")].value}')"
}
run

cat << EOF > /projects/tech-exercise/argocd-values.yaml
ignoreHelmHooks: true
operator: []
namespaces:
  - ${TEAM_NAME}-ci-cd
argocd_cr:
  initialRepositories: |
    - url: https://${GIT_SERVER}/${TEAM_NAME}/tech-exercise.git
      type: git
      passwordSecret:
        key: password
        name: git-auth
      usernameSecret:
        key: username
        name: git-auth
      insecure: true
EOF

helm upgrade --install argocd \
  --namespace ${TEAM_NAME}-ci-cd \
  -f /projects/tech-exercise/argocd-values.yaml \
  redhat-cop/gitops-operator

sleep 60
oc get pods -n ${TEAM_NAME}-ci-cd
ARGO_URL=$( echo https://$(oc get route argocd-server --template='{{ .spec.host }}' -n ${TEAM_NAME}-ci-cd ))
echo export ARGO_URL="${ARGO_URL}" | tee -a ~/.bashrc -a ~/.zshrc

echo "==> Log to ${ARGO_URL} and perform manual steps 6), 7), 8), 9) and 10)"
read -p "Press [Enter] when done to continue..."

echo https://$(oc get route/our-todolist -n ${TEAM_NAME}-ci-cd --template='{{.spec.host}}')

echo
echo "###############################################"
echo "### The Manual Menace -> Ubiquitous Journey ###"
echo "###############################################"
echo

echo "==> Log to https://${GIT_SERVER} and perform the manual steps 1), 2), 3), 4) and 5)"
read -p "Press [Enter] when done to continue..."

source ~/.bashrc
GITLAB_PAT=$(gitlab_pat)
echo export GITLAB_PAT="${GITLAB_PAT}" | tee -a ~/.bashrc -a ~/.zshrc
echo "GITLAB_USER: ${GITLAB_USER}"
echo "GITLAB_PAT:  ${GITLAB_PAT}"

cd /projects/tech-exercise
git remote set-url origin https://${GIT_SERVER}/${TEAM_NAME}/tech-exercise.git
cd /projects/tech-exercise
git add .
git commit -am "ADD - argocd values file"
git push -u origin --all

yq eval -i '.team=env(TEAM_NAME)' /projects/tech-exercise/values.yaml
yq eval ".source = \"https://$GIT_SERVER/$TEAM_NAME/tech-exercise.git\"" -i /projects/tech-exercise/values.yaml
sed -i "s|TEAM_NAME|$TEAM_NAME|" /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml

cd /projects/tech-exercise/
git add .
git commit -m  "ADD - correct project names"
git push

cat <<EOF | oc apply -n ${TEAM_NAME}-ci-cd -f -
  apiVersion: v1
  data:
    password: "$(echo -n ${GITLAB_PAT} | base64 -w0)"
    username: "$(echo -n ${GITLAB_USER} | base64 -w0)"
  kind: Secret
  type: kubernetes.io/basic-auth
  metadata:
    annotations:
      tekton.dev/git-0: https://${GIT_SERVER}
      sealedsecrets.bitnami.com/managed: "true"
    labels:
      credential.sync.jenkins.openshift.io: "true"
    name: git-auth
EOF

cd /projects/tech-exercise
helm upgrade --install uj --namespace ${TEAM_NAME}-ci-cd .
oc get projects | grep ${TEAM_NAME}
oc get pods -n ${TEAM_NAME}-ci-cd

echo "==> Log to ${ARGO_URL} and verify that ubiquitous-journey app is deployed"
read -p "Press [Enter] when done to continue..."

echo
echo "######################################"
echo "### The Manual Menace -> Extend UJ ###"
echo "######################################"
echo

cd /projects/tech-exercise
git remote set-url origin https://${GIT_SERVER}/${TEAM_NAME}/tech-exercise.git
git pull
ARGO_WEBHOOK=$(echo https://$(oc get route argocd-server --template='{{ .spec.host }}'/api/webhook  -n ${TEAM_NAME}-ci-cd))

echo "==> Log to https://${GIT_SERVER} and perform the manual steps 2). The argocd webhook url is ${ARGO_WEBHOOK}. Test the webhook Project hooks -> Test -> Push events."
read -p "Press [Enter] when done to continue..."


if [[ $(yq e '.applications[] | select(.name=="nexus") | length' /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml) < 1 ]]; then
    yq e '.applications += {"name": "nexus","enabled": true,"source": "https://redhat-cop.github.io/helm-charts","chart_name": "sonatype-nexus","source_ref": "1.1.10","values":{"includeRHRepositories": false,"service": {"name": "nexus"}}}' -i /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml
fi

cd /projects/tech-exercise
git add .
git commit -m  "ADD - nexus repo manager"
git push 

echo "==> Log to ${ARGO_URL} and verify that ubiquitous-journey app has deployed a nexus server. We patient, can take up to 5-10min."
read -p "Press [Enter] when done to continue..."

NEXUS_URL=$(echo https://$(oc get route nexus --template='{{ .spec.host }}' -n ${TEAM_NAME}-ci-cd))
echo export NEXUS_URL="${NEXUS_URL}" | tee -a ~/.bashrc -a ~/.zshrc
echo "==> Log to ${NEXUS_URL}. See credentials on step 4)"
read -p "Press [Enter] when done to continue..."

echo
echo "###########################################"
echo "### The Manual Menace -> This is GitOps ###"
echo "###########################################"
echo

cd /projects/tech-exercise
git remote set-url origin https://${GIT_SERVER}/${TEAM_NAME}/tech-exercise.git
git pull

echo "==> Log to ${OCP_CONSOLE} and perform the manual steps 1) and 2)."
read -p "Press [Enter] when done to continue..."

if [[ $(yq e '.applications.[].values.deployment.env_vars[] | select(.name=="BISCUITS") | length' /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml) < 1 ]]; then
    yq e '.applications.[1].values.deployment.env_vars += {"name": "BISCUITS", "value": "jaffa-cakes"}' -i /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml
fi

cd /projects/tech-exercise
git add .
git commit -m  "ADD - Jenkins environment variable"
git push 

echo "==> Log to https://${ARGO_URL} and verify that ubiquitous-journey jenkins deploy synced."
read -p "Press [Enter] when done to continue..."

echo "==> Log to ${OCP_CONSOLE} and verify that jenkins deploy has the new var BISCUITS."
read -p "Press [Enter] when done to continue..."

echo
echo "############################################"
echo "### The Manual Menace -> Here Be Dragons ###"
echo "############################################"
echo

echo "It is not expected to be executed during the course."
echo "It is just a summary of steps already done?."

echo
echo "#################################################"
echo "### Attack of the Pipelines -> Sealed Secrets ###"
echo "#################################################"
echo

cd /projects/tech-exercise
git remote set-url origin https://${GIT_SERVER}/${TEAM_NAME}/tech-exercise.git
git pull

echo "GITLAB_USER: ${GITLAB_USER}"
echo "GITLAB_PAT: ${GITLAB_PAT}"

cat << EOF > /tmp/git-auth.yaml
kind: Secret
apiVersion: v1
data:
  username: "$(echo -n ${GITLAB_USER} | base64 -w0)"
  password: "$(echo -n ${GITLAB_PAT} | base64 -w0)"
type: kubernetes.io/basic-auth
metadata:
  annotations:
    tekton.dev/git-0: https://${GIT_SERVER}
    sealedsecrets.bitnami.com/managed: "true"
  labels:
    credential.sync.jenkins.openshift.io: "true"
  name: git-auth
EOF

oc login --server=https://api.${CLUSTER_DOMAIN##apps.}:6443 -u ${USERNAME} -p ${PASSWORD}

kubeseal < /tmp/git-auth.yaml > /tmp/sealed-git-auth.yaml \
    -n ${TEAM_NAME}-ci-cd \
    --controller-namespace tl500-shared \
    --controller-name sealed-secrets \
    -o yaml

cat /tmp/sealed-git-auth.yaml 
cat /tmp/sealed-git-auth.yaml | grep -E 'username|password'

if [[ $(yq e '.applications[] | select(.name=="sealed-secrets") | length' /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml) < 1 ]]; then
    yq e '.applications += {"name": "sealed-secrets","enabled": true,"source": "https://redhat-cop.github.io/helm-charts","chart_name": "helper-sealed-secrets","source_ref": "1.0.3","values": {"secrets": [{"name": "git-auth","type": "kubernetes.io/basic-auth","annotations": {"tekton.dev/git-0": "https://GIT_SERVER","sealedsecrets.bitnami.com/managed": "true"},"labels": {"credential.sync.jenkins.openshift.io": "true"},"data": {"username": "SEALED_SECRET_USERNAME","password": "SEALED_SECRET_PASSWORD"}}]}}' -i /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml
    SEALED_SECRET_USERNAME=$(yq e '.spec.encryptedData.username' /tmp/sealed-git-auth.yaml)
    SEALED_SECRET_PASSWORD=$(yq e '.spec.encryptedData.password' /tmp/sealed-git-auth.yaml)
    sed -i "s|GIT_SERVER|$GIT_SERVER|" /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml
    sed -i "s|SEALED_SECRET_USERNAME|$SEALED_SECRET_USERNAME|" /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml
    sed -i "s|SEALED_SECRET_PASSWORD|$SEALED_SECRET_PASSWORD|" /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml
fi

echo "See # Sealed Secret section"
cat  /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml

cd /projects/tech-exercise
git add ubiquitous-journey/values-tooling.yaml
git commit -m "Sealed secret of Git user creds is added"
git push

echo "==> Log to https://${ARGO_URL} and verify SealedSecret chart. Drill into the SealedSecret and see the git-auth secret has synced."
read -p "Press [Enter] when done to continue..."

JENKINS_URL=$(echo https://$(oc get route jenkins --template='{{ .spec.host }}' -n ${TEAM_NAME}-ci-cd))
echo export JENKINS_URL="${JENKINS_URL}" | tee -a ~/.bashrc -a ~/.zshrc
echo "==> Log to ${JENKINS_URL}. Verify Jenkins synced Jenkins -> Manage Jenkins -> Manage Credentials to view <TEAM_NAME>-ci-cd-git-auth"
read -p "Press [Enter] when done to continue..."

echo
echo "##############################################################"
echo "### Attack of the Pipelines -> Application of Applications ###"
echo "##############################################################"
echo

echo "Deploying Pet Battle - Keycloak"

yq e '(.applications[] | (select(.name=="test-app-of-pb").enabled)) |=true' -i /projects/tech-exercise/values.yaml
yq e '(.applications[] | (select(.name=="staging-app-of-pb").enabled)) |=true' -i /projects/tech-exercise/values.yaml

if [[ $(yq e '.applications[] | select(.name=="keycloak") | length' /projects/tech-exercise/pet-battle/test/values.yaml) < 1 ]]; then
    yq e '.applications.keycloak = {"name": "keycloak","enabled": true,"source": "https://github.com/petbattle/pet-battle-infra","source_ref": "main","source_path": "keycloak","values": {"app_domain": "CLUSTER_DOMAIN"}}' -i /projects/tech-exercise/pet-battle/test/values.yaml
    sed -i "s|CLUSTER_DOMAIN|$CLUSTER_DOMAIN|" /projects/tech-exercise/pet-battle/test/values.yaml
fi

echo "See keycloak object"
cat /projects/tech-exercise/pet-battle/test/values.yaml
cat /projects/tech-exercise/pet-battle/test/values.yaml

cd /projects/tech-exercise
git add .
git commit -m  "ADD - app-of-apps and keycloak to test"
git push 

cd /projects/tech-exercise
helm upgrade --install uj --namespace ${TEAM_NAME}-ci-cd .

echo "==> Log to https://${ARGO_URL} and verify staging-app-of-pb and test-app-of-pb."
read -p "Press [Enter] when done to continue..."

echo "Deploying Pet Battle Test"

if [[ $(yq e '.applications[] | select(.name=="pet-battle-api") | length' /projects/tech-exercise/pet-battle/test/values.yaml) < 1 ]]; then
    yq e '.applications.pet-battle-api = {"name": "pet-battle-api","enabled": true,"source": "https://petbattle.github.io/helm-charts","chart_name": "pet-battle-api","source_ref": "1.2.1","values": {"image_name": "pet-battle-api","image_version": "latest", "hpa": {"enabled": false}}}' -i /projects/tech-exercise/pet-battle/test/values.yaml
fi
if [[ $(yq e '.applications[] | select(.name=="pet-battle") | length' /projects/tech-exercise/pet-battle/test/values.yaml) < 1 ]]; then
    yq e '.applications.pet-battle = {"name": "pet-battle","enabled": true,"source": "https://petbattle.github.io/helm-charts","chart_name": "pet-battle","source_ref": "1.0.6","values": {"image_version": "latest"}}' -i /projects/tech-exercise/pet-battle/test/values.yaml
fi
sed -i '/^$/d' /projects/tech-exercise/pet-battle/test/values.yaml
sed -i '/^# Keycloak/d' /projects/tech-exercise/pet-battle/test/values.yaml
sed -i '/^# Pet Battle Apps/d' /projects/tech-exercise/pet-battle/test/values.yaml

export JSON="'"'{
        "catsUrl": "https://pet-battle-api-'${TEAM_NAME}'-test.'${CLUSTER_DOMAIN}'",
        "tournamentsUrl": "https://pet-battle-tournament-'${TEAM_NAME}'-test.'${CLUSTER_DOMAIN}'",
        "matomoUrl": "https://matomo-'${TEAM_NAME}'-ci-cd.'${CLUSTER_DOMAIN}'/",
        "keycloak": {
          "url": "https://keycloak-'${TEAM_NAME}'-test.'${CLUSTER_DOMAIN}'/auth/",
          "realm": "pbrealm",
          "clientId": "pbclient",
          "redirectUri": "http://localhost:4200/tournament",
          "enableLogging": true
        }
      }'"'"
yq e '.applications.pet-battle.values.config_map = env(JSON) | .applications.pet-battle.values.config_map style="single"' -i /projects/tech-exercise/pet-battle/test/values.yaml

echo "pet-battle test definition"
cat /projects/tech-exercise/pet-battle/test/values.yaml

echo "Deploying Pet Battle Stage"
cp -f /projects/tech-exercise/pet-battle/test/values.yaml /projects/tech-exercise/pet-battle/stage/values.yaml
sed -i "s|${TEAM_NAME}-test|${TEAM_NAME}-stage|" /projects/tech-exercise/pet-battle/stage/values.yaml
sed -i 's|release: "test"|release: "stage"|' /projects/tech-exercise/pet-battle/stage/values.yaml

echo "pet-battle stage definition"
cat /projects/tech-exercise/pet-battle/stage/values.yaml

cd /projects/tech-exercise
git add .
git commit -m  "ADD - pet battle apps"
git push

echo "==> Log to https://${ARGO_URL} and verify Pet Battle apps for test and stage. Drill into one eg test-app-of-pb and see each of the three components of PetBattle"
read -p "Press [Enter] when done to continue..."

echo "==> Log to ${OCP_CONSOLE} Developer View -> Topology and select your <TEAM_NAME>-test|stage ns -> Route )"
read -p "Press [Enter] when done to continue..."

echo
echo "#################################################"
echo "### Attack of the Pipelines -> The Pipelines  ###"
echo "#################################################"
echo

cd /projects/tech-exercise
git remote set-url origin https://${GIT_SERVER}/${TEAM_NAME}/tech-exercise.git
git pull

echo
echo "Jenkins Group"
echo "--------------"
echo

echo "==> Log to https://${GIT_SERVER} and perform the manual steps 1). Create a Project in GitLab under <TEAM_NAME> group called pet-battle. Make the project as public."
read -p "Press [Enter] when done to continue..."

cd /projects
git clone https://github.com/rht-labs/pet-battle.git && cd pet-battle
git remote set-url origin https://${GIT_SERVER}/${TEAM_NAME}/pet-battle.git
git branch -M main
git push -u origin main

PET_JEN_TOKEN=$(echo "https://$(oc get route jenkins --template='{{ .spec.host }}' -n ${TEAM_NAME}-ci-cd)/multibranch-webhook-trigger/invoke?token=pet-battle")

echo "==> Log to https://${GIT_SERVER} . Add Pet Battle jenkins token ${PET_JEN_TOKEN} on pet-battle > Settings > Integrations."
read -p "Press [Enter] when done to continue..."

yq e '(.applications[] | (select(.name=="jenkins").values.deployment.env_vars[] | select(.name=="GITLAB_HOST")).value)|=env(GIT_SERVER)' -i /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml
yq e '(.applications[] | (select(.name=="jenkins").values.deployment.env_vars[] | select(.name=="GITLAB_GROUP_NAME")).value)|=env(TEAM_NAME)' -i /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml
yq e '.applications.pet-battle.source |="http://nexus:8081/repository/helm-charts"' -i /projects/tech-exercise/pet-battle/test/values.yaml

cd /projects/tech-exercise
git add .
git commit -m  "ADD - jenkins pipelines config"
git push

echo "==> Log to ${JENKINS_URL}. See the seed job has scaffolded out a pipeline for the frontend in the Jenkins UI. It’s done this by looking in the pet-battle repo where it found the Jenkinsfile (our pipeline definition). However it will fail on the first execution. This is expected as we’re going write some stuff to fix it! - If after Jenkins restarts you do not see the job run, feel free to manually trigger it to get it going"
read -p "Press [Enter] when done to continue..."

wget -O /projects/pet-battle/Jenkinsfile https://raw.githubusercontent.com/rht-labs/tech-exercise/main/tests/doc-regression-test-files/3a-jenkins-Jenkinsfile.groovy

cd /projects/pet-battle
git add Jenkinsfile
git commit -m "Jenkinsfile updated with build stage"
git push

echo "==> Log to ${JENKINS_URL}. See the  pet-battle pipeline is running successfully. Use the Blue Ocean view,"
read -p "Press [Enter] when done to continue..."

echo
echo "Tekton Group"
echo "------------"
echo

echo "==> Log to https://${GIT_SERVER} and perform the manual steps 1). Create a Project in GitLab under <TEAM_NAME> group called pet-battle-api. Make the project as internal."
read -p "Press [Enter] when done to continue..."

cd /projects
git clone https://github.com/rht-labs/pet-battle-api.git && cd pet-battle-api
git remote set-url origin https://${GIT_SERVER}/${TEAM_NAME}/pet-battle-api.git
git branch -M main
git push -u origin main

if [[ $(yq e '.applications[] | select(.name=="tekton-pipeline") | length' /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml) < 1 ]]; then
    yq e '.applications += {"name": "tekton-pipeline","enabled": true,"source": "https://GIT_SERVER/TEAM_NAME/tech-exercise.git","source_ref": "main","source_path": "tekton","values": {"team": "TEAM_NAME","cluster_domain": "CLUSTER_DOMAIN","git_server": "GIT_SERVER"}}' -i /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml
    sed -i "s|GIT_SERVER|$GIT_SERVER|" /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml
    sed -i "s|TEAM_NAME|$TEAM_NAME|" /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml    
    sed -i "s|CLUSTER_DOMAIN|$CLUSTER_DOMAIN|" /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml    
fi

yq e '.applications.pet-battle-api.source |="http://nexus:8081/repository/helm-charts"' -i /projects/tech-exercise/pet-battle/test/values.yaml

cd /projects/tech-exercise
git add .
git commit -m  "ADD - tekton pipelines config"
git push

echo "==> Log to https://${ARGO_URL} and verify ubiquitous-jorney app has a tekton-pipeline resource"
read -p "Press [Enter] when done to continue..." 

PET_API_TOKEN=$(echo https://$(oc -n ${TEAM_NAME}-ci-cd get route webhook --template='{{ .spec.host }}'))

echo "==> Log to https://${GIT_SERVER} . Add Pet Battle API token ${PET_API_TOKEN} on pet-battle-api > Settings > Integrations. Test the hook with Project Hooks -> Test -> Push events"
read -p "Press [Enter] when done to continue..."

cd /projects/pet-battle-api
mvn -ntp versions:set -DnewVersion=1.3.1

cd /projects/pet-battle-api
git add .
git commit -m  "UPDATED - pet-battle-version to 1.3.1"
git push 

echo "==> Log to ${OCP_CONSOLE} Observe Pipeline running -> Pipelines -> Pipelines in your <TEAM_NAME>-ci-cd project. Also, use the tkn command line to observe PipelineRun logs as well: 'tkn -n ${TEAM_NAME}-ci-cd pr logs -Lf'"
read -p "Press [Enter] when done to continue..."

echo
echo "##########################################################"
echo "### The Revenge of the Automated Testing -> Sonarqube  ###"
echo "##########################################################"
echo

cat << EOF > /tmp/sonarqube-auth.yaml
apiVersion: v1
data:
  username: "$(echo -n admin | base64 -w0)"
  password: "$(echo -n admin123 | base64 -w0)"
  currentAdminPassword: "$(echo -n admin | base64 -w0)"
kind: Secret
metadata:
  labels:
    credential.sync.jenkins.openshift.io: "true"
  name: sonarqube-auth
EOF

kubeseal < /tmp/sonarqube-auth.yaml > /tmp/sealed-sonarqube-auth.yaml \
    -n ${TEAM_NAME}-ci-cd \
    --controller-namespace tl500-shared \
    --controller-name sealed-secrets \
    -o yaml

cat /tmp/sealed-sonarqube-auth.yaml| grep -E 'username|password|currentAdminPassword'

echo "==> Perform step 3) in your IDE using the previous output ^^"
read -p "Press [Enter] when done to continue..."

cd /projects/tech-exercise
git add ubiquitous-journey/values-tooling.yaml
git commit -m  "ADD - sonarqube creds sealed secret"
git push

sleep 30; oc get secrets -n <TEAM_NAME>-ci-cd | grep sonarqube-auth

echo "==> Perform step 5) in your IDE using the previous output ^^"
read -p "Press [Enter] when done to continue..."

cd /projects/tech-exercise
git add .
git commit -m  "ADD - sonarqube"
git push

echo "==> Log to https://${ARGO_URL} and verify that sonarqube is deployed."
read -p "Press [Enter] when done to continue..." 

SONAR_URL=$(echo https://$(oc get route sonarqube --template='{{ .spec.host }}' -n ${TEAM_NAME}-ci-cd))
echo export SONAR_URL="${SONAR_URL}" | tee -a ~/.bashrc -a ~/.zshrc

echo "==> Log to https://${SONAR_URL} and verify installation is successful (admin/admin123)."
read -p "Press [Enter] when done to continue..."
