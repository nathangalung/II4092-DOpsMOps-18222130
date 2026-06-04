// SK-N-03 — horizontal autoscaling under ramping load (validates KNF-03).
// Drives 100 → 1000 QPS against the KServe predictor while HPA (CPU/RPS) and
// KEDA (Kafka lag) scale pods. Observe scaling out-of-band:
//   kubectl -n use-case-crypto get hpa,scaledobject,pods -w
//
// Run:
//   k6 run -e PREDICT_URL=http://crypto-predictor.use-case-crypto.svc/v2/models/crypto-predictor/infer \
//          load/hpa-keda-rampup.js
import http from 'k6/http';
import { check } from 'k6';

const PREDICT_URL =
  __ENV.PREDICT_URL ||
  'http://crypto-predictor.use-case-crypto.svc/v2/models/crypto-predictor/infer';

export const options = {
  scenarios: {
    rampup: {
      executor: 'ramping-arrival-rate',
      startRate: 100,
      timeUnit: '1s',
      preAllocatedVUs: 100,
      maxVUs: 3000,
      stages: [
        { target: 100, duration: '2m' },
        { target: 1000, duration: '8m' },
        { target: 1000, duration: '5m' },
      ],
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
  },
};

export default function () {
  // KServe v2 (Open Inference Protocol) inference payload.
  const body = JSON.stringify({
    inputs: [
      { name: 'input', shape: [1, 5], datatype: 'FP32', data: [1.0, 2.0, 3.0, 4.0, 5.0] },
    ],
  });
  const res = http.post(PREDICT_URL, body, {
    headers: { 'Content-Type': 'application/json' },
  });
  check(res, { 'status is 200': (r) => r.status === 200 });
}
