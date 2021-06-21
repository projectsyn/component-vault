local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.vault;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('vault', params.namespace);

{
  vault: app,
}
