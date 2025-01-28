// template adding configuration for vault
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.vault;

local config = params.config;
local configSecret = kube.Secret(params.name) {
  metadata+: {
    namespace: params.namespace,
  },
  stringData: {
    'vault-config.yml': std.manifestYamlDoc(config),
  },
};

local configurer = kube.Deployment('%s-configurer' % params.name) {
  metadata+: {
    namespace: params.namespace,
  },
  spec+: {
    replicas: 1,
    template+: {
      spec+: {
        containers_+: {
          configurer: kube.Container('vault-configurer') {
            image: '%s/%s:%s' % [ params.images.bankvaults.registry, params.images.bankvaults.repository, params.images.bankvaults.version ],
            command: [ 'bank-vaults', 'configure' ],
            args: [
              '--mode=k8s',
              '--k8s-secret-namespace=%s' % params.namespace,
              '--k8s-secret-name=%s-seal' % params.name,
              '--disable-metrics',
              '--vault-config-file=/config/vault-config.yml',
            ],
            resources: {
              requests: { cpu: '100m', memory: '32Mi' },
            },
            env_: {
              VAULT_ADDR: 'http://%s-active:8200' % params.name,
            },
            volumeMounts_+: {
              config: {
                mountPath: '/config/',
              },
            },
          },
        },
        volumes_: {
          config: {
            secret: {
              secretName: configSecret.metadata.name,
            },
          },
        },
        serviceAccountName: params.name,
      },
    },
  },
};


{
  '22_config': [ configSecret, configurer ],
}
