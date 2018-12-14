{
  util:: import "kubeflow/onnxrt-serving/util.libsonnet",

  // Parameters are intended to be late bound.
  params:: {
    name: null,
    numGpus: 0,
    labels: {
      app: $.params.name,
    },
    modelName: $.params.name,
    modelPath: null,
    modelStorageType: "storageType",

    version: "v1",
    firstVersion: true,

    deployIstio: false,

    deployHttpProxy: false,
    httpProxyImage: "gcr.io/kubeflow-images-public/onnxrt-model-server-http-proxy:v20180606-9dfda4f2",

    serviceType: "ClusterIP",

    // If users want to override the image then can override defaultCpuImage and/or defaultGpuImage
    // in which case the image used will still depend on whether GPUs are used or not.
    // Users can also override modelServerImage in which case the user supplied value will always be used
    // regardless of numGpus.
    defaultCpuImage: "tensorflow/serving:1.11.1",
    defaultGpuImage: "tensorflow/serving:1.11.1-gpu",
    modelServerImage: if $.params.numGpus == 0 then
      $.params.defaultCpuImage
    else
      $.params.defaultGpuImage,


    // Whether or not to enable s3 parameters
    s3Enable:: false,

    // Which storageType to use
    storageType:: null,
  },

  // Parametes specific to GCP.
  gcpParams:: {
    gcpCredentialSecretName: "",
  } + $.params,

  // Parameters that control S3 access
  // params overrides s3params because params can be overwritten by the user to override the defaults.
  s3params:: {
    //  Name of the k8s secrets containing S3 credentials
    s3SecretName: "",
    // Name of the key in the k8s secret containing AWS_ACCESS_KEY_ID.
    s3SecretAccesskeyidKeyName: "AWS_ACCESS_KEY_ID",

    // Name of the key in the k8s secret containing AWS_SECRET_ACCESS_KEY.
    s3SecretSecretaccesskeyKeyName: "AWS_SECRET_ACCESS_KEY",

    // S3 region
    s3AwsRegion: "us-west-1",

    // The use of strings is left over from when they were prototype parameters which only supports string type.

    // true Whether or not to use https for S3 connections
    s3UseHttps: "true",

    // Whether or not to verify https certificates for S3 connections
    s3VerifySsl: "true",

    // URL for your s3-compatible endpoint.
    s3Endpoint: "http://s3.us-west-1.amazonaws.com,",
  } + $.params,


  components:: {

    all:: [
            // Default routing rule for the first version of model.
            if $.util.toBool($.params.deployIstio) && $.util.toBool($.params.firstVersion) then
              $.parts.defaultRouteRule,
          ] +
          if $.params.s3Enable then
            [
              $.s3parts.onnxrtService,
              $.s3parts.onnxrtDeployment,
            ]
          else if $.params.storageType == "gcp" then
            [
              $.gcpParts.onnxrtService,
              $.gcpParts.onnxrtDeployment,
            ]
          else
            [
              $.parts.onnxrtService,
              $.parts.onnxrtDeployment,
            ],
  }.all,

  parts:: {
    // We define the containers one level beneath parts because combined with jsonnet late binding
    // this makes it easy for users to override specific bits of the container.
    onnxrtServingContainerBase:: {
      name: $.params.name,
      image: $.params.modelServerImage,
      imagePullPolicy: "IfNotPresent",
      command: [
        "/usr/bin/tensorflow_model_server",
      ],
      args: [
        "--port=9000",
        "--model_name=" + $.params.modelName,
        "--model_base_path=" + $.params.modelPath,
      ],
      ports: [
        {
          containerPort: 9000,
        },
      ],
      resources: {
        requests: {
          memory: "1Gi",
          cpu: "1",
        },
        limits: {
          memory: "4Gi",
          cpu: "4",
        },
      },
      securityContext: {
        runAsUser: 1000,
        fsGroup: 1000,
      },
      volumeMounts+: if $.params.modelStorageType == "nfs" then [{
        name: "nfs",
        mountPath: "/mnt",
      }]
      else [],
    },  // onnxrtServingContainer

    onnxrtServingContainer+: $.parts.onnxrtServingContainerBase +
                         if $.params.numGpus > 0 then
                           {
                             resources+: {
                               limits+: {
                                 "nvidia.com/gpu": $.params.numGpus,
                               },
                             },
                           }
                         else {},

    onnxrtServingMetadata+: {
      labels: $.params.labels { version: $.params.version },
      annotations: {
        "sidecar.istio.io/inject": if $.util.toBool($.params.deployIstio) then "true",
      },
    },

    httpProxyContainer:: {
      name: $.params.name + "-http-proxy",
      image: $.params.httpProxyImage,
      imagePullPolicy: "IfNotPresent",
      command: [
        "python",
        "/usr/src/app/server.py",
        "--port=8000",
        "--rpc_port=9000",
        "--rpc_timeout=10.0",
      ],
      env: [],
      ports: [
        {
          containerPort: 8000,
        },
      ],
      resources: {
        requests: {
          memory: "500Mi",
          cpu: "0.5",
        },
        limits: {
          memory: "1Gi",
          cpu: "1",
        },
      },
      securityContext: {
        runAsUser: 1000,
        fsGroup: 1000,
      },
    },  // httpProxyContainer


    onnxrtDeployment: {
      apiVersion: "extensions/v1beta1",
      kind: "Deployment",
      metadata: {
        name: $.params.name + "-" + $.params.version,
        namespace: $.params.namespace,
        labels: $.params.labels,
      },
      spec: {
        template: {
          metadata: $.parts.onnxrtServingMetadata,
          spec: {
            containers: [
              $.parts.onnxrtServingContainer,
              if $.util.toBool($.params.deployHttpProxy) then
                $.parts.httpProxyContainer,
            ],
            volumes+: if $.params.modelStorageType == "nfs" then
              [{
                name: "nfs",
                persistentVolumeClaim: {
                  claimName: $.params.nfsPVC,
                },
              }]
            else [],
          },
        },
      },
    },  // onnxrtDeployment

    onnxrtService: {
      apiVersion: "v1",
      kind: "Service",
      metadata: {
        labels: $.params.labels,
        name: $.params.name,
        namespace: $.params.namespace,
        annotations: {
          "getambassador.io/config":
            std.join("\n", [
              "---",
              "apiVersion: ambassador/v0",
              "kind:  Mapping",
              "name: onnxrtserving-mapping-" + $.params.name + "-get",
              "prefix: /models/" + $.params.name + "/",
              "rewrite: /",
              "method: GET",
              "service: " + $.params.name + "." + $.params.namespace + ":8000",
              "---",
              "apiVersion: ambassador/v0",
              "kind:  Mapping",
              "name: onnxrtserving-mapping-" + $.params.name + "-post",
              "prefix: /models/" + $.params.name + "/",
              "rewrite: /model/" + $.params.name + ":predict",
              "method: POST",
              "service: " + $.params.name + "." + $.params.namespace + ":8000",
            ]),
        },  //annotations
      },
      spec: {
        ports: [
          {
            name: "grpc-onnxrt-serving",
            port: 9000,
            targetPort: 9000,
          },
          {
            name: "http-onnxrt-serving-proxy",
            port: 8000,
            targetPort: 8000,
          },
        ],
        selector: $.params.labels,
        type: $.params.serviceType,
      },
    },  // onnxrtService

    defaultRouteRule: {
      apiVersion: "config.istio.io/v1alpha2",
      kind: "RouteRule",
      metadata: {
        name: $.params.name + "-default",
        namespace: $.params.namespace,
      },
      spec: {
        destination: {
          name: $.params.name,
        },
        precedence: 0,
        route: [
          {
            labels: { version: $.params.version },
          },
        ],
      },
    },

  },  // parts

  // Parts specific to S3
  s3parts:: $.parts {
    s3Env:: [
      { name: "AWS_ACCESS_KEY_ID", valueFrom: { secretKeyRef: { name: $.s3params.s3SecretName, key: $.s3params.s3SecretAccesskeyidKeyName } } },
      { name: "AWS_SECRET_ACCESS_KEY", valueFrom: { secretKeyRef: { name: $.s3params.s3SecretName, key: $.s3params.s3SecretSecretaccesskeyKeyName } } },
      { name: "AWS_REGION", value: $.s3params.s3AwsRegion },
      { name: "S3_REGION", value: $.s3params.s3AwsRegion },
      { name: "S3_USE_HTTPS", value: $.s3params.s3UseHttps },
      { name: "S3_VERIFY_SSL", value: $.s3params.s3VerifySsl },
      { name: "S3_ENDPOINT", value: $.s3params.s3Endpoint },
    ],

    onnxrtServingContainer: $.parts.onnxrtServingContainer {
      env+: $.s3parts.s3Env,
    },

    onnxrtDeployment: $.parts.onnxrtDeployment {
      spec: +{
        template: +{
          metadata: $.parts.onnxrtServingMetadata,
          spec: +{
            containers: [
              $.s3parts.onnxrtServingContainer,
              if $.util.toBool($.params.deployHttpProxy) then
                $.parts.httpProxyContainer,
            ],
          },
        },
      },
    },  // onnxrtDeployment
  },  // s3parts

  // Parts specific to GCP
  gcpParts:: $.parts {
    gcpEnv:: [
      if $.gcpParams.gcpCredentialSecretName != "" then
        { name: "GOOGLE_APPLICATION_CREDENTIALS", value: "/secret/gcp-credentials/user-gcp-sa.json" },
    ],

    onnxrtServingContainer: $.parts.onnxrtServingContainer {
      env+: $.gcpParts.gcpEnv,
      volumeMounts+: [
        if $.gcpParams.gcpCredentialSecretName != "" then
          {
            name: "gcp-credentials",
            mountPath: "/secret/gcp-credentials",
          },
      ],
    },

    onnxrtDeployment: $.parts.onnxrtDeployment {
      spec+: {
        template+: {
          metadata: $.parts.onnxrtServingMetadata,
          spec+: {
            containers: [
              $.gcpParts.onnxrtServingContainer,
              if $.util.toBool($.params.deployHttpProxy) then
                $.parts.httpProxyContainer,
            ],
            volumes: [
              if $.gcpParams.gcpCredentialSecretName != "" then
                {
                  name: "gcp-credentials",
                  secret: {
                    secretName: $.gcpParams.gcpCredentialSecretName,
                  },
                },
            ],
          },
        },
      },
    },  // onnxrtDeployment
  },  // gcpParts
}
