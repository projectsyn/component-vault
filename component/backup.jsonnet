local backup = import 'lib/backup-k8up.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.vault;


local backupSecret = kube.Secret('%s-backup-password' % params.name) {
  stringData: {
    password: params.backup.password,
  },
};
local backupSecretRef = {
  key: 'password',
  name: backupSecret.metadata.name,
};

local bucketSecret = kube.Secret('%s-backup-s3-credentials' % params.name) {
  stringData: {
    username: params.backup.bucket.accesskey,
    password: params.backup.bucket.secretkey,
  },
};
local bucketSecretRef = {
  name: bucketSecret.metadata.name,
  accesskeyname: 'username',
  secretkeyname: 'password',
};

local schedule = backup.Schedule(
  params.name,
  params.backup.schedule,
  keep_jobs=params.backup.keepjobs,
  bucket=params.backup.bucket.name,
  backupkey=backupSecretRef,
  s3secret=bucketSecretRef,
  create_bucket=false,
).schedule + backup.PruneSpec('23 * * * *', 30, 20) {
  metadata+: {
    namespace: params.namespace,
  },
};

local backupConfig = kube.ConfigMap('%s-backup' % params.name) {
  metadata+: {
    namespace: params.namespace,
  },
  data: {
    'vault-agent-config.hcl': |||
      exit_after_auth = false
      auto_auth {
          method "kubernetes" {
              config = {
                  role = "backup"
              }
          }
          sink "file" {
              config = {
                  path = "/home/vault/.vault-token"
                  mode = 0644
              }
          }
      }
    |||,
  },
};

local backupSA = kube.ServiceAccount('%s-backup' % params.name) {
  metadata+: {
    namespace: params.namespace,
  },
};

local backupPod = backup.PreBackupPod(
  params.name,
  '%s/%s:%s' % [ params.images.vault.registry, params.images.vault.repository, params.images.vault.version ],
  'vault operator raft snapshot save /dev/stdout',
  fileext='.snapshot'
) {
  metadata+: {
    namespace: params.namespace,
  },
  spec+: {
    pod+: {
      spec+: kube.PodSpec {
        containers_: {
          backup: kube.Container('backup') {
            image: '%s/%s:%s' % [ params.images.vault.registry, params.images.vault.repository, params.images.vault.version ],
            env_: {
              HOME: '/home/vault',
              VAULT_ADDR: 'http://%s-active:8200' % params.name,
              SKIP_SETCAP: 'true',
              VAULT_TOKEN: {
                secretKeyRef: {
                  name: '%s-seal' % params.name,
                  key: 'vault-root',
                },
              },
            },
            volumeMounts_+: {
              config: {
                mountPath: '/etc/vault/',
              },
              home: {
                mountPath: '/home/vault',
              },
            },
          },
        },
        volumes_: {
          config: {
            configMap: {
              name: backupConfig.metadata.name,
            },
          },
          home: {
            emptyDir: {},
          },
        },
        serviceAccountName: backupSA.metadata.name,
      },
    },
  },
};

if params.backup.enabled then {
  '31_schedule': [ backupSecret, bucketSecret, schedule ],
  '32_backup': [ backupConfig, backupPod, backupSA ],
} else {}
