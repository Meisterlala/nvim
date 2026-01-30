return {
  settings = {
    yaml = {
      schemaStore = {
        enable = false,
        url = '',
      },
      -- parse Kubernetes CRDs automatically and download them from the CRD store.
      kubernetesCRDStore = {
        enable = true,
      },
      -- Can never be emtpy, because of a nvim-k8s-crd bug
      schemas = {
        ['https://json.schemastore.org/kustomization.json'] = '**/kustomization.yaml',
      },
      validate = true,
    },
  },
}
