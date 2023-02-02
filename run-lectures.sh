#!/bin/bash

#
# Lecture https://rht-labs.com/tech-exercise/#
#

# Help function
help() {
  echo -e "Usage: $0 -u=<USERNAME> -p=<PASSWORD> -t=<TEAM_NAME>"
  echo -e "Example: $0 -u=lab01 -p=lab01 -t=01team"
  exit 1
}

# Parse and check input
for i in "$@"; do
  case $i in
    -u=*)
      USERNAME="${i#*=}"
      shift
      ;;
    -p=*)
      PASSWORD="${i#*=}"
      shift
      ;;
    -t=*)
      TEAM_NAME="${i#*=}"
      shift
      ;;
    *)
      help
      ;;
  esac
done

# Check vars
if [ -z ${USERNAME} ] || [ -z ${PASSWORD} ] || [ -z ${TEAM_NAME} ]
then
  help
fi

#
# Configuration
#
CLUSTER_DOMAIN=apps.ocp4.example.com
GIT_SERVER=gitlab-ce.apps.ocp4.example.com
OCP_CONSOLE=https://console-openshift-console.apps.ocp4.example.com

#
# Patches
#
ARGO_PATCH="--version 0.4.9"
KEYCLOACK_PATCH="labs1.0.1"

if [ "$1" == "--reset" ]
then
  helm uninstall my tl500/todolist --namespace ${TEAM_NAME}-ci-cd
  helm uninstall argocd --namespace ${TEAM_NAME}-ci-cd
  helm uninstall uj --namespace ${TEAM_NAME}-ci-cd
  oc delete all --all -n ${TEAM_NAME}-ci-cd
  oc delete all --all -n ${TEAM_NAME}-test
  oc delete all --all -n ${TEAM_NAME}-stage
  oc delete all --all -n ${TEAM_NAME}-dev
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
# Helm
#
echo "Running helm"
helm repo add tl500 https://rht-labs.com/todolist
helm search repo todolist
helm install my tl500/todolist --namespace ${TEAM_NAME}-ci-cd || true
echo https://$(oc get route/my-todolist -n ${TEAM_NAME}-ci-cd --template='{{.spec.host}}')
sleep 180
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
  redhat-cop/gitops-operator ${ARGO_PATCH}

