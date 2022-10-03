#!/bin/bash

#
# Input
#
USERNAME=$1
PASSWORD=$2

#
# Configuration
#
TEAM_NAME=zteam
CLUSTER_DOMAIN=ocp4.example.com
GIT_SERVER=gitlab-ce.apps.ocp4.example.com


if [ "$1" == "reset" ]
then
  oc delete all --all -n ${TEAM_NAME}-ci-cd
  oc delete project ${TEAM_NAME}
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

source ~/.zshrc
echo ${TEAM_NAME}
echo ${CLUSTER_DOMAIN}
echo ${GIT_SERVER}

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

source ~/.zshrc
GITLAB_PAT=$(gitlab_pat)
echo ${GITLAB_PAT}

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

echo "==> Log to https://${GIT_SERVER} and perform the manual steps 2). The argocd webhook url is ${ARGO_WEBHOOK}"
read -p "Press [Enter] when done to continue..."


if [[ $(yq e '.applications[] | select(.name=="nexus") | length' /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml) < 1 ]]; then
    yq e '.applications += {"name": "nexus","enabled": true,"source": "https://redhat-cop.github.io/helm-charts","chart_name": "sonatype-nexus","source_ref": "1.1.10","values":{"includeRHRepositories": false,"service": {"name": "nexus"}}}' -i /projects/tech-exercise/ubiquitous-journey/values-tooling.yaml
fi

cd /projects/tech-exercise
git add .
git commit -m  "ADD - nexus repo manager"
git push 

echo "==> Log to https://${ARGO_URL} and verify that ubiquitous-journey app has deployed a nexus server. We patient, can take up to 5-10min."
read -p "Press [Enter] when done to continue..."


NEXUS_URL=$(echo https://$(oc get route nexus --template='{{ .spec.host }}' -n ${TEAM_NAME}-ci-cd))
echo "==> Log to ${NEXUS_URL}. See credentials on step 4)"
read -p "Press [Enter] when done to continue..."

