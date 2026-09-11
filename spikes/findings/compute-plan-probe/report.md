# Compute-plan probe — 2026-09-11T06:26:39Z

| stage | policy | plan load | ops (+const) | preferred cpu/gpu/ane | CPU-only | not CPU | total cost |
|---|---|---|---|---|---|---|---|
| kokoro_decoder_har_post_15s | coreml-cpu+gpu | 1.54 s | 1041 (+1166) | 0/1041/0 | 0 | 0 | 1.0000 |
| kokoro_decoder_har_post_15s | coreml-cpu | 1.10 s | 1041 (+1166) | 1041/0/0 | 1041 | 0 | 1.0000 |

output directory /Users/atharvanayak/Developer/t2s_reader/spikes/findings/compute-plan-probe/
device arm64, 17179 MB, Version 26.2 (Build 25C56), 8 cores, thermal nominal
compute devices: ane, gpu, cpu
stages kokoro_decoder_har_post_15s; policies cpuAndGPU, cpu; timeout 900 s per plan
kokoro_decoder_har_post_15s: compiled stage kept from an earlier run at /Users/atharvanayak/Developer/t2s_reader/Packages/T2SKokoro/.build/compiled-stages-2e878c6a/kokoro_decoder_har_post_15s.mlmodelc/
kokoro_decoder_har_post_15s under coreml-cpu+gpu: loading the compute plan
kokoro_decoder_har_post_15s under coreml-cpu+gpu: plan loaded in 1.54 s; functions main; inputs har, ref_s, x_pre
kokoro_decoder_har_post_15s under coreml-cpu+gpu: 1041 operations (+ 1166 const), 1041 with a device, 1041 with a cost, total estimated cost 1.0000
kokoro_decoder_har_post_15s under coreml-cpu+gpu: preferred gpu 1041; 0 supported by the CPU only; 0 not supported by the CPU
kokoro_decoder_har_post_15s under coreml-cpu+gpu: the ten heaviest operations
  295 ios16.conv_transpose x_13_has_output_shape_cast_fp16: cost 0.0348, preferred gpu, supported [cpu,gpu]
  1371 ios16.conv_transpose input_69_has_output_shape_cast_fp16: cost 0.0314, preferred gpu, supported [cpu,gpu]
  1135 ios16.conv x_49_cast_fp16: cost 0.0278, preferred gpu, supported [cpu,gpu]
  1183 ios16.conv xt_77_cast_fp16: cost 0.0278, preferred gpu, supported [cpu,gpu]
  1272 ios16.conv xt_83_cast_fp16: cost 0.0278, preferred gpu, supported [cpu,gpu]
  1361 ios16.conv xt_89_cast_fp16: cost 0.0278, preferred gpu, supported [cpu,gpu]
  1935 ios16.conv x_83_cast_fp16: cost 0.0139, preferred gpu, supported [cpu,gpu]
  1979 ios16.conv xt_131_cast_fp16: cost 0.0139, preferred gpu, supported [cpu,gpu]
  2068 ios16.conv xt_137_cast_fp16: cost 0.0139, preferred gpu, supported [cpu,gpu]
  2157 ios16.conv xt_cast_fp16: cost 0.0139, preferred gpu, supported [cpu,gpu]
kokoro_decoder_har_post_15s under coreml-cpu+gpu: by operator, the ten heaviest — count, cost, preferred cpu/gpu/ane, not supported by the CPU
  ios16.conv: ×51, cost 0.4004, 0/51/0, 0 not on the CPU
  ios16.add: ×218, cost 0.2147, 0/218/0, 0 not on the CPU
  ios16.mul: ×148, cost 0.1279, 0/148/0, 0 not on the CPU
  ios16.conv_transpose: ×4, cost 0.0662, 0/4/0, 0 not on the CPU
  ios16.sub: ×45, cost 0.0324, 0/45/0, 0 not on the CPU
  ios16.sin: ×50, cost 0.0261, 0/50/0, 0 not on the CPU
  tile: ×96, cost 0.0260, 0/96/0, 0 not on the CPU
  ios16.pow: ×48, cost 0.0260, 0/48/0, 0 not on the CPU
  ios16.reduce_mean: ×88, cost 0.0243, 0/88/0, 0 not on the CPU
  ios16.real_div: ×44, cost 0.0243, 0/44/0, 0 not on the CPU
kokoro_decoder_har_post_15s under coreml-cpu: loading the compute plan
kokoro_decoder_har_post_15s under coreml-cpu: plan loaded in 1.10 s; functions main; inputs har, ref_s, x_pre
kokoro_decoder_har_post_15s under coreml-cpu: 1041 operations (+ 1166 const), 1041 with a device, 1041 with a cost, total estimated cost 1.0000
kokoro_decoder_har_post_15s under coreml-cpu: preferred cpu 1041; 1041 supported by the CPU only; 0 not supported by the CPU
kokoro_decoder_har_post_15s under coreml-cpu: the ten heaviest operations
  1135 ios16.conv x_49_cast_fp16: cost 0.0393, preferred cpu, supported [cpu]
  1183 ios16.conv xt_77_cast_fp16: cost 0.0393, preferred cpu, supported [cpu]
  1272 ios16.conv xt_83_cast_fp16: cost 0.0393, preferred cpu, supported [cpu]
  1361 ios16.conv xt_89_cast_fp16: cost 0.0393, preferred cpu, supported [cpu]
  295 ios16.conv_transpose x_13_has_output_shape_cast_fp16: cost 0.0314, preferred cpu, supported [cpu]
  1371 ios16.conv_transpose input_69_has_output_shape_cast_fp16: cost 0.0283, preferred cpu, supported [cpu]
  1935 ios16.conv x_83_cast_fp16: cost 0.0197, preferred cpu, supported [cpu]
  1979 ios16.conv xt_131_cast_fp16: cost 0.0197, preferred cpu, supported [cpu]
  2068 ios16.conv xt_137_cast_fp16: cost 0.0197, preferred cpu, supported [cpu]
  2157 ios16.conv xt_cast_fp16: cost 0.0197, preferred cpu, supported [cpu]
kokoro_decoder_har_post_15s under coreml-cpu: by operator, the ten heaviest — count, cost, preferred cpu/gpu/ane, not supported by the CPU
  ios16.conv: ×51, cost 0.5655, 51/0/0, 0 not on the CPU
  ios16.mul: ×148, cost 0.1481, 148/0/0, 0 not on the CPU
  ios16.add: ×218, cost 0.1237, 218/0/0, 0 not on the CPU
  ios16.conv_transpose: ×4, cost 0.0597, 4/0/0, 0 not on the CPU
  ios16.sub: ×45, cost 0.0187, 45/0/0, 0 not on the CPU
  ios16.sin: ×50, cost 0.0139, 50/0/0, 0 not on the CPU
  tile: ×96, cost 0.0139, 96/0/0, 0 not on the CPU
  ios16.pow: ×48, cost 0.0139, 48/0/0, 0 not on the CPU
  ios16.reduce_mean: ×88, cost 0.0129, 88/0/0, 0 not on the CPU
  ios16.real_div: ×44, cost 0.0129, 44/0/0, 0 not on the CPU
done
