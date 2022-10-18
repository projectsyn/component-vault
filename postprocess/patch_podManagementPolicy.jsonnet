/**
 * Switch to podManagementPolicy: OrderedReady
 */
local com = import 'lib/commodore.libjsonnet';
local inv = com.inventory();
local params = inv.parameters.vault;

local sts_file = std.extVar('output_path') + '/server-statefulset.yaml';


local sts = com.yaml_load(sts_file) + {
  spec+: {
    podManagementPolicy: params.podManagementPolicy,
  },
};


{
  [if params.podManagementPolicy != 'Parallel' then 'server-statefulset']: sts,
}
