#!/bin/bash

# Copyright 2018 Datawire. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License

set -e -o pipefail

HERE=$(cd $(dirname $0); pwd)

cd "$HERE"

CLEAN_ON_SUCCESS=

if [ "$1" == "--cleanup" ]; then
    CLEAN_ON_SUCCESS="--cleanup"
    shift
fi

ROOT=$(cd ../..; pwd)
PATH="${ROOT}:${PATH}"

source ${ROOT}/utils.sh

check_rbac

initialize_namespace "008-cacert"

kubectl cluster-info

python ${ROOT}/yfix.py ${ROOT}/fixes/test-dep.yfix \
    ${ROOT}/ambassador-deployment.yaml \
    k8s/ambassador-deployment.yaml \
    008-cacert \
    008-cacert

# create secrets for TLS stuff
kubectl create -n 008-cacert secret tls ambassador-certs --cert=certs/server.crt --key=certs/server.key
kubectl create -n 008-cacert secret generic ambassador-cacert --from-file=tls.crt=certs/client.crt 
# --from-literal=cert_required=true

kubectl apply -f k8s/rbac.yaml
kubectl apply -f k8s/ambassador.yaml
kubectl apply -f k8s/ambassador-deployment.yaml
# kubectl run demotest -n 008-cacert --image=dwflynn/demotest:0.0.1 -- /bin/sh -c "sleep 3600"

set +e +o pipefail

wait_for_pods 008-cacert

CLUSTER=$(cluster_ip)
APORT=$(service_port ambassador 008-cacert)
# DEMOTEST_POD=$(demotest_pod)

BASEURL="https://${CLUSTER}:${APORT}"

echo "Base URL $BASEURL"
echo "Diag URL $BASEURL/ambassador/v0/diag/"

wait_for_ready "$BASEURL"

if ! check_diag "$BASEURL" 1 "no services but TLS"; then
    exit 1
fi

if ! check_listeners "$BASEURL" 1 "no services but TLS"; then
    exit 1
fi

if [ -n "$CLEAN_ON_SUCCESS" ]; then
    drop_namespace 008-cacert
fi
