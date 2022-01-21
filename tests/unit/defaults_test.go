package main

import (
	"fmt"
	"io/ioutil"
	"strings"
	"testing"

	"github.com/instrumenta/kubeval/kubeval"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/yaml"
)

var (
	testPath       = "../../compiled/vault/vault"
	extraConfigHcl = `disable_mlock = true
ui = true
listener "tcp" {
  tls_disable = true
  address = "[::]:8200"
  cluster_address = "[::]:8201"
  x_forwarded_for_authorized_addrs = "198.51.100.0/24"
  x_forwarded_for_hop_skips = "0"
  x_forwarded_for_reject_not_authorized = "true"
  x_forwarded_for_reject_not_present = "false"
}
listener "tcp" {
  tls_disable = true
  address = "[::]:9200"
  telemetry {
    unauthenticated_metrics_access = true
  }
}
storage "raft" {
  path = "/vault/data"
}
service_registration "kubernetes" {}
telemetry {
  disable_hostname = true
}`
)

func validate(t *testing.T, path string) {
	files, err := ioutil.ReadDir(path)
	require.NoError(t, err)
	for _, file := range files {
		filePath := fmt.Sprintf("%s/%s", path, file.Name())
		if file.IsDir() {
			validate(t, filePath)
		} else {
			data, err := ioutil.ReadFile(filePath)
			require.NoError(t, err)

			conf := kubeval.NewDefaultConfig()
			res, err := kubeval.Validate(data, conf)
			if err != nil && strings.Contains(err.Error(), "404 Not Found") {
				// We do not have the api specification for the respecive resource we
				// skip for now
				// TODO(glrf) maybe we could load the CRD specification
				continue
			}
			require.NoError(t, err)
			for _, r := range res {
				if len(r.Errors) > 0 {
					t.Errorf("%s", filePath)
				}
				for _, e := range r.Errors {
					t.Errorf("\t %s", e)
				}
			}
		}
	}
}
func Test_Validate(t *testing.T) {
	validate(t, testPath)
}

func Test_Namespace(t *testing.T) {
	ns := corev1.Namespace{}
	data, err := ioutil.ReadFile(testPath + "/00_namespace.yaml")
	require.NoError(t, err)
	err = yaml.Unmarshal(data, &ns)
	require.NoError(t, err)
	assert.Equal(t, "vault", ns.Name)
}

func Test_HelmChartVaultConfig(t *testing.T) {
	cm := corev1.ConfigMap{}
	data, err := ioutil.ReadFile(testPath + "/10_vault/vault/templates/server-config-configmap.yaml")
	require.NoError(t, err)
	err = yaml.Unmarshal(data, &cm)
	require.NoError(t, err)
	expectedData := map[string]string{
		"extraconfig-from-values.hcl": extraConfigHcl,
	}
	assert.Equal(t, expectedData, cm.Data)
}
