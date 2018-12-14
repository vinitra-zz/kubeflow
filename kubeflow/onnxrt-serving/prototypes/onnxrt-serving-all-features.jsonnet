// @apiVersion 0.1
// @name io.ksonnet.pkg.onnxrt-serving
// @description ONNX Runtime serving
// @shortDescription A ONNXRuntime serving deployment
// @param name string Name to give to each of the components

local k = import "k.libsonnet";

// ksonnet appears to require name be a parameter of the prototype which is why we handle it differently.
local name = import "param://name";

// updatedParams includes the namespace from env by default.
local updatedParams = params + env;

local onnxrtServingBase = import "kubeflow/onnxrt-serving/onnxrt-serving.libsonnet";
local onnxrtServing = onnxrtServingBase {
  // Override parameters with user supplied parameters.
  params+: updatedParams {
    name: name,
  },
};

std.prune(k.core.v1.list.new(onnxrtServing.components))
