// template adding an additional role to enable auto unsealing
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.vault;

local name = params.name + '-unseal';

local unsealRole = kube.Role(name) {
  metadata+: {
    namespace: params.namespace,
  },
  rules: [
    {
      apiGroups: [ '' ],
      resources: [ 'secrets' ],
      verbs: [
        'get',
        'create',
        'update',
        'patch',
      ],
    },
  ],
};

local unsealRoleBinding = kube.RoleBinding(name) {
  metadata+: {
    namespace: params.namespace,
  },
  roleRef: {
    kind: 'Role',
    apiGroup: 'rbac.authorization.k8s.io',
    name: unsealRole.metadata.name,
  },
  subjects: [
    {
      kind: 'ServiceAccount',
      name: params.name,
      namespace: params.namespace,
    },
  ],
};

{
  '20_unseal-role': unsealRole,
  '21_unseal-role-binding': unsealRoleBinding,
}
