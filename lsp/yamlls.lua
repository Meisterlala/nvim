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
      schemas = {
        ['https://json.schemastore.org/kustomization.json'] = '**/kustomization.yaml',
      },
      validate = true,
    },
  },
}
