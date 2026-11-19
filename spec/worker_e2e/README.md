# Local two-Worker acceptance

Runs two real Sidekiq OS processes against local PostgreSQL and Redis. The channel adapter is synthetic and WebMock blocks all HTTP. This is Worker integration acceptance, not live WhatsApp delivery, a real-model evaluation, or a Kubernetes rolling deployment test.

Set `RAILS_ENV=test`, local `POSTGRES_HOST/PORT/USERNAME/PASSWORD`, `POSTGRES_DATABASE` ending in `_worker_rollout_test`, and a dedicated local `REDIS_URL`. Prepare a **disposable** database with `bundle exec rails db:schema:load`; do not point at an existing development or environment database. Run:

```sh
WORKER_E2E_ARTIFACTS=/absolute/ignored/artifact/directory bundle exec ruby spec/worker_e2e/run.rb
```

The runner creates synthetic contacts, uses a random private queue, runs one thread per Worker to demonstrate cross-process behavior, and terminates its own processes. The application callbacks' unrelated queues are not consumed; use a disposable Redis DB. It does not flush Redis. Do not run RSpec against the same database concurrently.

Checks: both Workers consume jobs; duplicate incoming notifications create one message; simultaneous first messages share a conversation; duplicate send jobs call the channel once; two idle-close jobs produce one notice; inbound waits behind closure and enters a new conversation; TERM removes readiness and drains the in-flight job while the surviving Worker continues.

The channel stub never provides a real delivery receipt. External send success followed by process death before persisting `source_id` remains ambiguous; this harness does not claim exactly-once external delivery.
