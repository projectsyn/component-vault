// template adding configuration for vault
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.vault;


local config = params.config;

{
  '22_config': kube.ConfigMap(params.name) {
    metadata+: {
      namespace: params.namespace,
    },
    data: {
      'vault-config.yml': std.manifestYamlDoc(config),
    },
  },
}
