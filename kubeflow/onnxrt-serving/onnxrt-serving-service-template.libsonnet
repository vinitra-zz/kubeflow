{
  local k = import "k.libsonnet",
  local util = import "kubeflow/onnxrt-serving/util.libsonnet",
  new(_env, _params):: {
    local params = _params + _env,
    local namespace = params.namespace,
    local name = params.name,
    local modelName =
      if params.modelName == "null" then
        params.name
      else
        params.modelName,

    local onnxrtService = {
      apiVersion: "v1",
      kind: "Service",
      metadata: {
        labels: {
          app: modelName,
        },
        name: name,
        namespace: namespace,
        annotations: {
          "getambassador.io/config":
            std.join("\n", [
              "---",
              "apiVersion: ambassador/v0",
              "kind:  Mapping",
              "name: onnxrtserving-predict-mapping-" + modelName,
              "prefix: /onnxrtserving/models/" + modelName,
              "rewrite: /v1/models/" + modelName + ":predict",
              "method: POST",
              "service: " + name + "." + namespace + ":8500",
              "---",
              "apiVersion: ambassador/v0",
              "kind:  Mapping",
              "name: onnxrtserving-predict-mapping-" + modelName + "-get",
              "prefix: /onnxrtserving/models/" + modelName,
              "rewrite: /v1/models/" + modelName,
              "method: GET",
              "service: " + name + "." + namespace + ":8500",
            ]),
        } + if util.toBool(params.enablePrometheus) then {
          "prometheus.io/scrape": "true",
          "prometheus.io/path": "/monitoring/prometheus/metrics",
          "prometheus.io/port": "8500",
        } else {},  //annotations
      },
      spec: {
        ports: [
          {
            name: "grpc-onnxrt-serving",
            port: 9000,
            targetPort: 9000,
          },
          {
            name: "http-onnxrt-serving",
            port: 8500,
            targetPort: 8500,
          },
        ],
        selector: {
          app: modelName,
        },
        type: params.serviceType,
      },
    },  // onnxrtService
    onnxrtService:: onnxrtService,

    local versionWeights = std.split(params.trafficRule, ","),
    local virtualService = {
      apiVersion: "networking.istio.io/v1alpha3",
      kind: "VirtualService",
      metadata: {
        name: name,
        namespace: namespace,
      },
      spec: {
        hosts: [
          "*",
        ],
        gateways: [
          "kubeflow-gateway",
        ],
        http: [
          {
            match: [
              {
                uri: {
                  prefix: "/istio/onnxrtserving/models/" + modelName,
                },
                method: {
                  exact: "POST",
                },
              },
            ],
            rewrite: {
              uri: "/v1/models/" + modelName + ":predict",
            },
            route: [
              {
                destination: {
                  host: name,
                  port: {
                    number: 8500,
                  },
                  subset: std.split(versionWeight, ":")[0],
                },
                weight: std.parseInt(std.split(versionWeight, ":")[1]),
              }
              for versionWeight in versionWeights
            ],
          },
        ],
      },
    },
    virtualService:: virtualService,

    local destinationRule = {
      apiVersion: "networking.istio.io/v1alpha3",
      kind: "DestinationRule",
      metadata: {
        name: name,
        namespace: namespace,
      },
      spec: {
        host: name,
        subsets: [
          {
            name: std.split(versionWeight, ":")[0],
            labels: {
              version: std.split(versionWeight, ":")[0],
            },
          }
          for versionWeight in versionWeights
        ],
      },
    },
    destinationRule:: destinationRule,
    all:: util.list([
      onnxrtService,
    ] + if util.toBool(params.injectIstio) then [
      virtualService,
      destinationRule,
    ] else []),
  },  // new
}
