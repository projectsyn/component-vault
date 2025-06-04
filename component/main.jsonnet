local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.vault;

local on_openshift =
  std.member([ 'openshift4', 'oke' ], inv.parameters.facts.distribution);

local ingress =
  // NOTE(sg): The values for `service_name`, `service_port` and `pathType`
  // are reverse engineered from the Helm chart's `server-ingress.yaml`
  // template (version 0.27.0).
  local service_name =
    local sn = params.helm_values.fullnameOverride;
    if
      params.helm_values.server.ha.enabled &&
      std.get(params.helm_values.server.ingress, 'activeService', true) == true then
      sn + '-active'
    else
      sn;
  local service_port = params.helm_values.server.service.port;
  local pathType =
    std.get(params.helm_values.server.ingress, 'pathType', 'Prefix');

  kube.Ingress(params.name) {
    metadata+: {
      annotations+: params.ingress.annotations,
    },
    spec: {
      rules: [
        {
          host: h.host,
          http: {
            paths: [
              {
                backend: {
                  service: {
                    name: service_name,
                    port: {
                      number: 8200,
                    },
                  },
                },
                path: p,
                pathType: pathType,
              }
              for p in h.paths
            ],
          },
        }
        for h in params.helm_values.server.ingress.hosts
      ],
      tls: params.helm_values.server.ingress.tls,
    },
  };

{
  '00_namespace': kube.Namespace(params.namespace),
  [if on_openshift && params.ingress.enabled then '90_ingress']: ingress,
}
