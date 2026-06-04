// SK-N-02 (feature-serving half) — sustained throughput > 10k QPS/node
// (validates KNF-02). The stream half (1M msg/s on Flink) is driven separately
// via kafka-producer-perf-test against crypto.validated — see the KNF-02 row in
// experiments/README.md.
//
// Run:
//   k6 run -e FEAST_URL=http://feast.model-lifecycle.svc:6566 \
//          load/feast-throughput.js
import http from 'k6/http';
import { check } from 'k6';

const FEAST_URL = __ENV.FEAST_URL || 'http://feast.model-lifecycle.svc:6566';
const SYMBOLS = (__ENV.SYMBOLS || 'BTC-USD,ETH-USD,SOL-USD').split(',');
const FEATURE_SERVICE = __ENV.FEATURE_SERVICE || 'crypto_inference_features';
const ENTITY_KEY = __ENV.ENTITY_KEY || 'symbol';

export const options = {
  scenarios: {
    throughput: {
      executor: 'ramping-arrival-rate',
      startRate: 1000,
      timeUnit: '1s',
      preAllocatedVUs: 500,
      maxVUs: 5000,
      stages: [
        { target: 5000, duration: '2m' },
        { target: 12000, duration: '3m' },
        { target: 12000, duration: '5m' },
      ],
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.001'],
    // Sustained successful request rate must clear the 10k QPS/node target.
    http_reqs: ['rate>10000'],
  },
};

export default function () {
  const entity = SYMBOLS[Math.floor(Math.random() * SYMBOLS.length)];
  const body = JSON.stringify({
    feature_service: FEATURE_SERVICE,
    entities: { [ENTITY_KEY]: [entity] },
  });
  const res = http.post(`${FEAST_URL}/get-online-features`, body, {
    headers: { 'Content-Type': 'application/json' },
  });
  check(res, { 'status is 200': (r) => r.status === 200 });
}
