local onnxrtservingService = import "kubeflow/onnxrt-serving/onnxrt-serving-service-template.libsonnet";
local onnxrtserving = import "kubeflow/onnxrt-serving/onnxrt-serving-template.libsonnet";

local params = {
  name: "m",
  serviceType: "ClusterIP",
  modelName: "mnist",
  trafficRule: "v1:100",
  injectIstio: false,
};

local istioParams = params {
  injectIstio: true,
};

local env = {
  namespace: "kubeflow",
};

local deploymentParam = {
  name: "m",
  modelName: "mnist",
  versionName: "v1",
  modelBasePath: "gs://abc",
  numGpus: 0,
  defaultCpuImage: "gcr.io/abc",
  defaultGpuImage: "gcr.io/abc",
  injectIstio: false,
  enablePrometheus: true,
};

local gpuParam1 = {
  name: "m",
  modelName: "mnist",
  versionName: "v1",
  modelBasePath: "gs://abc",
  numGpus: 1,
  defaultCpuImage: "gcr.io/abc",
  defaultGpuImage: "gcr.io/abc",
  injectIstio: false,
  enablePrometheus: true,
};

local gpuParamString0 = {
  name: "m",
  modelName: "mnist",
  versionName: "v1",
  modelBasePath: "gs://abc",
  numGpus: "0",
  defaultCpuImage: "gcr.io/abc",
  defaultGpuImage: "gcr.io/abc",
  injectIstio: false,
  enablePrometheus: true,
};

local gpuParamString1 = {
  name: "m",
  modelName: "mnist",
  versionName: "v1",
  modelBasePath: "gs://abc",
  numGpus: "1",
  defaultCpuImage: "gcr.io/abc",
  defaultGpuImage: "gcr.io/abc",
  injectIstio: false,
  enablePrometheus: true,
};

local serviceInstance = onnxrtservingService.new(env, params);
local istioServiceInstance = onnxrtservingService.new(env, istioParams);

local deploymentInstance = onnxrtserving.new(env, deploymentParam);

local gpuInstance = onnxrtserving.new(env, gpuParam1);
local gpuString0Instance = onnxrtserving.new(env, gpuParamString0);
local gpuString1Instance = onnxrtserving.new(env, gpuParamString1);

// This one should only have onnxrtService
std.assertEqual(
  std.length(serviceInstance.all.items),
  1,
) &&

// This one should have onnxrtService, virtualService, and DestinationRule
std.assertEqual(
  std.length(istioServiceInstance.all.items),
  3
) &&

std.startsWith(
  deploymentInstance.onnxrtDeployment.spec.template.spec.containers[0].args[4],
  "--monitoring_config_file"
) &&

std.assertEqual(
  deploymentInstance.onnxrtDeployment.spec.template.spec.containers[0].resources.limits,
  { cpu: "4", memory: "4Gi" }
) &&

std.assertEqual(
  gpuInstance.onnxrtDeployment.spec.template.spec.containers[0].resources.limits,
  { cpu: "4", memory: "4Gi", "nvidia.com/gpu": 1 }
) &&

std.assertEqual(
  gpuString0Instance.onnxrtDeployment.spec.template.spec.containers[0].resources.limits,
  { cpu: "4", memory: "4Gi" }
) &&

std.assertEqual(
  gpuString1Instance.onnxrtDeployment.spec.template.spec.containers[0].resources.limits,
  { cpu: "4", memory: "4Gi", "nvidia.com/gpu": 1 }
)
