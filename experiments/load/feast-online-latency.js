// SK-N-01 — Online feature-serving latency benchmark (validates KNF-01).
// p50 < 5 ms, p95 < 8 ms, p99 < 10 ms at sustained load (default 5000 QPS).
//
// Run:
//   k6 run -e FEAST_URL=http://feast.model-lifecycle.svc:6566 \
//          load/feast-online-latency.js
import http from 'k6/http';
import { check } from 'k6';

const FEAST_URL = __ENV.FEAST_URL || 'http://feast.model-lifecycle.svc:6566';
const SYMBOLS = (__ENV.SYMBOLS || 'BTC-USD,ETH-USD,SOL-USD').split(',');
const FEATURE_SERVICE = __ENV.FEATURE_SERVICE || 'crypto_inference_features';
const ENTITY_KEY = __ENV.ENTITY_KEY || 'symbol';

export const options = {
  scenarios: {
    latency: {
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.QPS || 5000),
      timeUnit: '1s',
      duration: __ENV.DURATION || '15m',
      preAllocatedVUs: 200,
      maxVUs: 2000,
    },
  },
  thresholds: {
    // k6 http_req_duration is in milliseconds.
    http_req_duration: ['p(50)<5', 'p(95)<8', 'p(99)<10'],
    http_req_failed: ['rate<0.001'],
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
