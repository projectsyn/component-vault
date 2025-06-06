// template adding configuration for vault
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.vault;

local config =
  // This function transforms field `roles` of the passed object from an
  // object with role names as keys and role configs as values into a list.
  local renderRoles(data) =
    if std.objectHas(data, 'roles') then
      data {
        roles: [
          data.roles[n] {
            name: n,
          }
          for n in std.objectFields(data.roles)
          if data.roles[n] != null
        ],
      }
    else
      data;

  // This function renders bankvaults config list from an object which has
  // field `[idkey]` of each entry as keys and the remaining config as values.
  // The function looks up the source object by reading `<sourcekey>_` in
  // component parameter `config`.
  //
  // This function calls `renderRoles()` to recursively transform field
  // `roles` of each entry of the field (if the entry has field `roles`).
  local renderField(sourcekey, idkey) =
    local data = std.get(params.config, '%s_' % sourcekey, {});
    [
      renderRoles(data[k]) {
        [idkey]: k,
      }
      for k in std.objectFields(data)
      if data[k] != null
    ];

  local rendered = std.prune({
    // NOTE(sg): new Bankvaults fields which are expected to be lists need to
    // be added here
    audit: renderField('audit', 'type'),
    auth: renderField('auth', 'path'),
    plugins: renderField('plugins', 'plugin_name'),
    policies: renderField('policies', 'name'),
    secrets: renderField('secrets', 'path'),
    startupSecrets: renderField('startupSecrets', 'path'),
  });
  // append configs provided in un-suffixed fields. This should preserve order
  // of configs for existing clusters.
  rendered {
    [if !std.endsWith(k, '_') then k]+: params.config[k]
    for k in std.objectFields(params.config)
  };


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