sleep 60
oc get pods -n ${TEAM_NAME}-ci-cd
ARGO_URL=$( echo https://$(oc get route argocd-server --template='{{ .spec.host }}' -n ${TEAM_NAME}-ci-cd ))
echo export ARGO_URL="${ARGO_URL}" | tee -a ~/.bashrc -a ~/.zshrc

echo "==> Log to ${ARGO_URL} and perform manual steps 6), 7), 8), 9) and 10) [Repository URL: https://rht-labs.com/todolist]"
read -p "Press [Enter] when done to continue..."

echo https://$(oc get route/our-todolist -n ${TEAM_NAME}-ci-cd --template='{{.spec.host}}')

echo
echo "###############################################"
echo "### The Manual Menace -> Ubiquitous Journey ###"
echo "###############################################"
echo

echo "==> Log to https://${GIT_SERVER} and perform the manual steps 1), 2), 3), 4) and 5) [${TEAM_NAME},public tech-exercise,internal]"
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

echo "==> Log to https://${GIT_SERVER} and perform the manual steps 2). The argocd webhook url is ${ARGO_WEBHOOK} . Test the webhook Project hooks -> Test -> Push events."
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
echo "==> Log to ${NEXUS_URL} See credentials on step 4)"
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

echo "==> Log to ${ARGO_URL} and verify that ubiquitous-journey jenkins deploy synced."
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
oc login --server=https://api.${CLUSTER_DOMAIN##apps.}:6443 -u ${USERNAME} -p ${PASSWORD} >/dev/null 2>&1

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

echo "==> Log to ${ARGO_URL} and verify SealedSecret chart. Drill into the SealedSecret and see the git-auth secret has synced."
read -p "Press [Enter] when done to continue..."

JENKINS_URL=$(echo https://$(oc get route jenkins --template='{{ .spec.host }}' -n ${TEAM_NAME}-ci-cd))
echo export JENKINS_URL="${JENKINS_URL}" | tee -a ~/.bashrc -a ~/.zshrc
echo "==> Log to ${JENKINS_URL} Verify Jenkins synced Jenkins -> Manage Jenkins -> Manage Credentials to view ${TEAM_NAME}-ci-cd-git-auth"
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
    yq e '.applications.keycloak = {"name": "keycloak","enabled": true,"source": "https://github.com/petbattle/pet-battle-infra","source_ref": "BRANCH_ID","source_path": "keycloak","values": {"app_domain": "CLUSTER_DOMAIN"}}' -i /projects/tech-exercise/pet-battle/test/values.yaml
    sed -i "s|CLUSTER_DOMAIN|${CLUSTER_DOMAIN}|" /projects/tech-exercise/pet-battle/test/values.yaml
    sed -i "s|BRANCH_ID|${KEYCLOACK_PATCH}|" /projects/tech-exercise/pet-battle/test/values.yaml
fi

echo "See keycloak object"
cat /projects/tech-exercise/pet-battle/test/values.yaml
sleep 180

cd /projects/tech-exercise
git add .
git commit -m  "ADD - app-of-apps and keycloak to test"
git push 

cd /projects/tech-exercise
helm upgrade --install uj --namespace ${TEAM_NAME}-ci-cd .

echo "==> Log to ${ARGO_URL} and verify staging-app-of-pb and test-app-of-pb."
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

echo "==> Log to ${ARGO_URL} and verify Pet Battle apps for test and stage. Drill into one eg test-app-of-pb and see each of the three components of PetBattle"
read -p "Press [Enter] when done to continue..."

echo "==> Log to ${OCP_CONSOLE} Developer View -> Topology and select your ${TEAM_NAME}-test|stage ns -> Route )"
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
echo "###########################################################"
echo "### Attack of the Pipelines -> The Pipelines - Jenkins  ###"
echo "###########################################################"
echo

echo "==> Log to https://${GIT_SERVER} and perform the manual steps 1). Create a Project in GitLab under ${TEAM_NAME} group called pet-battle. Make the project as public."
read -p "Press [Enter] when done to continue..."

cd /projects
git clone https://github.com/rht-labs/pet-battle.git && cd pet-battle
git remote set-url origin https://${GIT_SERVER}/${TEAM_NAME}/pet-battle.git
git branch -M main
git push -u origin main

PET_JEN_TOKEN=$(echo "https://$(oc get route jenkins --template='{{ .spec.host }}' -n ${TEAM_NAME}-ci-cd)/multibranch-webhook-trigger/invoke?token=pet-battle")

echo "==> Log to https://${GIT_SERVER} Add Pet Battle jenkins token ${PET_JEN_TOKEN} on pet-battle > Settings > Integrations."
read -p "Press [Enter] when done to continue..."

yq e '(.applications[] | (select(.name=="jenkins").values.deployment.env_vars[] | select(.name=="GITLAB_HOST")).value)|=env(GIT_SERVER)' -i /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml
yq e '(.applications[] | (select(.name=="jenkins").values.deployment.env_vars[] | select(.name=="GITLAB_GROUP_NAME")).value)|=env(TEAM_NAME)' -i /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml
yq e '.applications.pet-battle.source |="http://nexus:8081/repository/helm-charts"' -i /projects/tech-exercise/pet-battle/test/values.yaml

cd /projects/tech-exercise
git add .
git commit -m  "ADD - jenkins pipelines config"
git push
sleep 90

echo "==> Log to ${JENKINS_URL} See the seed job has scaffolded out a pipeline for the frontend in the Jenkins UI. It’s done this by looking in the pet-battle repo where it found the Jenkinsfile (our pipeline definition). However it will fail on the first execution. This is expected as we’re going write some stuff to fix it! - If after Jenkins restarts you do not see the job run, feel free to manually trigger it to get it going"
read -p "Press [Enter] when done to continue..."

#PROD
wget -O /projects/pet-battle/Jenkinsfile https://raw.githubusercontent.com/rht-labs/tech-exercise/main/tests/doc-regression-test-files/3a-jenkins-Jenkinsfile.groovy

cd /projects/pet-battle
git add Jenkinsfile
git commit -m "Jenkinsfile updated with build stage"
git push

echo "==> Log to ${JENKINS_URL} See the  pet-battle pipeline is running successfully. Use the Blue Ocean view,"
read -p "Press [Enter] when done to continue..."

echo
echo "##########################################################"
echo "### Attack of the Pipelines -> The Pipelines - Tekton  ###"
echo "##########################################################"
echo

echo "==> Log to https://${GIT_SERVER} and perform the manual steps 1). Create a Project in GitLab under ${TEAM_NAME} group called pet-battle-api. Make the project as internal."
read -p "Press [Enter] when done to continue..."

### TODO: This must be documented on the lectures
cd /projects/tech-exercise
git remote set-url origin https://${GIT_SERVER}/${TEAM_NAME}/tech-exercise.git
git pull
###

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

sleep 60
echo "==> Log to ${ARGO_URL} and verify ubiquitous-jorney app has a tekton-pipeline resource"
read -p "Press [Enter] when done to continue..." 

PET_API_TOKEN=$(echo https://$(oc -n ${TEAM_NAME}-ci-cd get route webhook --template='{{ .spec.host }}'))

echo "==> Log to https://${GIT_SERVER} Add Pet Battle API token ${PET_API_TOKEN} on pet-battle-api > Settings > Integrations. Test the hook with Project Hooks -> Test -> Push events"
read -p "Press [Enter] when done to continue..."

cd /projects/pet-battle-api
mvn -ntp versions:set -DnewVersion=1.3.1
sleep 100

cd /projects/pet-battle-api
git add .
git commit -m  "UPDATED - pet-battle-version to 1.3.1"
git push 

sleep 60
echo "==> Log to ${OCP_CONSOLE} Observe Pipeline running -> Pipelines -> Pipelines in your ${TEAM_NAME}-ci-cd project. Also, use the tkn command line to observe PipelineRun logs as well: 'tkn -n ${TEAM_NAME}-ci-cd pr logs -Lf'"
read -p "Press [Enter] when done to continue..."

echo
echo "##########################################################"
echo "### The Revenge of the Automated Testing -> Sonarqube  ###"
echo "##########################################################"
echo
oc login --server=https://api.${CLUSTER_DOMAIN##apps.}:6443 -u ${USERNAME} -p ${PASSWORD} >/dev/null 2>&1

cd /projects/tech-exercise
git remote set-url origin https://${GIT_SERVER}/${TEAM_NAME}/tech-exercise.git
git pull

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

echo "==> Perform step 3) in your IDE using the previous output ^^ /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml"
read -p "Press [Enter] when done to continue..."

cd /projects/tech-exercise
git add ubiquitous-journey/values-tooling.yaml
git commit -m  "ADD - sonarqube creds sealed secret"
git push

sleep 30; oc get secrets -n ${TEAM_NAME}-ci-cd | grep sonarqube-auth

echo "==> Perform step 5) in your IDE /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml"
read -p "Press [Enter] when done to continue..."

cd /projects/tech-exercise
git add .
git commit -m  "ADD - sonarqube"
git push

echo "==> Log to ${ARGO_URL} and verify that sonarqube is deployed."
read -p "Press [Enter] when done to continue..." 

SONAR_URL=$(echo https://$(oc get route sonarqube --template='{{ .spec.host }}' -n ${TEAM_NAME}-ci-cd))
echo export SONAR_URL="${SONAR_URL}" | tee -a ~/.bashrc -a ~/.zshrc

echo "==> Log to ${SONAR_URL} and verify installation is successful (admin/admin123)."
read -p "Press [Enter] when done to continue..."

echo
echo "#####################################################################"
echo "### The Revenge of the Automated Testing -> Sonarqube -> Jenkins  ###"
echo "#####################################################################"
echo

cd /projects/pet-battle
cat << EOF > sonar-project.js
const scanner = require('sonarqube-scanner');

scanner(
  {
    serverUrl: 'http://sonarqube-sonarqube:9000',
    options: {
      'sonar.login': process.env.SONARQUBE_USERNAME,
      'sonar.password': process.env.SONARQUBE_PASSWORD,
      'sonar.projectName': 'Pet Battle',
      'sonar.projectDescription': 'Pet Battle UI',
      'sonar.sources': 'src',
      'sonar.tests': 'src',
      'sonar.inclusions': '**', // Entry point of your code
      'sonar.test.inclusions': 'src/**/*.spec.js,src/**/*.spec.ts,src/**/*.spec.jsx,src/**/*.test.js,src/**/*.test.jsx',
      'sonar.exclusions': '**/node_modules/**',
      //'sonar.test.exclusions': 'src/app/core/*.spec.ts',
      // 'sonar.javascript.lcov.reportPaths': 'reports/lcov.info',
      // 'sonar.testExecutionReportPaths': 'coverage/test-reporter.xml'
    }
  },
  () => process.exit()
);
EOF

echo "==> Perform step 2) SONARQUBE_CREDS and 3) in your IDE using /projects/pet-battle/Jenkinsfile"
read -p "Press [Enter] when done to continue..."

cd /projects/pet-battle
git add Jenkinsfile sonar-project.js
git commit -m "test code-analysis step"
git push

echo "==> Observe the pet-battle Jenkins Pipeline at ${JENKINS_URL} and when scanning is completed, browse the ${SONAR_URL} to see Pet Battle project created"
read -p "Press [Enter] when done to continue..."

echo
echo "#####################################################################"
echo "### The Revenge of the Automated Testing -> Sonarqube -> Tekton   ###"
echo "#####################################################################"
echo

echo "==> Perform step 1) Add code-analysis step to our Pipeline. Edit /projects/tech-exercise/tekton/templates/pipelines/maven-pipeline.yaml file, add this step before the maven build step."
read -p "Press [Enter] when done to continue..."

echo "==> Perform step 2) Edit /projects/tech-exercise/tekton/templates/triggers/gitlab-trigger-template.yaml file, add this code to the end of the workspaces list where the # sonarqube-auth placeholder is."
read -p "Press [Enter] when done to continue..."

cd /projects/tech-exercise
cat <<'EOF' >> tekton/templates/tasks/sonarqube-quality-gate-check.yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: sonarqube-quality-gate-check
spec:
  description: >-
    This Task can be used to check sonarqube quality gate
  workspaces:
    - name: output
    - name: sonarqube-auth
      optional: true
  params:
    - name: WORK_DIRECTORY
      description: Directory to start build in (handle multiple branches)
      type: string
    - name: IMAGE
      description: the image to use
      type: string
      default: "quay.io/eformat/openshift-helm:latest"
  steps:
  - name: check
    image: $(params.IMAGE)
    script: |
      #!/bin/sh
      test -f $(workspaces.sonarqube-auth.path) || export SONAR_USER="$(cat $(workspaces.sonarqube-auth.path)/username):$(cat $(workspaces.sonarqube-auth.path)/password)"
  
      cd $(workspaces.output.path)/$(params.WORK_DIRECTORY)
      TASKFILE=$(find . -type f -name report-task.txt)
      if [ -z ${TASKFILE} ]; then
        echo "Task File not found"
        exit 1
      fi
      echo ${TASKFILE}

      TASKURL=$(cat ${TASKFILE} | grep ceTaskUrl)
      TURL=${TASKURL##ceTaskUrl=}
      if [ -z ${TURL} ]; then
        echo "Task URL not found"
        exit 1
      fi
      echo ${TURL}

      AID=$(curl -u ${SONAR_USER} -s $TURL | jq -r .task.analysisId)
      if [ -z ${AID} ]; then
        echo "Analysis ID not found"
        exit 1
      fi
      echo ${AID}

      SERVERURL=$(cat ${TASKFILE} | grep serverUrl)
      SURL=${SERVERURL##serverUrl=}
      if [ -z ${SURL} ]; then
        echo "Server URL not found"
        exit 1
      fi
      echo ${SURL}

      BUILDSTATUS=$(curl -u ${SONAR_USER} -s $SURL/api/qualitygates/project_status?analysisId=${AID} | jq -r .projectStatus.status)
      if [ "${BUILDSTATUS}" != "OK" ]; then
        echo "Failed Quality Gate - please check - $SURL/api/qualitygates/project_status?analysisId=${AID}"
        exit 1
      fi

      echo "Quality Gate Passed OK - $SURL/api/qualitygates/project_status?analysisId=${AID}"
      exit 0
EOF

echo "==> Perform step 4) Edit /projects/tech-exercise/tekton/templates/pipelines/maven-pipeline.yaml file and add the code-analysis-check step to our pipeline as shown below."
read -p "Press [Enter] when done to continue..."

echo "==> Perform step 5) Edit /projects/tech-exercise/tekton/templates/pipelines/maven-pipeline.yaml file to adjust the maven build step’s runAfter to be analysis-check so the static analysis steps happen before we even compile the app."
read -p "Press [Enter] when done to continue..."

cd /projects/tech-exercise
git add .
git commit -m  "ADD - code-analysis & check steps"
git push

sleep 30
cd /projects/pet-battle-api
git commit --allow-empty -m "TEST - running code analysis steps"
git push

echo "==> Log to ${OCP_CONSOLE} Observe Pipeline running -> Pipelines -> Pipelines in your ${TEAM_NAME}-ci-cd project. Wait until it finish. [Refresh web browser ...]'"
read -p "Press [Enter] when done to continue..."

echo "==> Log to ${SONAR_URL} and verify and inspect the results in Sonarqube UI - pet-battle-api."
read -p "Press [Enter] when done to continue..."

echo
echo "###################################################################"
echo "### The Revenge of the Automated Testing -> Testing -> Jenkins  ###"
echo "###################################################################"
echo

echo "==> Perform step 2) Edit /projects/pet-battle/Jenkinsfile file to extend the pipeline where //Jest Testing placeholder is."
read -p "Press [Enter] when done to continue..."

echo "==> Perform step 3) Edit /projects/pet-battle/Jenkinsfile file to add these post steps to the pipeline by the //Post steps go here placeholder."
read -p "Press [Enter] when done to continue..."

cd /projects/pet-battle
git add .
git commit -m "ADD - save test results"
git push

echo "==> Log to ${JENKINS_URL} Run twice pet-battle -> main job and see the test resunts under 'Web Code Coverage'"
read -p "Press [Enter] when done to continue..."

echo
echo "##################################################################"
echo "### The Revenge of the Automated Testing -> Testing -> Tekton  ###"
echo "##################################################################"
echo

cat << EOF > /tmp/allure-auth.yaml
apiVersion: v1
data:
  password: "$(echo -n password | base64 -w0)"
  username: "$(echo -n admin | base64 -w0)"
kind: Secret
metadata:
  name: allure-auth
EOF

kubeseal < /tmp/allure-auth.yaml > /tmp/sealed-allure-auth.yaml \
    -n ${TEAM_NAME}-ci-cd \
    --controller-namespace tl500-shared \
    --controller-name sealed-secrets \
    -o yaml

cat /tmp/sealed-allure-auth.yaml| grep -E 'username|password'

echo "==> Perform step 4), 5) in your IDE using the previous output ^^ /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml"
read -p "Press [Enter] when done to continue..."

cd /projects/tech-exercise
git add ubiquitous-journey/values-tooling.yaml
git commit -m  "ADD - Allure tooling"
git push

sleep 60
ALURE_URL=$(echo https://$(oc get route allure --template='{{ .spec.host }}' -n ${TEAM_NAME}-ci-cd)/allure-docker-service/projects/default/reports/latest/index.html)

echo "==> Log to ${ALURE_URL} and verify installation is successful (admin/password)."
read -p "Press [Enter] when done to continue..."

cd /projects/tech-exercise
cat <<'EOF' > tekton/templates/tasks/allure-post-report.yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: allure-post-report
  labels:
    app.kubernetes.io/version: "0.2"
spec:
  description: >-
    This task used for uploading test reports to allure
  workspaces:
    - name: output
  params:
    - name: APPLICATION_NAME
      type: string
      default: ""
    - name: IMAGE
      description: the image to use to upload results
      type: string
      default: "quay.io/openshift/origin-cli:4.9"
    - name: WORK_DIRECTORY
      description: Directory to start build in (handle multiple branches)
      type: string
    - name: ALLURE_HOST
      description: "Allure Host"
      default: "http://allure:5050"
    - name: ALLURE_SECRET
      type: string
      description: Secret containing Allure credentials
      default: allure-auth
  steps:
    - name: save-tests
      image: $(params.IMAGE)
      workingDir: $(workspaces.output.path)/$(params.WORK_DIRECTORY)
      env:
        - name: ALLURE_USERNAME
          valueFrom:
            secretKeyRef:
              name: $(params.ALLURE_SECRET)
              key: username
        - name: ALLURE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: $(params.ALLURE_SECRET)
              key: password
      script: |
        #!/bin/bash
        curl -sLo send_results.sh https://raw.githubusercontent.com/eformat/allure/main/scripts/send_results.sh && chmod 755 send_results.sh
        ./send_results.sh $(params.APPLICATION_NAME) \
          $(workspaces.output.path)/$(params.WORK_DIRECTORY) \
          ${ALLURE_USERNAME} \
          ${ALLURE_PASSWORD} \
          $(params.ALLURE_HOST)
EOF

echo "==> Perform step 2) Edit /projects/tech-exercise/tekton/templates/pipelines/maven-pipeline.yaml file and add the save-test-results step to the pipeline."
read -p "Press [Enter] when done to continue..."

cd /projects/tech-exercise
git add .
git commit -m  "ADD - save-test-results step"
git push

sleep 30
cd /projects/pet-battle-api
git commit --allow-empty -m "test save-test-results step"
git push

ALURE_PETURL=$(echo https://$(oc get route allure --template='{{ .spec.host }}' -n ${TEAM_NAME}-ci-cd)/allure-docker-service/projects/pet-battle-api/reports/latest/index.html)
echo "==> Log to ${OCP_CONSOLE} Observe Pipeline running -> Pipelines -> Pipelines in your ${TEAM_NAME}-ci-cd project -> pet-battle-api-xxx -> Details [Rerun pipeline if save-test-result step is not there ...]'"
read -p "Press [Enter] when done to continue..."

echo "==> Log to ${ALURE_PETURL} to browse to the uploaded test results from the pipeline in Allure. Test results + behaviours."
read -p "Press [Enter] when done to continue..."

echo
echo "########################################################################"
echo "### The Revenge of the Automated Testing -> Code Linting -> Jenkins  ###"
echo "########################################################################"
echo
oc login --server=https://api.${CLUSTER_DOMAIN##apps.}:6443 -u ${USERNAME} -p ${PASSWORD} >/dev/null 2>&1

echo "==> Perform step 4) Edit /projects/pet-battle/Jenkinsfile file to extend extend the stage{ "Build" } of the Jenkinsfile with the lint task. //Lint exercise here."
read -p "Press [Enter] when done to continue..."

### TODO: change document to include it
cd /projects/pet-battle
###
git add .
git commit -m "ADD - linting to the pipeline"
git push

echo "==> Log to ${JENKINS_URL} See new build triggered and the linter running as part of it."
read -p "Press [Enter] when done to continue..."

echo
echo "#######################################################################"
echo "### The Revenge of the Automated Testing -> Code Linting -> Tekton  ###"
echo "#######################################################################"
echo

echo "==> Log to ${OCP_CONSOLE} Observe Pipeline running -> Pipelines -> Pipelines in your ${TEAM_NAME}-ci-cd project -> pet-battle-api-xxx. The Code Linting is done at the 'mvn' step'."
read -p "Press [Enter] when done to continue..."

echo
echo "########################################################################"
echo "### The Revenge of the Automated Testing -> Kube Linting -> Jenkins  ###"
echo "########################################################################"
echo

echo "==> Perform step 1) Edit /projects/pet-battle/Jenkinsfile file to add the code snippet stage("Deploy - Helm Package"). //Kube-linter step."
read -p "Press [Enter] when done to continue..."

cd /projects/pet-battle
git add Jenkinsfile
git commit -m  "ADD - kube-linter step"
git push

echo "==> Log to ${JENKINS_URL} See new build triggered and the kube linter running as part of it. See 'Error: found 1 lint errors'. Lets fix it."
read -p "Press [Enter] when done to continue..."

echo "==> Perform step 3) Edit /projects/pet-battle/chart/templates/deploymentconfig.yaml to fix ^^ previous error. Also bump Chart.yaml"
read -p "Press [Enter] when done to continue..."

cd /projects/pet-battle
kube-linter lint chart --do-not-auto-add-defaults --include no-extensions-v1beta,no-readiness-probe,no-liveness-probe,dangling-service,mismatching-selector,writable-host-mount

cd /projects/pet-battle
git add .
git commit -m  "ADD - Liveliness probe"
git push

echo "==> Log to ${JENKINS_URL} See new build triggered and the kube linter running as part of it. The prevous error has gone."
read -p "Press [Enter] when done to continue..."

echo
echo "#######################################################################"
echo "### The Revenge of the Automated Testing -> Kube Linting -> Tekton  ###"
echo "#######################################################################"
echo
oc login --server=https://api.${CLUSTER_DOMAIN##apps.}:6443 -u ${USERNAME} -p ${PASSWORD} >/dev/null 2>&1

### TODO: This must be documented on the lectures 
cd /projects/tech-exercise
git remote set-url origin https://${GIT_SERVER}/${TEAM_NAME}/tech-exercise.git
git pull
###

curl -sLo /projects/tech-exercise/tekton/templates/tasks/kube-linter.yaml \
https://raw.githubusercontent.com/tektoncd/catalog/main/task/kube-linter/0.1/kube-linter.yaml

cd /projects/tech-exercise
git add .
git commit -m  " ADD - kube-linter task"
git push

echo "==> Perform step 2) Edit /projects/tech-exercise/tekton/templates/pipelines/maven-pipeline.yaml file to add kube-linter task. Modify mvn step to run after kube-linter"
read -p "Press [Enter] when done to continue..."

cd /projects/tech-exercise
git add .
git commit -m  "ADD - kube-linter checks"
git push

sleep 30
cd /projects/pet-battle-api
git commit --allow-empty -m "test kube-linter step"
git push

echo "==> Log to ${OCP_CONSOLE} Observe Pipeline running -> Pipelines -> Pipelines in your ${TEAM_NAME}-ci-cd project -> pet-battle-api-xxx -> Details. See the kube-linter step'. [Rerun pipeline if needed]."
read -p "Press [Enter] when done to continue..."


echo "==> Perform step Breaking the Build 1) Edit /projects/tech-exercise/tekton/templates/pipelines/maven-pipeline.yaml file to add required-label-owner to the includelist list on the kube-linter task."
read -p "Press [Enter] when done to continue..."

cd /projects/tech-exercise
git add .
git commit -m  "ADD - kube-linter required-label-owner check"
git push

sleep 30
cd /projects/pet-battle-api
git commit --allow-empty -m "test required-label-owner check"
git push

echo "==> Log to ${OCP_CONSOLE} Observe Pipeline running -> Pipelines -> Pipelines in your ${TEAM_NAME}-ci-cd project -> pet-battle-api-xxx -> Details. 'Wait for the pipeline to sync and trigger a pet-battle-api build. This should now fail."
read -p "Press [Enter] when done to continue..."

cd /projects/pet-battle-api
kube-linter lint chart --do-not-auto-add-defaults --include no-extensions-v1beta,no-readiness-probe,no-liveness-probe,dangling-service,mismatching-selector,writable-host-mount,required-label-owner

echo "==> Perform step Breaking the Build 5), and 6) to fix the previous issue ^^."
read -p "Press [Enter] when done to continue..."

cd /projects/pet-battle-api
mvn -ntp versions:set -DnewVersion=1.3.1

cd /projects/pet-battle-api
git add .
git commit -m  "ADD - kube-linter owner labels"
git push

echo "==> Log to ${OCP_CONSOLE} Observe Pipeline running -> Pipelines -> Pipelines in your ${TEAM_NAME}-ci-cd project -> pet-battle-api-xxx -> Details. This should now NOT fail."
read -p "Press [Enter] when done to continue..."

echo
echo "############################################################################################"
echo "### The Revenge of the Automated Testing -> OWASP ZAP Vulnerability Scanning -> Jenkins  ###"
echo "############################################################################################"
echo

echo "==> Perform step 1) Edit /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml to add jenkins-agent-zap."
read -p "Press [Enter] when done to continue..."

cd /projects/tech-exercise
git add ubiquitous-journey/values-tooling.yaml
git commit -m  "ADD - Zap Jenkins Agent"
git push

echo "==> Perform step 2) Edit /projects/pet-battle/Jenkinsfile to add ZAP scanning step below stage where //OWASP ZAP STAGE GOES HERE."
read -p "Press [Enter] when done to continue..."

cd /projects/pet-battle
git add Jenkinsfile
git commit -m  "ADD - OWASP ZAP scanning"
git push

echo "==> Log to ${JENKINS_URL} On the left hand side, see 'OWASP Zed Attack Proxy' for test results."
read -p "Press [Enter] when done to continue..."

echo
echo "###########################################################################################"
echo "### The Revenge of the Automated Testing -> OWASP ZAP Vulnerability Scanning -> Tekton  ###"
echo "###########################################################################################"
echo

cd /projects/tech-exercise
cat <<'EOF' > tekton/templates/tasks/zap-proxy.yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: zap-proxy
spec:
  workspaces:
    - name: output
  params:
    - name: APPLICATION_NAME
      type: string
      default: "zap-scan"
    - name: APP_URL
      description: The application under test url
    - name: ALLURE_HOST
      type: string
      description: "Allure Host"
      default: "http://allure:5050"
    - name: ALLURE_SECRET
      type: string
      description: Secret containing Allure credentials
      default: allure-auth
    - name: WORK_DIRECTORY
      description: Directory to start build in (handle multiple branches)
  steps:
    - name: zap-proxy
      image: quay.io/rht-labs/zap2docker-stable:latest
      env:
        - name: PIPELINERUN_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.labels['tekton.dev/pipelineRun']
        - name: ALLURE_USERNAME
          valueFrom:
            secretKeyRef:
              name: $(params.ALLURE_SECRET)
              key: username
        - name: ALLURE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: $(params.ALLURE_SECRET)
              key: password
      workingDir: $(workspaces.output.path)/$(params.WORK_DIRECTORY)
      script: |
        #!/usr/bin/env bash
        set -x
        echo "Make the wrk directory available to save the reports"
        cd /zap
        mkdir -p /zap/wrk
        echo "🪰🪰🪰 Starting the pen test..."
        /zap/zap-baseline.py -t $(params.APP_URL) -r $PIPELINERUN_NAME.html
        ls -lart /zap/wrk
        echo "🛸🛸🛸 Saving results..."
        # FIXME for now this works, move to script+image
        pip install pytest allure-pytest --user
        cat > test.py <<EOF
        import allure
        import glob
        import os
        def test_zap_scan_results():
            for file in list(glob.glob('/zap/wrk/*.html')):
                allure.attach.file(file, attachment_type=allure.attachment_type.HTML)
            pass
        EOF
        export PATH=$HOME/.local/bin:$PATH
        pytest test.py --alluredir=/zap/wrk/allure-results
        curl -sLo send_results.sh https://raw.githubusercontent.com/eformat/allure/main/scripts/send_results.sh && chmod 755 send_results.sh
        ./send_results.sh $(params.APPLICATION_NAME) \
        /zap \
        ${ALLURE_USERNAME} \
        ${ALLURE_PASSWORD} \
        $(params.ALLURE_HOST) \
        wrk/allure-results
EOF

echo "==> Perform step 2) Edit /projects/tech-exercise/tekton/templates/pipeline/maven-pipeline.yaml to add pentesting-test step."
read -p "Press [Enter] when done to continue..."

cd /projects/tech-exercise
git add .
git commit -m  "ADD - zap scan pentest"
git push

sleep 30
cd /projects/pet-battle-api
git commit --allow-empty -m "test zap-scan step"
git push


ZAP_URL=$(echo https://allure-${TEAM_NAME}-ci-cd.${CLUSTER_DOMAIN}/allure-docker-service/projects/zap-scan/reports/latest/index.html)
echo "==> Log to ${ZAP_URL} and see Suites -> ZAP Scan Report."
read -p "Press [Enter] when done to continue..."

echo
echo "################################################################################"
echo "### The Revenge of the Automated Testing -> Image Security -> StackRox (ACS) ###"
echo "################################################################################"
echo

ROX_URL=$(echo https://$(oc -n stackrox get route central --template='{{ .spec.host }}'))
ROX_PSS=$(echo $(oc -n stackrox get secret central-htpasswd -o go-template='{{index .data "password" | base64decode}}'))

echo "==> Log to ${ROX_URL} Use admin/${ROX_PSS} ."
read -p "Press [Enter] when done to continue..."

export ROX_API_TOKEN=$(oc -n stackrox get secret rox-api-token-tl500 -o go-template='{{index .data "token" | base64decode}}')
echo export ROX_API_TOKEN="${ROX_API_TOKEN}" | tee -a ~/.bashrc -a ~/.zshrc

export ROX_ENDPOINT=central-stackrox.${CLUSTER_DOMAIN}
echo export ROX_ENDPOINT="${ROX_ENDPOINT}" | tee -a ~/.bashrc -a ~/.zshrc

roxctl central whoami --insecure-skip-tls-verify -e $ROX_ENDPOINT:443

cat << EOF > /tmp/rox-auth.yaml
apiVersion: v1
data:
  password: "$(echo -n ${ROX_API_TOKEN} | base64 -w0)"
  username: "$(echo -n ${ROX_ENDPOINT} | base64 -w0)"
kind: Secret
metadata:
  labels:
    credential.sync.jenkins.openshift.io: "true"
  name: rox-auth
EOF

kubeseal < /tmp/rox-auth.yaml > /tmp/sealed-rox-auth.yaml \
    -n ${TEAM_NAME}-ci-cd \
    --controller-namespace tl500-shared \
    --controller-name sealed-secrets \
    -o yaml

cat /tmp/sealed-rox-auth.yaml | grep -E 'username|password'

echo "==> Perform step 4) Edit /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml to add Sealed Secrets entry. Copy the output of username and password from the previous command and update the values."
read -p "Press [Enter] when done to continue..."

cd /projects/tech-exercise
git add .
git commit -m  "ADD - stackrox sealed secret"
git push

echo "==> Log to ${ROX_URL} Use admin/${ROX_PSS} . Perform 5), 6), 7), 8), 9), and 10)"
read -p "Press [Enter] when done to continue..."

echo
echo "##########################################################################"
echo "### The Revenge of the Automated Testing -> Image Security -> Jenkins  ###"
echo "##########################################################################"
echo
oc login --server=https://api.${CLUSTER_DOMAIN##apps.}:6443 -u ${USERNAME} -p ${PASSWORD} >/dev/null 2>&1

echo "==> Perform step 1) ROX_CREDS using /projects/pet-battle/Jenkinsfile"
read -p "Press [Enter] when done to continue..."

echo "==> Perform step 2) Add image scanning stage on /projects/pet-battle/Jenkinsfile at //IMAGE SCANNING"
read -p "Press [Enter] when done to continue..."

cd /projects/pet-battle
git add .
git commit -m  "ADD - image scan stage"
git push 

echo "==> Log to ${JENKINS_URL} See pet-battle pipeline running with the image-scan stag."
read -p "Press [Enter] when done to continue..."

echo "==> Perform step Check Build/Deploy Time Violations 1) extend /projects/pet-battle/Jenkinsfile at //BUILD & DEPLOY CHECKS"
read -p "Press [Enter] when done to continue..."

cd /projects/pet-battle
git add .
git commit -m  "ADD - image scan stage"
git push

echo "==> Log to ${JENKINS_URL} observer the pet-battle pipeline, check the logs for image scanning stage and detects some violations for deploy.(Blue Ocean)"
read -p "Press [Enter] when done to continue..."

echo "==> Log to ${ROX_URL} See Violations"
read -p "Press [Enter] when done to continue..."

echo "==> TODO - Add the violation fix from Dragons"
read -p "Press [Enter] when done to continue..."

echo
echo "#########################################################################"
echo "### The Revenge of the Automated Testing -> Image Security -> Tekton  ###"
echo "#########################################################################"
echo
oc login --server=https://api.${CLUSTER_DOMAIN##apps.}:6443 -u ${USERNAME} -p ${PASSWORD} >/dev/null 2>&1

cd /projects/tech-exercise
cat <<'EOF' > tekton/templates/tasks/rox-image-scan.yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: rox-image-scan
spec:
  workspaces:
    - name: output
  params:
    - name: ROX_SECRET
      type: string
      description: Secret containing the Stackrox endpoint and token as (username and password)
      default: rox-auth
    - name: IMAGE
      type: string
      description: Full name of image to scan (example -- gcr.io/rox/sample:5.0-rc1)
    - name: OUTPUT_FORMAT
      type: string
      description:  Output format (json | csv | table)
      default: json
    - name: WORK_DIRECTORY
      description: Directory to start build in (handle multiple branches)
  steps:
    - name: rox-image-scan
      image: registry.access.redhat.com/ubi8/ubi-minimal:latest
      workingDir: $(workspaces.output.path)/$(params.WORK_DIRECTORY)
      env:
        - name: ROX_API_TOKEN
          valueFrom:
            secretKeyRef:
              name: $(params.ROX_SECRET)
              key: password
        - name: ROX_ENDPOINT
          valueFrom:
            secretKeyRef:
              name: $(params.ROX_SECRET)
              key: username
      script: |
        #!/usr/bin/env bash
        set +x
        export NO_COLOR="True"
        curl -k -L -H "Authorization: Bearer $ROX_API_TOKEN" https://$ROX_ENDPOINT/api/cli/download/roxctl-linux --output roxctl  > /dev/null; echo "Getting roxctl"
        chmod +x roxctl > /dev/null
        ./roxctl image scan --insecure-skip-tls-verify -e $ROX_ENDPOINT:443 --image $(params.IMAGE) -o $(params.OUTPUT_FORMAT)
EOF

cd /projects/tech-exercise
git add .
git commit -m  "ADD - rox-image-scan-task"
git push 

echo "==> Perform step 3) Edit /projects/tech-exercise/tekton/templates/pipeline/maven-pipeline.yaml to add image-scan step. Edit helm-package step to runafter image-scan"
read -p "Press [Enter] when done to continue..."

cd /projects/tech-exercise
git add .
git commit -m  "ADD - image-scan step to pipeline"
git push

sleep 30
cd /projects/pet-battle-api
git commit --allow-empty -m "test image-scan step"
git push

echo "==> Log to ${OCP_CONSOLE} Observe Pipeline running -> Pipelines -> Pipelines in your ${TEAM_NAME}-ci-cd project -> pet-battle-api-xxx -> Details. See the image-scan task."
read -p "Press [Enter] when done to continue..."

cd /projects/tech-exercise
cat <<'EOF' >> tekton/templates/tasks/rox-image-scan.yaml
    - name: rox-image-check
      image: registry.access.redhat.com/ubi8/ubi-minimal:latest
      workingDir: $(workspaces.output.path)/$(params.WORK_DIRECTORY)
      env:
        - name: ROX_API_TOKEN
          valueFrom:
            secretKeyRef:
              name: $(params.ROX_SECRET)
              key: password
        - name: ROX_ENDPOINT
          valueFrom:
            secretKeyRef:
              name: $(params.ROX_SECRET)
              key: username
      script: |
        #!/usr/bin/env bash
        set +x
        export NO_COLOR="True"
        curl -k -L -H "Authorization: Bearer $ROX_API_TOKEN" https://$ROX_ENDPOINT/api/cli/download/roxctl-linux --output roxctl  > /dev/null;echo "Getting roxctl"
        chmod +x roxctl > /dev/null
        ./roxctl image check --insecure-skip-tls-verify -e $ROX_ENDPOINT:443 --image $(params.IMAGE) -o json
        if [ $? -eq 0 ]; then
          echo "🦕 no issues found 🦕";
          exit 0;
        else
          echo "🛑 image checks failed 🛑";
          exit 1;
        fi
EOF

cd /projects/tech-exercise
git add .
git commit -m  "ADD - rox-image-check-task"
git push

sleep 30
cd /projects/pet-battle-api
git commit --allow-empty -m "test image-check step"
git push

echo "==> Log to ${OCP_CONSOLE} Observe the pet-battle-api pipeline running with the image-scan task."
read -p "Press [Enter] when done to continue..."

echo "==> Perform step Breaking the Build  1) and 2) edit pet-battle-api/Dockerfile.jvm"
read -p "Press [Enter] when done to continue..."

cd /projects/pet-battle-api
git add .
git commit -m  "Expose port 22"
git push

echo "==> Log to ${OCP_CONSOLE} Observe the pet-battle-api pipeline running with the image-scan task. The run will fail on image-scan step due to :22 violation"
read -p "Press [Enter] when done to continue..."

echo "==> Log to ${ROX_URL} Back in ACS we can also see the failure in the Violations view"
read -p "Press [Enter] when done to continue..."

echo "==> Perform step Breaking the Build 6) edit pet-battle-api/Dockerfile.jvm to remove :22 and fix the issue"
read -p "Press [Enter] when done to continue..."

cd /projects/pet-battle-api
git add .
git commit -m  "FIX - Security violation, remove port 22 exposure"
git push

echo "==> Log to ${OCP_CONSOLE} Observe the pet-battle-api pipeline running successfully again."
read -p "Press [Enter] when done to continue..."

echo
echo "##############################################################"
echo "### The Revenge of the Automated Testing -> Image Signing  ###"
echo "##############################################################"
echo

cd /tmp
cosign generate-key-pair k8s://${TEAM_NAME}-ci-cd/${TEAM_NAME}-cosign

echo
echo "#########################################################################"
echo "### The Revenge of the Automated Testing -> Image Signing -> Jenkins  ###"
echo "#########################################################################"
echo

echo "==> Perform step 1) Edit /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml to add jenkins-agent-cosign."
read -p "Press [Enter] when done to continue..."

cd /projects/tech-exercise
git add ubiquitous-journey/values-tooling.yaml
git commit -m  "ADD - Cosign Jenkins Agent"
git push

echo "==> Perform step 2) Edit /projects/pet-battle/Jenkinsfile to add cosign step at //IMAGE SIGN EXAMPLE GOES HERE."
read -p "Press [Enter] when done to continue..."

cp /tmp/cosign.pub /projects/pet-battle/
cd /projects/pet-battle
git add cosign.pub Jenkinsfile
git commit -m  "ADD - cosign public key for image verification and Jenkinsfile updated"
git push

echo "==> Log to ${JENKINS_URL} Observe the pet-battle pipeline running with the image-sign stage. (Blue Ocean)"
read -p "Press [Enter] when done to continue..."

echo "==> Log to ${OCP_CONSOLE} Builds > ImageStreams inside ${TEAM_NAME}-test namespace and select pet-battle. See a tag ending with .sig which shows you that this is image signed."
read -p "Press [Enter] when done to continue..."

cd /projects/pet-battle
oc login --server=https://api.${CLUSTER_DOMAIN##apps.}:6443 -u ${USERNAME} -p ${PASSWORD}
oc registry login $(oc registry info) --insecure=true
cosign verify --key k8s://${TEAM_NAME}-ci-cd/${TEAM_NAME}-cosign default-route-openshift-image-registry.${CLUSTER_DOMAIN}/${TEAM_NAME}-test/pet-battle:1.2.0 --allow-insecure-registry

echo
echo "########################################################################"
echo "### The Revenge of the Automated Testing -> Image Signing -> Tekton  ###"
echo "########################################################################"
echo

cd /projects/tech-exercise
cat <<'EOF' > tekton/templates/tasks/image-signing.yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: image-signing
spec:
  workspaces:
    - name: output
  params:
    - name: APPLICATION_NAME
      description: Name of the application
      type: string
    - name: TEAM_NAME
      description: Name of the team that doing this exercise :)
      type: string
    - name: VERSION
      description: Version of the application
      type: string
    - name: COSIGN_VERSION
      type: string
      description: Version of cosign CLI
      default: 1.0.0
    - name: WORK_DIRECTORY
      description: Directory to start build in (handle multiple branches)
      type: string
  steps:
    - name: image-signing
      image: quay.io/openshift/origin-cli:4.9
      workingDir: $(workspaces.output.path)/$(params.WORK_DIRECTORY)
      script: |
        #!/usr/bin/env bash
        curl -skL -o /tmp/cosign https://github.com/sigstore/cosign/releases/download/v$(params.COSIGN_VERSION)/cosign-linux-amd64
        chmod -R 775 /tmp/cosign

        oc registry login
        /tmp/cosign sign -key k8s://$(params.TEAM_NAME)-ci-cd/$(params.TEAM_NAME)-cosign `oc registry info`/$(params.TEAM_NAME)-test/$(params.APPLICATION_NAME):$(params.VERSION)
EOF

echo "==> Perform step 2) Edit /projects/tech-exercise/tekton/templates/pipeline/maven-pipeline.yaml to add image-sign step. //Cosign Image Sign"
read -p "Press [Enter] when done to continue..."

cd /projects/tech-exercise
git add .
git commit -m  "ADD - image-signing-task"
git push

sleep 30
cp /tmp/cosign.pub /projects/pet-battle-api/
cd /projects/pet-battle-api
git add cosign.pub
git commit -m  "ADD - cosign public key for image verification"
git push

echo "==> Log to ${OCP_CONSOLE} Observe the pet-battle-api pipeline running with the image-sign task."
read -p "Press [Enter] when done to continue..."

echo "==> Log to ${OCP_CONSOLE} Builds > ImageStreams inside ${TEAM_NAME}-test namespace and select pet-battle-api. See a tag ending with .sig which shows you that this is image signed."
read -p "Press [Enter] when done to continue..."

cd /projects/pet-battle-api
oc registry login $(oc registry info) --insecure=true
cosign verify --key k8s://${TEAM_NAME}-ci-cd/${TEAM_NAME}-cosign default-route-openshift-image-registry.${CLUSTER_DOMAIN}/${TEAM_NAME}-test/pet-battle-api:1.3.1 --allow-insecure-registry

echo
echo "########################################################################"
echo "### The Revenge of the Automated Testing -> Load Testing -> Jenkins  ###"
echo "########################################################################"
echo

echo "==> Perform step 1) Edit /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml to add jenkins-agent-python."
read -p "Press [Enter] when done to continue..."

cd /projects/tech-exercise
git add ubiquitous-journey/values-tooling.yaml
git commit -m  "ADD - Python Jenkins Agent"
git push

cat << EOF > /projects/pet-battle/locustfile.py

import logging
from locust import HttpUser, task, events

class getCat(HttpUser):
  @task
  def cat(self):
      self.client.get("/home", verify=False)

@events.quitting.add_listener
def _(environment, **kw):
  if environment.stats.total.fail_ratio > 0.01:
      logging.error("Test failed due to failure ratio > 1%")
      environment.process_exit_code = 1
  elif environment.stats.total.avg_response_time > 200:
      logging.error("Test failed due to average response time ratio > 200 ms")
      environment.process_exit_code = 1
  elif environment.stats.total.get_response_time_percentile(0.95) > 800:
      logging.error("Test failed due to 95th percentile response time > 800 ms")
      environment.process_exit_code = 1
  else:
      environment.process_exit_code = 0
EOF

echo "==> Perform step 3) Edit /projects/pet-battle/Jenkinsfile to add load-test step at //LOAD TESTING EXAMPLE GOES HERE."
read -p "Press [Enter] when done to continue..."

cd /projects/pet-battle
git add Jenkinsfile locustfile.py
git commit -m  "ADD - load testing stage and locustfile"
git push

echo "==> Log to ${JENKINS_URL} Obeserve the pet-battle pipeline running with the load testing stage, (Blue Ocean). If the pipeline fails due to the thresh-holds we set, you can always adjust it by updating the locustfile.py with higher values."
read -p "Press [Enter] when done to continue..."

echo
echo "#######################################################################"
echo "### The Revenge of the Automated Testing -> Load Testing -> Tekton  ###"
echo "#######################################################################"
echo

cat << EOF > /projects/pet-battle-api/locustfile.py

import logging
from locust import HttpUser, task, events

class getCat(HttpUser):
  @task
  def cat(self):
      self.client.get("/cats", verify=False)

@events.quitting.add_listener
def _(environment, **kw):
  if environment.stats.total.fail_ratio > 0.01:
      logging.error("Test failed due to failure ratio > 1%")
      environment.process_exit_code = 1
  elif environment.stats.total.avg_response_time > 200:
      logging.error("Test failed due to average response time ratio > 200 ms")
      environment.process_exit_code = 1
  elif environment.stats.total.get_response_time_percentile(0.95) > 800:
      logging.error("Test failed due to 95th percentile response time > 800 ms")
      environment.process_exit_code = 1
  else:
      environment.process_exit_code = 0

EOF

cd /projects/tech-exercise
cat <<'EOF' > tekton/templates/tasks/load-testing.yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: load-testing
spec:
  workspaces:
    - name: output
  params:
    - name: APPLICATION_NAME
      description: Name of the application
      type: string
    - name: TEAM_NAME
      description: Name of the team that doing this exercise :)
      type: string
    - name: WORK_DIRECTORY
      description: Directory to start build in (handle multiple branches)
      type: string
  steps:
    - name: load-testing
      image: quay.io/centos7/python-38-centos7:latest
      workingDir: $(workspaces.output.path)/$(params.WORK_DIRECTORY)
      script: |
        #!/usr/bin/env bash
        pip3 install locust
        locust --headless --users 10 --spawn-rate 1 -H https://$(params.APPLICATION_NAME)-$(params.TEAM_NAME)-test.{{ .Values.cluster_domain }} --run-time 1m --loglevel INFO --only-summary 
EOF

echo "==> Perform step 3) Edit /projects/tech-exercise/tekton/templates/pipeline/maven-pipeline.yaml to add load-test step. //Load Testing"
read -p "Press [Enter] when done to continue..."

cd /projects/tech-exercise/tekton
git add .
git commit -m  "ADD - load testing task"
git push

sleep 30
cd /projects/pet-battle-api
git add locustfile.py
git commit -m  "ADD - locustfile for load testing"
git push

echo "==> Log to ${OCP_CONSOLE} Observe the pet-battle-api pipeline running with the load-testing task. If the pipeline fails due to the tresholds we set, you can always adjust it by updating the locustfile.py with higher values."
read -p "Press [Enter] when done to continue..."


echo
echo "#######################################################################"
echo "### The Revenge of the Automated Testing -> System Test -> Jenkins  ###"
echo "#######################################################################"
echo

echo "==> XXX No instructions here? XXX."
read -p "Press [Enter] when done to continue..."

echo
echo "######################################################################"
echo "### The Revenge of the Automated Testing -> System Test -> Tekton  ###"
echo "######################################################################"
echo

echo "==> XXX No instructions here? XXX."
read -p "Press [Enter] when done to continue..."

echo
echo "######################################################"
echo "### Return of the Monitoring -> Enable Monitoring  ###"
echo "######################################################"
echo

echo "==> Perform Add Grafana & Service Monitor step 1) Open /projects/tech-exercise/pet-battle/test/values.yaml and /projects/tech-exercise/pet-battle/stage/values.yaml files. Update values for pet-battle-api adding 'servicemonitor: true' ."
read -p "Press [Enter] when done to continue..."

cd /projects/tech-exercise
git add .
git commit -m "ServiceMonitor enabled" 
git push

sleep 30
oc get servicemonitor -n ${TEAM_NAME}-test -o yaml

echo "==> Perform Add Grafana & Service Monitor step 2) Edit /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml to add grafana dashboard"
read -p "Press [Enter] when done to continue..."

cd /projects/tech-exercise
git add .
git commit -m "Grafana added"
git push

echo "==> Log to ${ARGO_URL} and verify that grafana app is deployed"
read -p "Press [Enter] when done to continue..."

GRAFANA_URL=$(echo https://$(oc get route grafana-route --template='{{ .spec.host }}' -n ${TEAM_NAME}-ci-cd))
echo export GRAFANA_URL="${GRAFANA_URL}" | tee -a ~/.bashrc -a ~/.zshrc

echo "==> Log to ${GRAFANA_URL} The Dashboards should be showing some basic information."
read -p "Press [Enter] when done to continue..."

for i in {1..3}
do
  sleep 60
  curl -k -vL $(oc get route/pet-battle-api -n ${TEAM_NAME}-test --template='{{.spec.host}}')/dogs
  curl -k -vL -X POST -d '{"OK":"🐈"}' $(oc get route/pet-battle-api -n ${TEAM_NAME}-test --template='{{.spec.host}}')/cats/
  curl -k -vL $(oc get route/pet-battle-api -n ${TEAM_NAME}-test --template='{{.spec.host}}')/api/dogs
  curl -k -vL -X POST -d '{"OK":"🦆"}' $(oc get route/pet-battle-api -n ${TEAM_NAME}-test --template='{{.spec.host}}')/cats/
  curl -k -vL $(oc get route/pet-battle-api -n ${TEAM_NAME}-test --template='{{.spec.host}}')/api/dogs
  curl -k -vL -X POST -d '{"OK":"🐶"}' $(oc get route/pet-battle-api -n ${TEAM_NAME}-test --template='{{.spec.host}}')/cats/
done

echo "==> Back to ${GRAFANA_URL} See some data populated into the 4xx and 5xx boards."
read -p "Press [Enter] when done to continue..."

GRAFANA_ADMIN_CREDEN=$(oc get secret grafana-admin-credentials -o=jsonpath='{.data.GF_SECURITY_ADMIN_PASSWORD}' -n ${TEAM_NAME}-ci-cd | base64 -d; echo -n)
echo "GRAFANA_ADMIN_CREDEN: ${GRAFANA_ADMIN_CREDEN}"

echo "==> Perform Create a Dashboard step 2), 3), 4), and 5). Use admin / ${GRAFANA_ADMIN_CREDEN} to sign to grafana"
read -p "Press [Enter] when done to continue..."

echo
echo "##################################################"
echo "### Return of the Monitoring -> Create Alerts  ###"
echo "##################################################"
echo
oc login --server=https://api.${CLUSTER_DOMAIN##apps.}:6443 -u ${USERNAME} -p ${PASSWORD} >/dev/null 2>&1

cat << EOF >> /projects/pet-battle-api/chart/templates/prometheusrule.yaml
    - alert: PetBattleMongoDBDiskUsage
      annotations:
        message: 'Pet Battle MongoDB disk usage in namespace {{ .Release.Namespace }} higher than 80%'
      expr: (kubelet_volume_stats_used_bytes{persistentvolumeclaim="pet-battle-api-mongodb",namespace="{{ .Release.Namespace }}"} / kubelet_volume_stats_capacity_bytes{persistentvolumeclaim="pet-battle-api-mongodb",namespace="{{ .Release.Namespace }}"}) * 100 > 80
      labels:
        severity: {{ .Values.prometheusrules.severity | default "warning" }}
EOF

cat << EOF >> /projects/pet-battle-api/chart/templates/prometheusrule.yaml
    - alert: PetBattleApiMaxHttpRequestTime
      annotations:
        message: 'Pet Battle Api max http request time over last 5 min in namespace {{ .Release.Namespace }} exceeds 1.5 sec.'
      expr: max_over_time(http_server_requests_seconds_max{service="pet-battle-api",namespace="{{ .Release.Namespace }}"}[5m]) > 1.5
      labels:
        severity: {{ .Values.prometheusrules.severity | default "warning" }}
EOF

cd /projects/pet-battle-api
mvn -ntp versions:set -DnewVersion=1.3.2

cd /projects/pet-battle-api
git add .
git commit -m  "ADD - Alerting Rules extended"
git push

echo "==> Log to ${OCP_CONSOLE} Observe Pipeline running -> Pipelines -> Pipelines in your ${TEAM_NAME}-ci-cd project -> pet-battle-api-xxx . When the chart version is updated automatically, ArgoCD will detect your new changes and apply them to the cluster."
read -p "Press [Enter] when done to continue..."

oc project ${TEAM_NAME}-test
oc rsh `oc get po -l app.kubernetes.io/component=mongodb -o name -n ${TEAM_NAME}-test` dd if=/dev/urandom of=/var/lib/mongodb/data/rando-calrissian bs=10M count=50

echo "==> Log to ${OCP_CONSOLE} Observe alert firing  Developer -> Observe > Alerts. Select the right project ${TEAM_NAME}-test from the drop down menu. See PetBattleMongoDBDiskUsage alert ."
read -p "Press [Enter] when done to continue..."

echo
echo "############################################"
echo "### Return of the Monitoring -> Logging  ###"
echo "############################################"
echo

oc project ${TEAM_NAME}-test
oc logs `oc get po -l app.kubernetes.io/component=mongodb -o name -n ${TEAM_NAME}-test` --since 1m

KIBANA_URL=$(echo https://kibana-openshift-logging.${CLUSTER_DOMAIN})
echo export KIBANA_URL="${KIBANA_URL}" | tee -a ~/.bashrc -a ~/.zshrc

echo "==> Log to ${KIBANA_URL} and perform step 4), 5), 6), 7), 8), and 9) ."
read -p "Press [Enter] when done to continue..."

echo
echo "##################################################"
echo "### The Deployments Strike Back - Autoscaling  ###"
echo "##################################################"
echo
oc login --server=https://api.${CLUSTER_DOMAIN##apps.}:6443 -u ${USERNAME} -p ${PASSWORD} >/dev/null 2>&1

echo "==> Perform step 2) Edit /projects/tech-exercise/pet-battle/test/values.yaml and set pet-battle-api hpa to enabled:true"
read -p "Press [Enter] when done to continue..."

cd /projects/tech-exercise
git add pet-battle/test/values.yaml
git commit -m  "ADD - HPA enabled for test env"
git push

echo "==> Log to ${ARGO_URL} and see the new HPA object created on test-pet-battle-api."
read -p "Press [Enter] when done to continue..."

echo "==> K6 load test running... Log to ${OCP_CONSOLE} see autoscaler kicking in and spinnin up additional pods. Administrator -> Workloads -> HPA (${TEAM_NAME}-test). Developer -> Topology (${TEAM_NAME} test)"

sleep 10
cat << EOF > /tmp/load.js
import http from 'k6/http';
import { sleep } from 'k6';
export default function () {
  http.get('https://$(oc get route/pet-battle-api -n ${TEAM_NAME}-test --template='{{.spec.host}}')/cats');
}
EOF

k6 run --insecure-skip-tls-verify --vus 100 --duration 30s /tmp/load.js

read -p "Press [Enter] when done to continue..."

echo "==> Log to ${OCP_CONSOLE} After a few moments you should see the autoscaler settle back down and the replicas are reduced."
read -p "Press [Enter] when done to continue..."

echo
echo "#############################################################"
echo "### The Deployments Strike Back - Blue/Green Deployments  ###"
echo "#############################################################"
echo

cat << EOF >> /projects/tech-exercise/pet-battle/test/values.yaml
  # Pet Battle UI Blue
  blue-pet-battle:
    name: blue-pet-battle
    enabled: true
    source: http://nexus:8081/repository/helm-charts
    chart_name: pet-battle
    source_ref: 1.0.6 # helm chart version - may need adjusting!
    values:
      image_version: latest # container image version - may need adjusting!
      fullnameOverride: blue-pet-battle
      blue_green: active
      # we controll the prod route via the "blue" chart for simplicity
      prod_route: true
      prod_route_svc_name: blue-pet-battle
      config_map: '{
        "catsUrl": "https://pet-battle-api-${TEAM_NAME}-test.${CLUSTER_DOMAIN}",
        "tournamentsUrl": "https://pet-battle-tournament-${TEAM_NAME}-test.${CLUSTER_DOMAIN}",
        "matomoUrl": "https://matomo-${TEAM_NAME}-ci-cd.${CLUSTER_DOMAIN}/",
        "keycloak": {
          "url": "https://keycloak-${TEAM_NAME}-test.${CLUSTER_DOMAIN}/auth/",
          "realm": "pbrealm",
          "clientId": "pbclient",
          "redirectUri": "http://localhost:4200/tournament",
          "enableLogging": true
        }
      }'

  # Pet Battle UI Green
  green-pet-battle:
    name: green-pet-battle
    enabled: true
    source: http://nexus:8081/repository/helm-charts
    chart_name: pet-battle
    source_ref: 1.0.6 # helm chart version - may need adjusting!
    values:
      image_version: latest # container image version - may need adjusting!
      fullnameOverride: green-pet-battle
      blue_green: inactive
      config_map: '{
        "catsUrl": "https://pet-battle-api-${TEAM_NAME}-test.${CLUSTER_DOMAIN}",
        "tournamentsUrl": "https://pet-battle-tournament-${TEAM_NAME}-test.${CLUSTER_DOMAIN}",
        "matomoUrl": "https://matomo-${TEAM_NAME}-ci-cd.${CLUSTER_DOMAIN}/",
         "keycloak": {
          "url": "https://keycloak-${TEAM_NAME}-test.${CLUSTER_DOMAIN}/auth/",
          "realm": "pbrealm",
          "clientId": "pbclient",
          "redirectUri": "http://localhost:4200/tournament",
          "enableLogging": true
        }
      }'
EOF

cd /projects/tech-exercise
git add pet-battle/test/values.yaml
git commit -m  "ADD - blue & green environments"
git push

sleep 60
oc get svc -l blue_green=inactive --no-headers -n ${TEAM_NAME}-test
oc get svc -l blue_green=active --no-headers -n ${TEAM_NAME}-test

echo "==> Perform step 4) Edit /projects/pet-battle/Jenkinsfile file to pdate the Jenkinsfile to do the deployment for the inactive. //BLUE / GREEN DEPLOYMENT GOES HERE"
read -p "Press [Enter] when done to continue..."

echo "==> Perform step 5), 6)"
read -p "Press [Enter] when done to continue..."

cd /projects/pet-battle
git add .
git commit -m "ADD - Blue / Green deployment to pipeline"
git push

echo "==> Perform step 8)"
read -p "Press [Enter] when done to continue..."

echo
echo "######################################################"
echo "### The Deployments Strike Back - A/B Deployments  ###"
echo "######################################################"
echo

echo "==> Perform A/B and Analytics step 1) Edit /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml and add matomo application."
read -p "Press [Enter] when done to continue..."

### TODO: This must be documented on the lectures
cd /projects/tech-exercise
git remote set-url origin https://${GIT_SERVER}/${TEAM_NAME}/tech-exercise.git
git pull
###

cd /projects/tech-exercise
git add .
git commit -m  "ADD - matomo app"
git push 

sleep 120
oc get pod -n ${TEAM_NAME}-ci-cd

MATOMO_URL=$(echo https://$(oc get route/matomo -n ${TEAM_NAME}-ci-cd --template='{{.spec.host}}'))
echo export MATOMO_URL="${MATOMO_URL}" | tee -a ~/.bashrc -a ~/.zshrc

echo "==> Log to ${MATOMO_URL} admin / 'My\$uper\$ecretPassword123#' no data yet"
read -p "Press [Enter] when done to continue..."

cat << EOF >> /projects/tech-exercise/pet-battle/test/values.yaml
  # Pet Battle UI - experiment
  pet-battle-b:
    name: pet-battle-b
    enabled: true
    source: http://nexus:8081/repository/helm-charts
    chart_name: pet-battle
    source_ref: 1.0.6 # helm chart version - may need adjusting!
    values:
      image_version: latest # container image version - may need adjusting!
      fullnameOverride: pet-battle-b
      route: false
      config_map: '{
        "catsUrl": "https://pet-battle-api-${TEAM_NAME}-test.${CLUSTER_DOMAIN}",
        "tournamentsUrl": "https://pet-battle-tournament-${TEAM_NAME}-test.${CLUSTER_DOMAIN}",
        "matomoUrl": "https://matomo-${TEAM_NAME}-ci-cd.${CLUSTER_DOMAIN}/",
        "keycloak": {
          "url": "https://keycloak-${TEAM_NAME}-test.${CLUSTER_DOMAIN}/auth/",
          "realm": "pbrealm",
          "clientId": "pbclient",
          "redirectUri": "http://localhost:4200/tournament",
          "enableLogging": true
        }
      }'
EOF

echo "==> Perform A/B Deployment 2) Edit /projects/tech-exercise/pet-battle/test/values.yaml to extend the configuration for the existing Pet Battle deployment (A) by adding the a_b_deploy properties to the values section."
read -p "Press [Enter] when done to continue..."

cd /projects/tech-exercise
git add pet-battle/test/values.yaml
git commit -m  "ADD - A & B environments"
git push

sleep 60
oc get svc -l app.kubernetes.io/instance=pet-battle -n ${TEAM_NAME}-test
oc get svc -l app.kubernetes.io/instance=pet-battle-b -n ${TEAM_NAME}-test

echo "==> Perform A/B Deployment step 5) and 6)"
read -p "Press [Enter] when done to continue..."

cd /projects/pet-battle
git add .
git commit -m "ADD - Green banner"
git push

PET_BATTLE_URL=$(oc get route/pet-battle -n ${TEAM_NAME}-test --template='{{.spec.host}}')
echo export PET_BATTLE_URL="${PET_BATTLE_URL}" | tee -a ~/.bashrc -a ~/.zshrc

echo "==> Perform A/B Deployment step 8). PET_BATTLE_URL: ${PET_BATTLE_URL} ."
read -p "Press [Enter] when done to continue..."

cd /projects/tech-exercise
yq eval -i .applications.pet-battle.values.a_b_deploy.a_weight='100' pet-battle/test/values.yaml
yq eval -i .applications.pet-battle.values.a_b_deploy.b_weight='100' pet-battle/test/values.yaml
git add pet-battle/test/values.yaml
git commit -m  "service B weight increased to 50%"
git push

echo "==> Perform A/B Deployment step 10). PET_BATTLE_URL: ${PET_BATTLE_URL} ."
read -p "Press [Enter] when done to continue..."

cd /projects/tech-exercise
yq eval -i .applications.pet-battle.values.a_b_deploy.a_weight='100' pet-battle/test/values.yaml
yq eval -i .applications.pet-battle.values.a_b_deploy.b_weight='0' pet-battle/test/values.yaml
git add pet-battle/test/values.yaml
git commit -m  "service B weight increased to 100"
git push

echo "==> Perform A/B Deployment step 11). PET_BATTLE_URL: ${PET_BATTLE_URL} MATOMO_URL: ${MATOMO_URL} ."
read -p "Press [Enter] when done to continue..."

echo
echo "###########################"
echo "### Rise of the Cluster ###"
echo "###########################"
echo

echo "==> Additional content info. Student will not run it on the course."
read -p "Press [Enter] when done to continue..."
